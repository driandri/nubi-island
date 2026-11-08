import AppKit
import SwiftUI
@preconcurrency import SwiftTerm

@MainActor
final class DeveloperTerminalModel: NSObject, ObservableObject, @preconcurrency LocalProcessTerminalViewDelegate {
    @Published private(set) var terminalView = LocalProcessTerminalView(frame: .zero)
    @Published private(set) var projectPath: String?
    @Published private(set) var isRunning = false
    @Published private(set) var exitMessage: String?

    func start(in project: DeveloperProject) {
        if isRunning && projectPath == project.path { focus(); return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            exitMessage = "Folder proyek tidak ditemukan. Pilih folder lain di Developer."
            return
        }
        stop()
        let view = LocalProcessTerminalView(frame: .zero)
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = .white
        view.processDelegate = self
        terminalView = view
        projectPath = project.path
        exitMessage = nil
        let candidate = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shell = FileManager.default.isExecutableFile(atPath: candidate) ? candidate : "/bin/zsh"
        view.startProcess(executable: shell, args: ["-l"], currentDirectory: project.path)
        isRunning = true
        focus()
    }

    func focus() {
        let view = terminalView
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }

    func stop() {
        if isRunning { terminalView.terminate() }
        isRunning = false
        projectPath = nil
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard source === terminalView else { return }
        isRunning = false
        exitMessage = exitCode.map { "Shell selesai (kode \($0))." } ?? "Shell berhenti."
    }
}

private struct EmbeddedTerminalView: NSViewRepresentable {
    @ObservedObject var model: DeveloperTerminalModel
    func makeNSView(context: Context) -> LocalProcessTerminalView { model.terminalView }
    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}
}

struct DeveloperHubPanel: View {
    @ObservedObject var workspace: DeveloperWorkspaceModel
    @ObservedObject var launcher: LauncherModel
    @ObservedObject var agents: DeveloperAgentModel
    @ObservedObject var services: DeveloperServiceModel
    var openTerminal: () -> Void
    var openAgentTerminal: (DeveloperAgentSession) -> Void
    @State private var showServices = false
    private let editorIDs = ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.jetbrains.intellij"]

    var body: some View {
        Group {
            if showServices {
                DeveloperServicesPanel(workspace: workspace, services: services) { showServices = false }
            } else {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("DEVELOPER").font(.system(size: 11, weight: .bold)).tracking(1.2)
                Spacer()
                Button("Layanan") { showServices = true }
                Button("Tambah proyek", action: chooseProject)
                    .accessibilityLabel("Tambah folder proyek")
            }
            if workspace.projects.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Belum ada proyek").font(.system(size: 17, weight: .semibold))
                    Text("Tambahkan folder kerja untuk melihat Git dan membuka terminal di lokasi yang tepat.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                    Button("Pilih folder…", action: chooseProject).buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Picker("Proyek", selection: Binding(get: { workspace.selectedPath ?? "" }, set: { workspace.select($0) })) {
                        ForEach(workspace.projects) { project in
                            Text(project.name).tag(project.path)
                        }
                    }.labelsHidden().frame(maxWidth: 280)
                    Spacer()
                    Button { workspace.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Perbarui status Git")
                    if let project = workspace.selectedProject {
                        Button { workspace.remove(project.path) } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel("Hapus proyek dari daftar")
                    }
                }
                if workspace.isRefreshing {
                    ProgressView("Membaca status Git…")
                } else if let git = workspace.git {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(git.branch, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(git.isClean ? "Tidak ada perubahan Git" : "Staged \(git.staged) · Belum staged \(git.unstaged) · Baru \(git.untracked)")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.78))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else if let error = workspace.gitError {
                    Text(error).font(.system(size: 12)).foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    Menu {
                        Button("Finder") { workspace.editorBundleID = "" }
                        ForEach(launcher.apps.filter { $0.bundleID.map(editorIDs.contains) == true }) { app in
                            Button(app.name) { workspace.editorBundleID = app.bundleID ?? "" }
                        }
                    } label: { Label("Editor", systemImage: "chevron.down") }
                    Button("Buka proyek") { workspace.openSelectedInEditor() }
                    Button("Finder") { workspace.revealSelected() }
                    Spacer()
                    Button("Mulai terminal", action: openTerminal).buttonStyle(.borderedProminent)
                }.font(.system(size: 11))
            }
            Divider()
            HStack {
                Text("AGEN AI").font(.system(size: 11, weight: .bold)).tracking(1)
                Spacer()
                ForEach(DeveloperAgentProvider.allCases) { provider in
                    Button(provider.title) {
                        if agents.isConnected(provider) { agents.disconnect(provider) }
                        else { agents.connect(provider) }
                    }
                    .tint(agents.isConnected(provider) ? .green : .white)
                    .accessibilityLabel(agents.isConnected(provider) ? "Lepas koneksi \(provider.title)" : "Hubungkan \(provider.title)")
                    .help(agents.isConnected(provider) ? "Lepas koneksi \(provider.title)" : "Pasang hook \(provider.title)")
                }
            }
            if let message = agents.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.78))
            }
            if agents.sessions.isEmpty {
                Text("Belum ada sesi aktif. Hubungkan CLI di atas dan mulai sesi baru.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(agents.sessions) { session in
                            Button { openAgentTerminal(session) } label: {
                                HStack {
                                    Text(session.provider.title).fontWeight(.semibold)
                                    Text(session.state.label)
                                    Spacer()
                                    Text(session.detail.isEmpty ? URL(fileURLWithPath: session.projectPath).lastPathComponent : session.detail)
                                        .lineLimit(1)
                                    Image(systemName: "terminal")
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.88))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Buka terminal untuk sesi \(session.provider.title)")
                            .disabled(!canOpenTerminal(for: session))
                            .help(canOpenTerminal(for: session) ? "Buka terminal di folder sesi" : "Folder sesi tidak tersedia")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .onAppear { refreshServices() }
        .onChange(of: workspace.selectedPath) { _, _ in refreshServices() }
        .onChange(of: workspace.git) { _, _ in refreshServices() }
    }

    private func refreshServices() {
        services.refresh(project: workspace.selectedProject, branch: workspace.git?.branch)
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Tambah proyek"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in workspace.add(url) }
        }
    }

    private func canOpenTerminal(for session: DeveloperAgentSession) -> Bool {
        guard session.projectPath.hasPrefix("/") else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: session.projectPath, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

private struct DeveloperServicesPanel: View {
    @ObservedObject var workspace: DeveloperWorkspaceModel
    @ObservedObject var services: DeveloperServiceModel
    var back: () -> Void
    @State private var githubToken = ""
    @State private var vercelToken = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("LAYANAN PENGEMBANG").font(.system(size: 11, weight: .bold)).tracking(1)
                Spacer()
                Button("Perbarui") { services.refresh(project: workspace.selectedProject, branch: workspace.git?.branch) }
                Button("Kembali") {
                    githubToken = ""
                    vercelToken = ""
                    back()
                }
            }
            Text("Status proyek yang dipilih. Nubi hanya membaca data; token disimpan di Keychain.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
            Text("GitHub: izin Pull requests dan Actions untuk membaca. Vercel: tautkan proyek lewat .vercel/project.json.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
            Divider()
            HStack {
                Text("GITHUB").font(.system(size: 11, weight: .semibold))
                Spacer()
                if services.connected.contains(.github) {
                    Button("Putuskan GitHub") { services.disconnect(.github) }
                } else {
                    SecureField("Token GitHub", text: $githubToken).frame(width: 220)
                    Button("Hubungkan GitHub") {
                        services.connect(.github, token: githubToken, project: workspace.selectedProject, branch: workspace.git?.branch)
                        githubToken = ""
                    }
                }
            }
            statusRow("Pull request", services.pullRequest)
            statusRow("Actions", services.action)
            Divider()
            HStack {
                Text("VERCEL").font(.system(size: 11, weight: .semibold))
                Spacer()
                if services.connected.contains(.vercel) {
                    Button("Putuskan Vercel") { services.disconnect(.vercel) }
                } else {
                    SecureField("Token Vercel", text: $vercelToken).frame(width: 220)
                    Button("Hubungkan Vercel") {
                        services.connect(.vercel, token: vercelToken, project: workspace.selectedProject, branch: workspace.git?.branch)
                        vercelToken = ""
                    }
                }
            }
            statusRow("Deployment", services.deployment)
            if let message = services.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .textFieldStyle(.roundedBorder)
    }

    private func statusRow(_ label: String, _ status: DeveloperServiceStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).frame(width: 84, alignment: .leading).foregroundStyle(.white.opacity(0.72))
            Text(status.title).lineLimit(1)
            if !status.detail.isEmpty { Text(status.detail).lineLimit(1).foregroundStyle(.white.opacity(0.65)) }
            Spacer(minLength: 0)
            if let url = status.url { Button("Buka") { NSWorkspace.shared.open(url) } }
        }
        .foregroundStyle(status.phase == .unauthorized || status.phase == .failed ? .orange : .white)
    }
}

struct DeveloperTerminalPanel: View {
    @ObservedObject var workspace: DeveloperWorkspaceModel
    @ObservedObject var terminal: DeveloperTerminalModel
    var showProjects: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("TERMINAL", systemImage: "terminal").font(.system(size: 11, weight: .bold)).tracking(1)
                if let path = terminal.projectPath {
                    Text(URL(fileURLWithPath: path).lastPathComponent).font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
                Spacer()
                if terminal.isRunning {
                    Button("Fokus") { terminal.focus() }
                    Button("Tutup sesi") { terminal.stop() }
                }
            }.buttonStyle(.bordered).controlSize(.small)
            if terminal.isRunning {
                EmbeddedTerminalView(model: terminal)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onAppear { terminal.focus() }
            } else {
                VStack(spacing: 9) {
                    Text(terminal.exitMessage ?? "Terminal belum dibuka").font(.system(size: 13, weight: .medium))
                    if let project = workspace.selectedProject {
                        Button("Mulai di \(project.name)") { terminal.start(in: project) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Pilih proyek", action: showProjects).buttonStyle(.borderedProminent)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
