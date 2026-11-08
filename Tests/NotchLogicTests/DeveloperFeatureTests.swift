import Foundation
import XCTest
@testable import NotchTools

final class DeveloperFeatureTests: XCTestCase {
    func testGitOverviewTracksRealRepositoryChanges() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nubi-git-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try git(["init", "-q"], at: folder)
        let tracked = folder.appendingPathComponent("tracked.txt")
        try "first\n".write(to: tracked, atomically: true, encoding: .utf8)
        try git(["add", "tracked.txt"], at: folder)
        try git(["-c", "user.name=Nubi Test", "-c", "user.email=nubi@example.invalid", "commit", "-qm", "initial"], at: folder)

        let clean = try XCTUnwrap(GitStatusReader.read(at: folder))
        XCTAssertTrue(clean.isClean)

        try "staged\n".write(to: tracked, atomically: true, encoding: .utf8)
        try git(["add", "tracked.txt"], at: folder)
        try "unstaged\n".write(to: tracked, atomically: true, encoding: .utf8)
        try "new\n".write(to: folder.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        let changed = try XCTUnwrap(GitStatusReader.read(at: folder))
        XCTAssertEqual(changed.branch, clean.branch)
        XCTAssertEqual(changed.staged, 1)
        XCTAssertEqual(changed.unstaged, 1)
        XCTAssertEqual(changed.untracked, 1)
        XCTAssertFalse(changed.isClean)
    }

    func testUnbornBranchNameIsReadable() {
        XCTAssertEqual(GitOverview.parse("## No commits yet on main\n")?.branch, "main")
        XCTAssertEqual(GitOverview.parse("## Initial commit on feature\n")?.branch, "feature")
    }

    @MainActor
    func testMissingProjectFolderReportsRecoverableError() {
        let suite = "nubi-developer-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DeveloperWorkspaceModel(defaults: defaults)
        model.add(FileManager.default.temporaryDirectory.appendingPathComponent("nubi-missing-\(UUID().uuidString)"))
        XCTAssertNotNil(model.gitError)
        XCTAssertFalse(model.isRefreshing)
    }

    @MainActor
    func testAgentEventsRespectTimeAndProviderConnection() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nubi-agent-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date().timeIntervalSince1970

        try writeEvent("z-start.json", provider: "codex", event: "SessionStart", session: "ended", time: now - 3, to: folder)
        try writeEvent("a-end.json", provider: "codex", event: "SessionEnd", session: "ended", time: now - 1, to: folder)
        try writeEvent("b-claude.json", provider: "claude", event: "Notification", session: "waiting", time: now - 2, to: folder)
        try writeEvent("c-gemini.json", provider: "gemini", event: "BeforeTool", session: "working", time: now, to: folder)

        let model = DeveloperAgentModel(folder: folder, connectedProviders: Set(DeveloperAgentProvider.allCases))
        model.refresh()
        XCTAssertEqual(model.sessions.count, 2)
        XCTAssertEqual(model.sessions.first(where: { $0.provider == .claude })?.state, .waiting)
        XCTAssertEqual(model.sessions.first(where: { $0.provider == .gemini })?.state, .working)
        XCTAssertFalse(model.sessions.contains { $0.provider == .codex })
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)

        try writeEvent("older.json", provider: "claude", event: "UserPromptSubmit", session: "older",
                       time: now - 300, to: folder)
        model.refresh()
        let older = try XCTUnwrap(model.sessions.first { $0.id == "claude:older" })
        XCTAssertEqual(older.state, .working)
        XCTAssertEqual(older.updatedAt.timeIntervalSince1970, now - 300, accuracy: 0.001)

        try writeEvent("disabled.json", provider: "codex", event: "PreToolUse", session: "hidden", time: now, to: folder)
        let disconnected = DeveloperAgentModel(folder: folder, connectedProviders: [])
        disconnected.refresh()
        XCTAssertTrue(disconnected.sessions.isEmpty)
    }

    @MainActor
    func testGeminiHookConnectAndDisconnectPreserveOtherSettings() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nubi-hook-config-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = folder.appendingPathComponent("settings.json")
        let script = folder.appendingPathComponent("nubi-agent-hook.py")
        let events = folder.appendingPathComponent("agent-events", isDirectory: true)
        try FileManager.default.createDirectory(at: events, withIntermediateDirectories: true)
        try "pass\n".write(to: script, atomically: true, encoding: .utf8)
        let original: [String: Any] = [
            "theme": "custom",
            "hooks": ["BeforeTool": [["matcher": "Bash", "hooks": [["type": "command", "command": "echo keep"]]]]]
        ]
        try JSONSerialization.data(withJSONObject: original).write(to: settings)
        let model = DeveloperAgentModel(folder: events, scriptURL: script, settingsURLs: [.gemini: settings])

        model.connect(.gemini)
        XCTAssertTrue(model.isConnected(.gemini))
        let connected = try readSettings(settings)
        let hooks = try XCTUnwrap(connected["hooks"] as? [String: [[String: Any]]])
        let beforeTool = try XCTUnwrap(hooks["BeforeTool"])
        XCTAssertEqual(beforeTool.count, 2)
        let nubiHandler = try XCTUnwrap((beforeTool.last?["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(nubiHandler["timeout"] as? Int, 3_000)
        let permissions = try FileManager.default.attributesOfItem(atPath: settings.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        var disabledSettings = connected
        var disabledHooks = try XCTUnwrap(disabledSettings["hooks"] as? [String: Any])
        disabledHooks["disabled"] = ["nubi-gemini-BeforeTool"]
        disabledSettings["hooks"] = disabledHooks
        try JSONSerialization.data(withJSONObject: disabledSettings).write(to: settings)
        XCTAssertFalse(model.isConnected(.gemini))
        try writeEvent("disabled.json", provider: "gemini", event: "BeforeTool", session: "disabled",
                       time: Date().timeIntervalSince1970, to: events)
        model.refresh()
        XCTAssertTrue(model.sessions.isEmpty)
        model.connect(.gemini)
        XCTAssertEqual(model.message, "Hook Nubi dinonaktifkan di pengaturan Gemini. Aktifkan lewat /hooks agar status terlihat.")
        let reconnected = try readSettings(settings)
        XCTAssertEqual(((reconnected["hooks"] as? [String: Any])?["BeforeTool"] as? [[String: Any]])?.count, 2)

        model.disconnect(.gemini)
        XCTAssertFalse(model.isConnected(.gemini))
        let disconnected = try readSettings(settings)
        XCTAssertEqual(disconnected["theme"] as? String, "custom")
        XCTAssertEqual((disconnected["hooks"] as? [String: Any])?["disabled"] as? [String], ["nubi-gemini-BeforeTool"])
        let remaining = try XCTUnwrap((disconnected["hooks"] as? [String: Any])?["BeforeTool"] as? [[String: Any]])
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(((remaining.first?["hooks"] as? [[String: Any]])?.first)?["command"] as? String, "echo keep")
    }

    @MainActor
    func testClaudeAndCodexHooksKeepExistingHandlers() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nubi-hook-providers-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("nubi-agent-hook.py")
        try "pass\n".write(to: script, atomically: true, encoding: .utf8)

        for provider in [DeveloperAgentProvider.claude, .codex] {
            let settings = folder.appendingPathComponent("\(provider.rawValue)-settings.json")
            let original: [String: Any] = ["theme": "keep", "hooks": [
                "PreToolUse": [["hooks": [["type": "command", "command": "echo keep"]]]]
            ]]
            try JSONSerialization.data(withJSONObject: original).write(to: settings)
            let model = DeveloperAgentModel(folder: folder, scriptURL: script, settingsURLs: [provider: settings])

            model.connect(provider)
            XCTAssertTrue(model.isConnected(provider))
            let connected = try readSettings(settings)
            let hooks = try XCTUnwrap(connected["hooks"] as? [String: [[String: Any]]])
            for event in provider.events {
                let entry = try XCTUnwrap(hooks[event]?.last)
                let handler = try XCTUnwrap((entry["hooks"] as? [[String: Any]])?.first)
                XCTAssertEqual(handler["timeout"] as? Int, 3)
                XCTAssertEqual(handler["name"] as? String, "nubi-\(provider.rawValue)-\(event)")
            }

            model.disconnect(provider)
            XCTAssertFalse(model.isConnected(provider))
            let disconnected = try readSettings(settings)
            XCTAssertEqual(disconnected["theme"] as? String, "keep")
            let remaining = try XCTUnwrap((disconnected["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])
            XCTAssertEqual(remaining.count, 1)
            XCTAssertEqual(((remaining[0]["hooks"] as? [[String: Any]])?.first)?["command"] as? String, "echo keep")
        }
    }

    private func readSettings(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func writeEvent(_ name: String, provider: String, event: String, session: String,
                            time: TimeInterval, to folder: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "provider": provider, "event": event, "session": session, "cwd": folder.path,
            "detail": "", "time": time
        ])
        try data.write(to: folder.appendingPathComponent(name))
    }

    private func git(_ arguments: [String], at folder: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments) failed")
    }
}
