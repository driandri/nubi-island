import Combine
import Foundation

enum DeveloperAgentProvider: String, CaseIterable, Identifiable, Sendable {
    case claude, codex, gemini
    var id: String { rawValue }
    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .gemini: "Gemini CLI"
        }
    }
    var settingsURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return switch self {
        case .claude: home.appendingPathComponent(".claude/settings.json")
        case .codex: home.appendingPathComponent(".codex/hooks.json")
        case .gemini: home.appendingPathComponent(".gemini/settings.json")
        }
    }
    var events: [String] {
        switch self {
        case .claude: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification", "Stop", "StopFailure", "SessionEnd"]
        case .codex: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]
        case .gemini: ["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification", "AfterAgent", "SessionEnd"]
        }
    }
}

struct DeveloperAgentSession: Identifiable, Equatable, Sendable {
    enum State: String, Sendable {
        case idle, working, waiting, finished, failed

        var label: String {
            switch self {
            case .idle: "Siap"
            case .working: "Bekerja"
            case .waiting: "Menunggu"
            case .finished: "Selesai"
            case .failed: "Gagal"
            }
        }
    }
    let id: String
    let provider: DeveloperAgentProvider
    let projectPath: String
    var state: State
    var detail: String
    var updatedAt: Date
}

private struct AgentHookRecord: Decodable {
    let provider: String
    let event: String
    let session: String
    let cwd: String
    let detail: String
    let time: TimeInterval
}

@MainActor
final class DeveloperAgentModel: ObservableObject {
    @Published private(set) var sessions: [DeveloperAgentSession] = []
    @Published private(set) var message: String?
    private let folder: URL
    private let connectedProvidersOverride: Set<DeveloperAgentProvider>?
    private let scriptURL: URL?
    private let settingsURLs: [DeveloperAgentProvider: URL]
    private var timer: Timer?

    init(folder: URL? = nil, connectedProviders: Set<DeveloperAgentProvider>? = nil,
         scriptURL: URL? = nil, settingsURLs: [DeveloperAgentProvider: URL] = [:]) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notch/agent-events", isDirectory: true)
        self.connectedProvidersOverride = connectedProviders
        self.scriptURL = scriptURL ?? Bundle.main.url(forResource: "nubi-agent-hook", withExtension: "py")
        self.settingsURLs = settingsURLs
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }

    func stop() { timer?.invalidate(); timer = nil; sessions = [] }

    func isConnected(_ provider: DeveloperAgentProvider) -> Bool {
        if let connectedProvidersOverride { return connectedProvidersOverride.contains(provider) }
        guard let script = scriptURL,
              let document = try? readSettings(settingsURL(for: provider)),
              let hooks = document["hooks"] as? [String: Any] else { return false }
        if provider == .gemini {
            let disabled = Set(hooks["disabled"] as? [String] ?? [])
            if provider.events.contains(where: { disabled.contains("nubi-gemini-\($0)") }) { return false }
        }
        return provider.events.allSatisfy { event in
            let command = hookCommand(provider, event: event, script: script)
            let entries = hooks[event] as? [[String: Any]] ?? []
            return entries.contains { entry in
                ((entry["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String) == command }
            }
        }
    }

    func connect(_ provider: DeveloperAgentProvider) {
        guard let script = scriptURL else {
            message = "Helper agen tidak ditemukan di bundle Nubi."
            return
        }
        do {
            var document = try readSettings(settingsURL(for: provider))
            var hooks = document["hooks"] as? [String: Any] ?? [:]
            for event in provider.events {
                var entries = hooks[event] as? [[String: Any]] ?? []
                let command = hookCommand(provider, event: event, script: script)
                if !entries.contains(where: { entry in
                    ((entry["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String) == command }
                }) {
                    entries.append(["hooks": [["type": "command", "name": "nubi-\(provider.rawValue)-\(event)",
                                               "command": command, "timeout": provider == .gemini ? 3_000 : 3]]])
                }
                hooks[event] = entries
            }
            document["hooks"] = hooks
            try writeSettings(document, to: settingsURL(for: provider))
            if provider == .gemini && !isConnected(provider) {
                message = "Hook Nubi dinonaktifkan di pengaturan Gemini. Aktifkan lewat /hooks agar status terlihat."
            } else {
                message = provider == .codex
                    ? "Hook Codex terpasang. Buka /hooks di Codex dan percaya hook Nubi agar aktif."
                    : "Hook \(provider.title) terpasang. Mulai sesi baru agar status terlihat."
            }
        } catch {
            message = "Gagal memasang hook \(provider.title): \(error.localizedDescription)"
        }
    }

    func disconnect(_ provider: DeveloperAgentProvider) {
        guard let script = scriptURL else {
            message = "Helper agen tidak ditemukan di bundle Nubi."
            return
        }
        do {
            var document = try readSettings(settingsURL(for: provider))
            var hooks = document["hooks"] as? [String: Any] ?? [:]
            for event in provider.events {
                guard let entries = hooks[event] as? [[String: Any]] else { continue }
                let command = hookCommand(provider, event: event, script: script)
                var retained: [[String: Any]] = []
                for var entry in entries {
                    guard let handlers = entry["hooks"] as? [[String: Any]] else { retained.append(entry); continue }
                    let remaining = handlers.filter { ($0["command"] as? String) != command }
                    if !remaining.isEmpty {
                        entry["hooks"] = remaining
                        retained.append(entry)
                    }
                }
                if retained.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = retained }
            }
            document["hooks"] = hooks
            try writeSettings(document, to: settingsURL(for: provider))
            sessions.removeAll { $0.provider == provider }
            message = "Koneksi \(provider.title) dilepas."
        } catch {
            message = "Gagal melepas hook \(provider.title): \(error.localizedDescription)"
        }
    }

    func refresh() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) else { return }
        let records: [(URL, AgentHookRecord)] = files.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                  let record = try? JSONDecoder().decode(AgentHookRecord.self, from: data) else {
                try? FileManager.default.removeItem(at: file)
                return nil
            }
            return (file, record)
        }.sorted { $0.1.time < $1.1.time }
        let connected = Set(DeveloperAgentProvider.allCases.filter { isConnected($0) })
        let now = Date()
        for (file, record) in records.prefix(100) {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let provider = DeveloperAgentProvider(rawValue: record.provider),
                  connected.contains(provider),
                  record.time <= now.timeIntervalSince1970 + 60,
                  now.timeIntervalSince1970 - record.time < 3600 else { continue }
            let eventDate = Date(timeIntervalSince1970: record.time)
            let id = "\(provider.rawValue):\(record.session.isEmpty ? record.cwd : record.session)"
            let state: DeveloperAgentSession.State
            switch record.event {
            case "SessionStart": state = .idle
            case "Notification", "PermissionRequest": state = .waiting
            case "Stop", "AfterAgent": state = .finished
            case "StopFailure", "PostToolUseFailure", "AfterToolFailure": state = .failed
            case "SessionEnd":
                sessions.removeAll { $0.id == id }
                continue
            default: state = .working
            }
            if let index = sessions.firstIndex(where: { $0.id == id }) {
                sessions[index].state = state
                if !record.detail.isEmpty { sessions[index].detail = record.detail }
                sessions[index].updatedAt = eventDate
            } else {
                sessions.append(DeveloperAgentSession(id: id, provider: provider,
                    projectPath: record.cwd, state: state, detail: record.detail, updatedAt: eventDate))
            }
        }
        sessions.removeAll { now.timeIntervalSince($0.updatedAt) > ($0.state == .working || $0.state == .waiting ? 3600 : 30) }
        sessions.sort { $0.updatedAt > $1.updatedAt }
    }

    private func readSettings(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let object = value as? [String: Any] else { throw CocoaError(.coderInvalidValue) }
        return object
    }

    private func writeSettings(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".nubi-\(UUID().uuidString)")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        do {
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try file.write(contentsOf: data)
            try file.close()
            guard rename(temporary.path, url.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func hookCommand(_ provider: DeveloperAgentProvider, event: String, script: URL) -> String {
        "/usr/bin/python3 \(shellQuote(script.path)) \(provider.rawValue) \(event)"
    }

    private func settingsURL(for provider: DeveloperAgentProvider) -> URL {
        settingsURLs[provider] ?? provider.settingsURL
    }

    private func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
