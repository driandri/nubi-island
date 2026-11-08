import Combine
import Foundation
import Security

enum DeveloperServiceProvider: String, CaseIterable {
    case github, vercel
    var title: String { self == .github ? "GitHub" : "Vercel" }
}

struct GitHubRepository: Equatable, Sendable {
    let owner: String
    let name: String

    static func parse(remote: String) -> GitHubRepository? {
        let value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if value.hasPrefix("git@github.com:") {
            path = String(value.dropFirst("git@github.com:".count))
        } else if let url = URLComponents(string: value), url.host?.lowercased() == "github.com",
                  url.query == nil, url.fragment == nil,
                  (url.scheme == "https" && url.user == nil && url.password == nil)
                    || (url.scheme == "ssh" && url.user == "git" && url.password == nil) {
            path = url.path
        } else { return nil }
        let pieces = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/").map(String.init)
        guard pieces.count == 2 else { return nil }
        let name = pieces[1].hasSuffix(".git") ? String(pieces[1].dropLast(4)) : pieces[1]
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !pieces[0].isEmpty, !name.isEmpty,
              pieces[0].unicodeScalars.allSatisfy(allowed.contains),
              name.unicodeScalars.allSatisfy(allowed.contains),
              pieces[0] != ".", pieces[0] != "..", name != ".", name != ".." else { return nil }
        return GitHubRepository(owner: pieces[0], name: name)
    }

    static func read(at folder: URL) -> GitHubRepository? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path, "config", "--get", "remote.origin.url"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, data.count < 4096 else { return nil }
            return parse(remote: String(decoding: data, as: UTF8.self))
        } catch { return nil }
    }
}

struct VercelProjectLink: Decodable, Equatable, Sendable {
    let projectId: String
    let orgId: String

    static func read(at folder: URL) -> VercelProjectLink? {
        let url = folder.appendingPathComponent(".vercel/project.json")
        guard let data = try? Data(contentsOf: url), data.count <= 4096,
              let link = try? JSONDecoder().decode(Self.self, from: data),
              link.projectId.hasPrefix("prj_"), !link.orgId.isEmpty else { return nil }
        return link
    }
}

@MainActor
protocol DeveloperServiceCredentialStore {
    func token(for provider: DeveloperServiceProvider) throws -> String?
    func setToken(_ token: String, for provider: DeveloperServiceProvider) throws
    func removeToken(for provider: DeveloperServiceProvider) throws
}

@MainActor
final class DeveloperServiceKeychain: DeveloperServiceCredentialStore {
    private let service = "com.personal.notch.developer-services"

    private func query(_ provider: DeveloperServiceProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }

    func token(for provider: DeveloperServiceProvider) throws -> String? {
        var request = query(provider)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return token
    }

    func setToken(_ token: String, for provider: DeveloperServiceProvider) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query(provider) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var request = query(provider)
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(request as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }

    func removeToken(for provider: DeveloperServiceProvider) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    struct KeychainError: Error, LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Keychain tidak tersedia (kode \(status))." }
    }
}

enum DeveloperServicePhase: Equatable {
    case disconnected, unlinked, loading, empty, ready, unauthorized, failed
}

struct DeveloperServiceStatus: Equatable {
    let phase: DeveloperServicePhase
    let title: String
    let detail: String
    let url: URL?

    static func message(_ phase: DeveloperServicePhase, _ title: String, _ detail: String = "") -> Self {
        Self(phase: phase, title: title, detail: detail, url: nil)
    }
}

protocol DeveloperServiceTransport: Sendable {
    func get(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

private final class RejectServiceRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class URLSessionServiceTransport: DeveloperServiceTransport, @unchecked Sendable {
    private let redirectGuard: RejectServiceRedirects
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 12
        let guardDelegate = RejectServiceRedirects()
        redirectGuard = guardDelegate
        session = URLSession(configuration: configuration, delegate: guardDelegate, delegateQueue: nil)
    }

    func get(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, response)
    }

}

enum DeveloperServiceAPI {
    static func githubPull(repository: GitHubRepository, branch: String, token: String,
                           transport: DeveloperServiceTransport) async -> DeveloperServiceStatus {
        let path = "/repos/\(repository.owner)/\(repository.name)/pulls"
        let context = "\(repository.owner)/\(repository.name) · \(branch)"
        let query = [URLQueryItem(name: "state", value: "open"),
                     URLQueryItem(name: "head", value: "\(repository.owner):\(branch)"),
                     URLQueryItem(name: "per_page", value: "1")]
        do {
            let (data, response) = try await transport.get(request(host: "api.github.com", path: path, query: query, token: token))
            guard response.statusCode == 200 else { return status(for: response) }
            let pulls = try JSONDecoder().decode([Pull].self, from: data)
            guard let pull = pulls.first else { return .message(.empty, "Tidak ada PR terbuka", context) }
            return DeveloperServiceStatus(phase: .ready, title: "PR #\(pull.number): \(pull.title)", detail: context,
                                          url: safeURL(pull.htmlURL, host: "github.com"))
        } catch { return .message(.failed, "Gagal membaca pull request", "Periksa koneksi lalu coba lagi.") }
    }

    static func githubAction(repository: GitHubRepository, branch: String, token: String,
                             transport: DeveloperServiceTransport) async -> DeveloperServiceStatus {
        let path = "/repos/\(repository.owner)/\(repository.name)/actions/runs"
        let context = "\(repository.owner)/\(repository.name) · \(branch)"
        let query = [URLQueryItem(name: "branch", value: branch), URLQueryItem(name: "per_page", value: "1")]
        do {
            let (data, response) = try await transport.get(request(host: "api.github.com", path: path, query: query, token: token))
            guard response.statusCode == 200 else { return status(for: response) }
            let runs = try JSONDecoder().decode(Runs.self, from: data).workflowRuns
            guard let run = runs.first else { return .message(.empty, "Belum ada run Actions", context) }
            let state = run.conclusion ?? run.status
            return DeveloperServiceStatus(phase: .ready, title: run.name ?? "GitHub Actions",
                                          detail: "\(context) · \(state)", url: safeURL(run.htmlURL, host: "github.com"))
        } catch { return .message(.failed, "Gagal membaca Actions", "Periksa koneksi lalu coba lagi.") }
    }

    static func vercelDeployment(link: VercelProjectLink, branch: String?, token: String,
                                 transport: DeveloperServiceTransport) async -> DeveloperServiceStatus {
        var query = [URLQueryItem(name: "projectId", value: link.projectId),
                     URLQueryItem(name: "limit", value: "1")]
        if link.orgId.hasPrefix("team_") { query.append(URLQueryItem(name: "teamId", value: link.orgId)) }
        if let branch, !branch.isEmpty { query.append(URLQueryItem(name: "branch", value: branch)) }
        do {
            let (data, response) = try await transport.get(request(host: "api.vercel.com", path: "/v7/deployments", query: query, token: token))
            guard response.statusCode == 200 else { return status(for: response) }
            let deployments = try JSONDecoder().decode(Deployments.self, from: data).deployments
            guard let deployment = deployments.first else { return .message(.empty, "Belum ada deployment", branch ?? "Proyek ini") }
            let state = deployment.readyState ?? "UNKNOWN"
            let target = deployment.target == "production" ? "Produksi" : "Preview"
            return DeveloperServiceStatus(phase: .ready, title: "\(target) · \(state)",
                                          detail: deployment.name ?? link.projectId,
                                          url: safeURL(deployment.inspectorURL, host: "vercel.com"))
        } catch { return .message(.failed, "Gagal membaca deployment", "Periksa koneksi lalu coba lagi.") }
    }

    private static func request(host: String, path: String, query: [URLQueryItem], token: String) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Nubi", forHTTPHeaderField: "User-Agent")
        if host == "api.github.com" { request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        return request
    }

    private static func status(for response: HTTPURLResponse) -> DeveloperServiceStatus {
        switch response.statusCode {
        case 401: .message(.unauthorized, "Akses kedaluwarsa", "Perbarui token atau putuskan koneksi.")
        case 403: .message(.unauthorized, "Akses ditolak", "Periksa izin token dan batas API.")
        case 404: .message(.unlinked, "Proyek tidak ditemukan", "Periksa akses dan tautan proyek.")
        case 429: .message(.failed, "Batas API tercapai", "Coba lagi nanti.")
        default: .message(.failed, "Layanan gagal merespons", "HTTP \(response.statusCode)")
        }
    }

    private static func safeURL(_ raw: String?, host: String) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme == "https", url.host?.lowercased() == host,
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        return url
    }

    private struct Pull: Decodable {
        let number: Int
        let title: String
        let htmlURL: String?
        enum CodingKeys: String, CodingKey { case number, title, htmlURL = "html_url" }
    }
    private struct Runs: Decodable {
        let workflowRuns: [Run]
        enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }
    }
    private struct Run: Decodable {
        let name: String?
        let status: String
        let conclusion: String?
        let htmlURL: String?
        enum CodingKeys: String, CodingKey { case name, status, conclusion, htmlURL = "html_url" }
    }
    private struct Deployments: Decodable { let deployments: [Deployment] }
    private struct Deployment: Decodable {
        let name: String?
        let target: String?
        let readyState: String?
        let inspectorURL: String?
        enum CodingKeys: String, CodingKey { case name, target, readyState, inspectorURL = "inspectorUrl" }
    }
}

@MainActor
final class DeveloperServiceModel: ObservableObject {
    @Published private(set) var connected: Set<DeveloperServiceProvider> = []
    @Published private(set) var pullRequest = DeveloperServiceStatus.message(.disconnected, "GitHub belum terhubung")
    @Published private(set) var action = DeveloperServiceStatus.message(.disconnected, "GitHub belum terhubung")
    @Published private(set) var deployment = DeveloperServiceStatus.message(.disconnected, "Vercel belum terhubung")
    @Published private(set) var message: String?

    private let credentials: DeveloperServiceCredentialStore
    private let transport: DeveloperServiceTransport
    private var githubRefreshID = UUID()
    private var vercelRefreshID = UUID()
    private var githubTask: Task<Void, Never>?
    private var vercelTask: Task<Void, Never>?

    init(credentials: DeveloperServiceCredentialStore = DeveloperServiceKeychain(),
         transport: DeveloperServiceTransport = URLSessionServiceTransport()) {
        self.credentials = credentials
        self.transport = transport
        for provider in DeveloperServiceProvider.allCases where (try? credentials.token(for: provider)) != nil {
            connected.insert(provider)
        }
    }

    func connect(_ provider: DeveloperServiceProvider, token: String, project: DeveloperProject?, branch: String?) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { message = "Masukkan token \(provider.title)."; return }
        do {
            try credentials.setToken(trimmed, for: provider)
            connected.insert(provider)
            message = "\(provider.title) terhubung. Status hanya dibaca saat panel Developer dibuka atau diperbarui."
            refresh(project: project, branch: branch)
        } catch { message = "Token tidak dapat disimpan di Keychain: \(error.localizedDescription)" }
    }

    func disconnect(_ provider: DeveloperServiceProvider) {
        do {
            try credentials.removeToken(for: provider)
            connected.remove(provider)
            if provider == .github {
                githubTask?.cancel()
                githubRefreshID = UUID()
                pullRequest = .message(.disconnected, "GitHub belum terhubung")
                action = .message(.disconnected, "GitHub belum terhubung")
            } else {
                vercelTask?.cancel()
                vercelRefreshID = UUID()
                deployment = .message(.disconnected, "Vercel belum terhubung")
            }
            message = "Koneksi \(provider.title) dilepas dan token dihapus dari Keychain."
        } catch { message = "Koneksi gagal dilepas: \(error.localizedDescription)" }
    }

    func refresh(project: DeveloperProject?, branch: String?) {
        githubTask?.cancel()
        vercelTask?.cancel()
        githubRefreshID = UUID()
        vercelRefreshID = UUID()
        let githubID = githubRefreshID
        let vercelID = vercelRefreshID
        guard let project else {
            if connected.contains(.github) {
                pullRequest = .message(.unlinked, "Pilih proyek Git")
                action = .message(.unlinked, "Pilih proyek Git")
            }
            if connected.contains(.vercel) { deployment = .message(.unlinked, "Pilih proyek Vercel") }
            return
        }
        if connected.contains(.github) {
            do {
                if let token = try credentials.token(for: .github) {
                    pullRequest = .message(.loading, "Membaca pull request…")
                    action = .message(.loading, "Membaca Actions…")
                    githubTask = Task { [weak self] in
                        guard let self else { return }
                        let repository = await Task.detached { GitHubRepository.read(at: project.url) }.value
                        guard self.githubRefreshID == githubID else { return }
                        guard let repository else {
                            self.pullRequest = .message(.unlinked, "Remote GitHub tidak ditemukan")
                            self.action = .message(.unlinked, "Remote GitHub tidak ditemukan")
                            return
                        }
                        guard let branch, !branch.isEmpty, branch != "HEAD (no branch)" else {
                            self.pullRequest = .message(.unlinked, "Branch Git belum tersedia")
                            self.action = .message(.unlinked, "Branch Git belum tersedia")
                            return
                        }
                        async let pull = DeveloperServiceAPI.githubPull(repository: repository, branch: branch,
                                                                         token: token, transport: self.transport)
                        async let run = DeveloperServiceAPI.githubAction(repository: repository, branch: branch,
                                                                          token: token, transport: self.transport)
                        let result = await (pull, run)
                        guard self.githubRefreshID == githubID else { return }
                        self.pullRequest = result.0
                        self.action = result.1
                    }
                } else {
                    connected.remove(.github)
                    pullRequest = .message(.disconnected, "GitHub belum terhubung")
                    action = .message(.disconnected, "GitHub belum terhubung")
                }
            } catch {
                pullRequest = .message(.failed, "Keychain tidak tersedia")
                action = .message(.failed, "Keychain tidak tersedia")
            }
        }
        if connected.contains(.vercel) {
            do {
                if let token = try credentials.token(for: .vercel) {
                    deployment = .message(.loading, "Membaca deployment…")
                    vercelTask = Task { [weak self] in
                        guard let self else { return }
                        let link = await Task.detached { VercelProjectLink.read(at: project.url) }.value
                        guard self.vercelRefreshID == vercelID else { return }
                        guard let link else {
                            self.deployment = .message(.unlinked, "Proyek Vercel belum ditautkan", "Tidak ada .vercel/project.json.")
                            return
                        }
                        let result = await DeveloperServiceAPI.vercelDeployment(link: link, branch: branch,
                                                                                 token: token, transport: self.transport)
                        guard self.vercelRefreshID == vercelID else { return }
                        self.deployment = result
                    }
                } else {
                    connected.remove(.vercel)
                    deployment = .message(.disconnected, "Vercel belum terhubung")
                }
            } catch { deployment = .message(.failed, "Keychain tidak tersedia") }
        }
    }
}
