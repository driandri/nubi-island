import AppKit
import Combine
import CryptoKit
import ScreenCaptureKit
import Vision
import UniformTypeIdentifiers

private final class SendableCaptureFilter: @unchecked Sendable {
    let value: SCContentFilter
    init(_ value: SCContentFilter) { self.value = value }
}

private actor ShelfOCRCache {
    private var values: [String: String] = [:]
    func value(for hash: String) -> String? { values[hash] }
    func set(_ text: String, for hash: String) { values[hash] = text }
    func clear() { values.removeAll() }
}

enum ShelfArchive {
    static func createZIP(files: [URL], destination: URL) throws {
        guard !files.isEmpty, destination.isFileURL else { throw NSError(domain: "Notch", code: 1, userInfo: [NSLocalizedDescriptionKey: "No files to archive"]) }
        let working = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let temporary = working.appendingPathComponent("Nōtch Shelf")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: working) }
        for file in files {
            var name = file.lastPathComponent
            var destinationFile = temporary.appendingPathComponent(name)
            var suffix = 2
            while FileManager.default.fileExists(atPath: destinationFile.path) {
                name = "\(file.deletingPathExtension().lastPathComponent)-\(suffix).\(file.pathExtension)"
                destinationFile = temporary.appendingPathComponent(name)
                suffix += 1
            }
            try FileManager.default.copyItem(at: file, to: destinationFile)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", temporary.path, destination.path]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "Notch", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "ZIP gagal dibuat"])
        }
    }
}

final class ShelfCaptureObserver: NSObject, SCContentSharingPickerObserver, @unchecked Sendable {
    weak var owner: FileShelf?
    init(owner: FileShelf) { self.owner = owner }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in self?.owner?.finishCapture() }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        let selected = SendableCaptureFilter(filter)
        Task { @MainActor [weak self] in self?.owner?.capture(selected.value) }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor [weak self] in self?.owner?.finishCapture(error: error.localizedDescription) }
    }
}

@MainActor
final class FileShelf: ObservableObject {
    static let capacity = 8
    @Published private(set) var files: [URL] = []
    @Published var error: String?
    @Published var searchQuery = ""
    @Published private(set) var recognizedText: [URL: String] = [:]
    @Published private(set) var processingOCR: Set<URL> = []
    @Published private(set) var ocrError: String?
    private let ocrCache = ShelfOCRCache()
    private let exists: (URL) -> Bool
    private let revealInFinder: (URL) -> Void
    private var picker: NSOpenPanel?
    private var captureObserver: ShelfCaptureObserver?

    init(exists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
         revealInFinder: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }) {
        self.exists = exists
        self.revealInFinder = revealInFinder
    }

    func chooseFiles(onAccepted: @escaping @MainActor () -> Void) {
        if let picker { picker.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel()
        panel.title = "Add files to shelf"
        panel.prompt = "Add"
        panel.message = "Keep up to eight file or folder references nearby."
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        picker = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else { return }
            self.picker = nil
            if response == .OK, self.add(panel.urls) { onAccepted() }
        }
    }

    /// A selection succeeds only if at least one existing local file is retained on the shelf.
    /// Duplicate references count as accepted but never consume another slot.
    @discardableResult
    func add(_ urls: [URL]) -> Bool {
        var accepted = false
        var unavailable = 0
        var overflow = 0
        for candidate in urls {
            guard candidate.isFileURL else { unavailable += 1; continue }
            let url = candidate.standardizedFileURL
            guard exists(url) else { unavailable += 1; continue }
            if files.contains(url) { accepted = true; continue }
            guard files.count < Self.capacity else { overflow += 1; continue }
            files.append(url)
            recognize(url)
            accepted = true
        }
        var messages: [String] = []
        if unavailable > 0 { messages.append("\(unavailable) item(s) are not available local files.") }
        if overflow > 0 { messages.append("Shelf full: \(overflow) item(s) skipped (limit \(Self.capacity)).") }
        error = messages.isEmpty ? nil : messages.joined(separator: " ")
        return accepted
    }

    func remove(_ url: URL) {
        files.removeAll { $0 == url.standardizedFileURL }
        recognizedText.removeValue(forKey: url.standardizedFileURL)
        error = nil
    }
    func clear() { files.removeAll(); recognizedText.removeAll(); Task { await ocrCache.clear() }; error = nil; ocrError = nil }

    var searchResults: [URL] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return files }
        return files.filter { $0.lastPathComponent.localizedStandardContains(query)
            || recognizedText[$0, default: ""].localizedStandardContains(query) }
    }

    private func recognize(_ url: URL) {
        guard ["png", "jpg", "jpeg", "tiff", "heic", "bmp", "gif"].contains(url.pathExtension.lowercased()) else { return }
        processingOCR.insert(url)
        let cache = ocrCache
        Task.detached(priority: .utility) { [weak self] in
            var result: (String, String)?
            if let data = try? Data(contentsOf: url) {
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                if let cached = await cache.value(for: hash) { result = (hash, cached) }
                else {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    if (try? VNImageRequestHandler(data: data).perform([request])) != nil {
                        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                        await cache.set(text, for: hash)
                        result = (hash, text)
                    }
                }
            }
            await MainActor.run {
                guard let self else { return }
                self.processingOCR.remove(url)
                guard self.files.contains(url) else { return }
                guard let result else { self.ocrError = "OCR gagal membaca \(url.lastPathComponent)"; return }
                self.recognizedText[url] = result.1
                self.ocrError = nil
            }
        }
    }

    func captureScreenshot() {
        guard captureObserver == nil else { return }
        let observer = ShelfCaptureObserver(owner: self)
        captureObserver = observer
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow, .singleDisplay]
        picker.defaultConfiguration = configuration
        picker.add(observer)
        picker.isActive = true
        NSApp.activate(ignoringOtherApps: true)
        picker.present()
    }

    func finishCapture(error message: String? = nil) {
        let picker = SCContentSharingPicker.shared
        if let captureObserver { picker.remove(captureObserver) }
        captureObserver = nil
        picker.isActive = false
        if let message { error = message }
    }

    func capture(_ filter: SCContentFilter) {
        finishCapture()
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(filter.contentRect.width * CGFloat(filter.pointPixelScale)))
        configuration.height = max(1, Int(filter.contentRect.height * CGFloat(filter.pointPixelScale)))
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { [weak self] image, captureError in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let image else { self.error = captureError?.localizedDescription ?? "Screenshot gagal"; return }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png]
                panel.nameFieldStringValue = "Nubi Screenshot.png"
                NSApp.activate(ignoringOtherApps: true)
                panel.begin { [weak self] response in
                    guard response == .OK, let url = panel.url, let self else { return }
                    do {
                        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                            self.error = "Gagal membuat gambar PNG"; return
                        }
                        try data.write(to: url, options: .atomic)
                        _ = self.add([url])
                    } catch { self.error = error.localizedDescription }
                }
            }
        }
    }

    func createZIP() {
        guard !files.isEmpty else { error = "Tambahkan file ke Shelf terlebih dahulu"; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "Nubi Shelf.zip"
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            let source = self.files
            Task.detached(priority: .utility) {
                do {
                    try ShelfArchive.createZIP(files: source, destination: destination)
                    await MainActor.run { _ = self.add([destination]) }
                } catch { await MainActor.run { self.error = error.localizedDescription } }
            }
        }
    }

    func openZIP(_ url: URL) { NSWorkspace.shared.open(url) }

    func reveal(_ url: URL) {
        let url = url.standardizedFileURL
        guard url.isFileURL, files.contains(url), exists(url) else {
            error = "This file was moved or is no longer available. Remove its reference and drop it again."
            return
        }
        error = nil
        revealInFinder(url)
    }
}
