import AppKit
import Combine
import Foundation

struct DeveloperProject: Codable, Equatable, Identifiable, Sendable {
    let path: String
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var id: String { path }
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

struct GitOverview: Equatable, Sendable {
    let branch: String
    let staged: Int
    let unstaged: Int
    let untracked: Int
    var isClean: Bool { staged + unstaged + untracked == 0 }

    static func parse(_ output: String) -> GitOverview? {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard let heading = lines.first, heading.hasPrefix("## ") else { return nil }
        let headingBranch = String(heading.dropFirst(3)).components(separatedBy: "...").first ?? "HEAD"
        let branch = ["No commits yet on ", "Initial commit on "].first(where: headingBranch.hasPrefix)
            .map { String(headingBranch.dropFirst($0.count)) } ?? headingBranch
        var staged = 0
        var unstaged = 0
        var untracked = 0
        for line in lines.dropFirst() where line.count >= 3 {
            let code = Array(line.prefix(2))
            if code == ["?", "?"] { untracked += 1; continue }
            if code[0] != " " { staged += 1 }
            if code[1] != " " { unstaged += 1 }
        }
        return GitOverview(branch: branch, staged: staged, unstaged: unstaged, untracked: untracked)
    }
}

enum GitStatusReader {
    static func read(at url: URL) throws -> GitOverview? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", url.path, "-c", "core.fsmonitor=false", "status", "--porcelain=v1", "--branch", "--untracked-files=normal"]
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return GitOverview.parse(String(decoding: data, as: UTF8.self))
    }
}

@MainActor
final class DeveloperWorkspaceModel: ObservableObject {
    @Published private(set) var projects: [DeveloperProject]
    @Published private(set) var selectedPath: String?
    @Published private(set) var git: GitOverview?
    @Published private(set) var gitError: String?
    @Published private(set) var isRefreshing = false
    @Published var editorBundleID: String {
        didSet { defaults.set(editorBundleID, forKey: Self.editorKey) }
    }

    private static let projectsKey = "notch.developer.projects"
    private static let selectedKey = "notch.developer.selectedProject"
    private static let editorKey = "notch.developer.editor"
    private let defaults: UserDefaults
    private var refreshID = UUID()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        projects = (defaults.stringArray(forKey: Self.projectsKey) ?? []).map { DeveloperProject(path: $0) }
        selectedPath = defaults.string(forKey: Self.selectedKey)
        editorBundleID = defaults.string(forKey: Self.editorKey) ?? ""
        if !projects.contains(where: { $0.path == selectedPath }) { selectedPath = projects.first?.path }
        refresh()
    }

    var selectedProject: DeveloperProject? { projects.first { $0.path == selectedPath } }

    func add(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !projects.contains(where: { $0.path == path }) else { select(path); return }
        projects.append(DeveloperProject(path: path))
        defaults.set(projects.map(\.path), forKey: Self.projectsKey)
        select(path)
    }

    func select(_ path: String) {
        guard projects.contains(where: { $0.path == path }) else { return }
        selectedPath = path
        defaults.set(path, forKey: Self.selectedKey)
        refresh()
    }

    func remove(_ path: String) {
        projects.removeAll { $0.path == path }
        defaults.set(projects.map(\.path), forKey: Self.projectsKey)
        if selectedPath == path {
            selectedPath = projects.first?.path
            defaults.set(selectedPath, forKey: Self.selectedKey)
            refresh()
        }
    }

    func refresh() {
        refreshID = UUID()
        let id = refreshID
        git = nil
        gitError = nil
        guard let project = selectedProject else { isRefreshing = false; return }
        guard FileManager.default.fileExists(atPath: project.path) else {
            isRefreshing = false
            gitError = "Folder proyek tidak ditemukan. Pilih folder lagi atau hapus dari daftar."
            return
        }
        isRefreshing = true
        Task.detached { [weak self] in
            let result = Result { try GitStatusReader.read(at: project.url) }
            await MainActor.run {
                guard let self, self.refreshID == id else { return }
                self.isRefreshing = false
                switch result {
                case .success(let overview):
                    self.git = overview
                    if overview == nil { self.gitError = "Folder ini bukan repositori Git." }
                case .failure(let error): self.gitError = "Status Git gagal dibaca: \(error.localizedDescription)"
                }
            }
        }
    }

    func revealSelected() {
        guard let selectedProject else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedProject.url])
    }

    func openSelectedInEditor() {
        guard let selectedProject else { return }
        guard !editorBundleID.isEmpty,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editorBundleID) else {
            revealSelected()
            return
        }
        NSWorkspace.shared.open([selectedProject.url], withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}
