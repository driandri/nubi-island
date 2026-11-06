import AppKit
import ApplicationServices
import Combine

struct ClipboardEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case text, color, link }
    let kind: Kind
    let value: String
    var isPinned = false
    var id: String { "\(kind.rawValue)-\(value)" }
    var label: String {
        switch kind { case .text: "Text"; case .color: "Color"; case .link: "Link" }
    }
    static func from(_ raw: String) -> ClipboardEntry? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 16_384 else { return nil }
        if value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil {
            return ClipboardEntry(kind: .color, value: value.uppercased())
        }
        if let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
            return ClipboardEntry(kind: .link, value: value)
        }
        return ClipboardEntry(kind: .text, value: value)
    }
}

struct ClipboardHistoryStore {
    static let capacity = 30
    private(set) var entries: [ClipboardEntry] = []
    mutating func add(_ entry: ClipboardEntry) {
        var incoming = entry
        if let old = entries.first(where: { $0.id == entry.id }) { incoming.isPinned = old.isPinned }
        entries.removeAll { $0.id == entry.id }
        entries.insert(incoming, at: 0)
        while entries.count > Self.capacity {
            guard let oldestUnpinned = entries.lastIndex(where: { !$0.isPinned }) else { break }
            entries.remove(at: oldestUnpinned)
        }
    }
    mutating func setPinned(_ id: String, to pinned: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isPinned = pinned
    }
    mutating func clear() { entries.removeAll() }
    func filtered(_ query: String) -> [ClipboardEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { needle.isEmpty || $0.value.localizedStandardContains(needle) }
            .sorted { $0.isPinned && !$1.isPinned }
    }
}

@MainActor
final class ClipboardHistoryModel: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var searchQuery = ""
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            if enabled { loadSaved(); start() }
            else { stop(); store.clear(); entries = []; removeSaved() }
        }
    }
    @Published var persistHistory: Bool {
        didSet {
            defaults.set(persistHistory, forKey: Self.persistKey)
            if persistHistory && enabled { save() }
            else { removeSaved() }
        }
    }
    @Published var ignoredApps: [String] {
        didSet {
            ignoredApps = Array(Set(ignoredApps.filter { !$0.isEmpty })).sorted()
            defaults.set(ignoredApps, forKey: Self.ignoredKey)
        }
    }
    @Published private(set) var storageError: String?
    private static let enabledKey = "notch.clipboard.enabled"
    private static let persistKey = "notch.clipboard.persist"
    private static let ignoredKey = "notch.clipboard.ignoredApps"
    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private let fileURL: URL
    private let frontmostBundleID: () -> String?
    private var timer: Timer?
    private var lastChangeCount: Int
    private var store = ClipboardHistoryStore()

    init(defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general, fileURL: URL? = nil,
         frontmostBundleID: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }) {
        self.defaults = defaults; self.pasteboard = pasteboard; self.frontmostBundleID = frontmostBundleID
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notch", isDirectory: true).appendingPathComponent("clipboard-history.json")
        enabled = defaults.bool(forKey: Self.enabledKey)
        persistHistory = defaults.bool(forKey: Self.persistKey)
        ignoredApps = defaults.stringArray(forKey: Self.ignoredKey) ?? []
        lastChangeCount = pasteboard.changeCount
        if enabled { loadSaved(); start() }
    }
    var visibleEntries: [ClipboardEntry] { store.filtered(searchQuery) }
    func setPinned(_ entry: ClipboardEntry, to pinned: Bool) {
        store.setPinned(entry.id, to: pinned); entries = store.entries; save()
    }
    func addIgnoredApp(_ bundleID: String) {
        guard !bundleID.isEmpty, !ignoredApps.contains(bundleID) else { return }
        ignoredApps.append(bundleID)
    }
    func removeIgnoredApp(_ bundleID: String) { ignoredApps.removeAll { $0 == bundleID } }
    private func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scan() }
        }
    }
    private func scan() {
        guard enabled, pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        if let bundleID = frontmostBundleID(), ignoredApps.contains(bundleID) { return }
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard !types.contains(where: { $0.localizedCaseInsensitiveContains("concealed") || $0.localizedCaseInsensitiveContains("transient") }),
              !types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) else { return }
        let entry: ClipboardEntry?
        if types.contains(NSPasteboard.PasteboardType.color.rawValue),
           let color = NSColor(from: pasteboard)?.usingColorSpace(.deviceRGB) {
            let hex = String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                             Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
            entry = ClipboardEntry(kind: .color, value: hex)
        } else if let value = pasteboard.string(forType: .string) { entry = ClipboardEntry.from(value) }
        else { entry = nil }
        guard let entry else { return }
        store.add(entry); entries = store.entries; save()
    }
    private func loadSaved() {
        guard persistHistory, let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else { return }
        store.clear()
        for entry in saved.reversed() {
            guard let valid = ClipboardEntry.from(entry.value), valid.kind == entry.kind else { continue }
            store.add(valid)
            store.setPinned(valid.id, to: entry.isPinned)
        }
        entries = store.entries
    }
    private func save() {
        guard enabled && persistHistory else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(store.entries).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            storageError = nil
        } catch { storageError = "Tidak dapat menyimpan riwayat clipboard: \(error.localizedDescription)" }
    }
    private func removeSaved() {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do { try FileManager.default.removeItem(at: fileURL); storageError = nil }
            catch { storageError = "Tidak dapat menghapus riwayat clipboard: \(error.localizedDescription)" }
        }
    }
    func copy(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        pasteboard.setString(entry.value, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }
    @discardableResult func paste(_ entry: ClipboardEntry) -> Bool {
        copy(entry)
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return true
    }
    @discardableResult func pasteVisible(at position: Int) -> Bool {
        let visible = visibleEntries
        guard visible.indices.contains(position) else { return false }
        return paste(visible[position])
    }
    func clear() { store.clear(); entries = []; save() }
    func stop() { timer?.invalidate(); timer = nil; save(); store.clear(); entries = [] }
}
