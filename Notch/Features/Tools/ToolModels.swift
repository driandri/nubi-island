import AppKit
import AVFoundation
import Combine
import Foundation
import IOKit.pwr_mgt

enum QuickActionID: String, CaseIterable, Identifiable {
    case home, music, timer, calendar, clipboard, shelf, screenshot, launcher, todos, calculator, battery, system, snapLeft, snapRight, snapTopLeft, snapTopRight, snapBottomLeft, snapBottomRight, snapFull
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Home"
        case .music: "Music"
        case .timer: "Timer"
        case .calendar: "Calendar"
        case .clipboard: "Clipboard"
        case .shelf: "File Shelf"
        case .screenshot: "Capture Screenshot"
        case .launcher: "Launcher"
        case .todos: "To-do"
        case .calculator: "Calculator"
        case .battery: "Battery"
        case .system: "System Stats"
        case .snapLeft: "Snap Left"
        case .snapRight: "Snap Right"
        case .snapTopLeft: "Snap Top Left"
        case .snapTopRight: "Snap Top Right"
        case .snapBottomLeft: "Snap Bottom Left"
        case .snapBottomRight: "Snap Bottom Right"
        case .snapFull: "Snap Full Screen"
        }
    }
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .music: "music.note"
        case .timer: "timer"
        case .calendar: "calendar"
        case .clipboard: "doc.on.clipboard"
        case .shelf: "tray"
        case .screenshot: "camera.viewfinder"
        case .launcher: "square.grid.2x2"
        case .todos: "checklist"
        case .calculator: "plus.forwardslash.minus"
        case .battery: "battery.100percent"
        case .system: "desktopcomputer"
        default: "rectangle.split.2x2"
        }
    }
    static func search(_ query: String) -> [Self] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? allCases : allCases.filter { $0.title.localizedStandardContains(query) }
    }
}

struct TodoItem: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var isComplete: Bool
    var createdAt: Date
}

@MainActor
final class TodoModel: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    @Published private(set) var error: String?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notch", isDirectory: true).appendingPathComponent("todos.json")
        do {
            let data = try Data(contentsOf: self.fileURL)
            items = try JSONDecoder().decode([TodoItem].self, from: data)
        } catch CocoaError.fileReadNoSuchFile { } catch { self.error = "Couldn't load to-do items: \(error.localizedDescription)" }
    }
    var openCount: Int { items.filter { !$0.isComplete }.count }
    func add(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        items.insert(TodoItem(id: UUID(), title: title, isComplete: false, createdAt: .now), at: 0)
        save()
    }
    func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isComplete.toggle()
        save()
    }
    func remove(_ id: UUID) { items.removeAll { $0.id == id }; save() }
    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: fileURL, options: .atomic)
            error = nil
        } catch { self.error = "Couldn't save to-do items: \(error.localizedDescription)" }
    }
}

struct LaunchableApp: Identifiable, Equatable {
    var id: String { bundleID ?? url.path }
    let name: String
    let bundleID: String?
    let url: URL
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published private(set) var apps: [LaunchableApp] = []
    @Published private(set) var error: String?
    @Published private(set) var pinnedIDs: [String]
    private let roots: [URL]
    private let defaults: UserDefaults
    init(roots: [URL]? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinnedIDs = defaults.stringArray(forKey: "notch.launcher.pinned") ?? []
        self.roots = roots ?? [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
                               FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        refresh()
    }
    func refresh() {
        var found: [String: LaunchableApp] = [:]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                enumerator.skipDescendants()
                let bundle = Bundle(url: url)
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let app = LaunchableApp(name: name, bundleID: bundle?.bundleIdentifier, url: url)
                found[app.id] = app
            }
        }
        apps = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func results(for query: String) -> [LaunchableApp] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = q.isEmpty ? apps : apps.filter { $0.name.localizedStandardContains(q) }
        return Array(matches.sorted {
            let left = pinnedIDs.firstIndex(of: $0.id) ?? Int.max
            let right = pinnedIDs.firstIndex(of: $1.id) ?? Int.max
            return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left < right
        }.prefix(30))
    }
    func isPinned(_ app: LaunchableApp) -> Bool { pinnedIDs.contains(app.id) }
    func togglePin(_ app: LaunchableApp) {
        if let index = pinnedIDs.firstIndex(of: app.id) { pinnedIDs.remove(at: index) }
        else { pinnedIDs.append(app.id) }
        defaults.set(pinnedIDs, forKey: "notch.launcher.pinned")
    }
    func movePinned(_ app: LaunchableApp, by offset: Int) {
        guard let index = pinnedIDs.firstIndex(of: app.id), pinnedIDs.indices.contains(index + offset) else { return }
        pinnedIDs.swapAt(index, index + offset)
        defaults.set(pinnedIDs, forKey: "notch.launcher.pinned")
    }
    func open(_ app: LaunchableApp) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            Task { @MainActor in self?.error = error?.localizedDescription }
        }
    }
}

struct CalculatorEngine: Equatable {
    private(set) var display = "0"
    private var stored: Decimal?
    private var operation: String?
    private var startsNew = true
    private(set) var error: String?
    mutating func input(_ key: String) {
        if key == "C" { self = Self(); return }
        if key == "⌫" {
            if error != nil { self = Self(); return }
            display = display.count > 1 ? String(display.dropLast()) : "0"
            return
        }
        if key == "±" { if display != "0" { display = display.hasPrefix("-") ? String(display.dropFirst()) : "-" + display }; return }
        if key == "%" {
            guard let number = Decimal(string: display) else { return }
            show(number / 100); return
        }
        if key == "." {
            if startsNew { display = "0"; startsNew = false }
            if !display.contains(".") { display += "." }
            return
        }
        if key.count == 1, let digit = key.first, digit.isNumber {
            if error != nil { self = Self() }
            display = startsNew || display == "0" ? key : display + key
            startsNew = false
            return
        }
        if ["+", "−", "×", "÷"].contains(key) {
            if stored != nil && !startsNew { calculate() }
            stored = Decimal(string: display)
            operation = key
            startsNew = true
            return
        }
        if key == "=" { calculate(); operation = nil; stored = nil; startsNew = true }
    }
    private mutating func calculate() {
        guard let lhs = stored, let rhs = Decimal(string: display), let operation else { return }
        if operation == "÷" && rhs == 0 { error = "Cannot divide by zero"; display = "Error"; return }
        let result: Decimal
        switch operation {
        case "+": result = lhs + rhs
        case "−": result = lhs - rhs
        case "×": result = lhs * rhs
        default: result = lhs / rhs
        }
        show(result)
    }
    private mutating func show(_ number: Decimal) {
        let value = NSDecimalNumber(decimal: number)
        display = value == .notANumber ? "Error" : value.stringValue
        error = value == .notANumber ? "Invalid result" : nil
        startsNew = true
    }
}

@MainActor
final class QuickNoteModel: ObservableObject {
    @Published var text: String = "" { didSet { scheduleSave() } }
    @Published private(set) var error: String?
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notch", isDirectory: true).appendingPathComponent("quick-note.txt")
        do { text = try String(contentsOf: self.fileURL, encoding: .utf8) }
        catch CocoaError.fileReadNoSuchFile { }
        catch { self.error = "Could not load Quick Notes: \(error.localizedDescription)" }
    }
    var preview: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first.map(String.init) ?? "Tulis catatan singkat"
    }
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }
    func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            error = nil
        } catch { self.error = "Could not save Quick Notes: \(error.localizedDescription)" }
    }
    func stop() { saveTask?.cancel(); save() }
}

@MainActor
final class KeepAwakeModel: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var status = "Klik agar layar tetap menyala"
    private var assertion: IOPMAssertionID = 0
    func toggle() { active ? stop() : start() }
    func start() {
        guard !active else { return }
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Nubi Keep Awake" as CFString, &assertion)
        active = result == kIOReturnSuccess
        status = active ? "Klik untuk matikan" : "Gagal menjaga layar tetap menyala (kode \(result))"
    }
    func stop() {
        if active { IOPMAssertionRelease(assertion) }
        assertion = 0; active = false; status = "Klik agar layar tetap menyala"
    }
}

@MainActor
final class CapturePreviewModel: ObservableObject {
    @Published private(set) var cameraStatus = "Camera off"
    @Published private(set) var microphoneStatus = "Microphone off"
    @Published private(set) var cameraActive = false
    @Published private(set) var microphoneActive = false
    @Published private(set) var microphoneLevel: Float = 0
    let cameraSession = AVCaptureSession()
    private final class SessionBox: @unchecked Sendable {
        let session: AVCaptureSession
        init(_ session: AVCaptureSession) { self.session = session }
    }
    private let cameraQueue = DispatchQueue(label: "notch.camera.preview")
    private var cameraGeneration = 0
    private let audioEngine = AVAudioEngine()

    func startCamera() async {
        guard !cameraActive else { return }
        cameraGeneration += 1
        let token = cameraGeneration
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard allowed else { cameraStatus = "Camera denied. Allow it in System Settings → Privacy & Security → Camera."; return }
        guard let device = AVCaptureDevice.default(for: .video) else { cameraStatus = "No camera available"; return }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            cameraSession.beginConfiguration()
            cameraSession.inputs.forEach(cameraSession.removeInput)
            if cameraSession.canAddInput(input) { cameraSession.addInput(input) }
            cameraSession.commitConfiguration()
            guard !cameraSession.inputs.isEmpty else { cameraStatus = "Camera unavailable"; return }
            let box = SessionBox(cameraSession)
            await withCheckedContinuation { continuation in
                cameraQueue.async { box.session.startRunning(); continuation.resume() }
            }
            guard token == cameraGeneration else {
                cameraQueue.async { box.session.stopRunning() }
                return
            }
            cameraActive = true
            cameraStatus = "Camera preview only · nothing is saved"
        } catch { cameraStatus = error.localizedDescription }
    }
    func stopCamera() {
        cameraGeneration += 1
        let box = SessionBox(cameraSession)
        cameraQueue.async { if box.session.isRunning { box.session.stopRunning() } }
        cameraActive = false
        cameraStatus = "Camera off"
    }
    func startMicrophone() async {
        guard !microphoneActive else { return }
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard allowed else { microphoneStatus = "Microphone denied. Allow it in System Settings → Privacy & Security → Microphone."; return }
        do {
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0 else { microphoneStatus = "No microphone available"; return }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
                let samples = UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength))
                let rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(buffer.frameLength))
                Task { @MainActor [weak self] in self?.microphoneLevel = min(1, rms * 8) }
            }
            try audioEngine.start()
            microphoneActive = true
            microphoneStatus = "Input level only · nothing is recorded"
        } catch { microphoneStatus = error.localizedDescription; audioEngine.inputNode.removeTap(onBus: 0) }
    }
    func stopMicrophone() {
        if microphoneActive { audioEngine.inputNode.removeTap(onBus: 0) }
        audioEngine.stop()
        microphoneActive = false
        microphoneLevel = 0
        microphoneStatus = "Microphone off"
    }
    func stop() { stopCamera(); stopMicrophone() }
}
