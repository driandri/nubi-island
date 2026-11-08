import Foundation
import XCTest
@testable import NotchTools

final class DeveloperServiceTests: XCTestCase {
    func testGitHubRemoteParsingAcceptsOnlyGitHubRepositoryPaths() {
        let expected = GitHubRepository(owner: "acme", name: "project")
        XCTAssertEqual(GitHubRepository.parse(remote: "https://github.com/acme/project.git"), expected)
        XCTAssertEqual(GitHubRepository.parse(remote: "git@github.com:acme/project.git"), expected)
        XCTAssertEqual(GitHubRepository.parse(remote: "ssh://git@github.com/acme/project"), expected)
        XCTAssertNil(GitHubRepository.parse(remote: "https://token@github.com/acme/project.git"))
        XCTAssertNil(GitHubRepository.parse(remote: "https://github.com.evil.test/acme/project"))
        XCTAssertNil(GitHubRepository.parse(remote: "https://github.com/acme/project/extra"))
        XCTAssertNil(GitHubRepository.parse(remote: "https://github.com/acme/project?token=x"))
    }

    func testVercelProjectLinkReadsOnlyLinkedProject() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nubi-vercel-link-\(UUID().uuidString)")
        let directory = folder.appendingPathComponent(".vercel")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertNil(VercelProjectLink.read(at: folder))
        try #"{"projectId":"prj_example","orgId":"team_example"}"#
            .write(to: directory.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(VercelProjectLink.read(at: folder), VercelProjectLink(projectId: "prj_example", orgId: "team_example"))
    }

    func testGitHubPullUsesReadOnlyRequestAndValidatesLink() async throws {
        let transport = StubTransport(status: 200, body: #"[{"number":12,"title":"Fix login","html_url":"https://github.com/acme/project/pull/12"}]"#)
        let result = await DeveloperServiceAPI.githubPull(repository: GitHubRepository(owner: "acme", name: "project"),
                                                           branch: "feature/a", token: "test-token", transport: transport)
        XCTAssertEqual(result.phase, .ready)
        XCTAssertEqual(result.url?.absoluteString, "https://github.com/acme/project/pull/12")
        let latest = await transport.lastRequest()
        let request = try XCTUnwrap(latest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.url?.host, "api.github.com")
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "head" })?.value, "acme:feature/a")

        let unsafe = StubTransport(status: 200, body: #"[{"number":12,"title":"Fix login","html_url":"https://evil.test/fake"}]"#)
        let unsafeResult = await DeveloperServiceAPI.githubPull(repository: GitHubRepository(owner: "acme", name: "project"),
                                                                 branch: "main", token: "test-token", transport: unsafe)
        XCTAssertEqual(unsafeResult.phase, .ready)
        XCTAssertNil(unsafeResult.url)
    }

    func testAPISeparatesEmptyUnauthorizedAndDeploymentStates() async throws {
        let repo = GitHubRepository(owner: "acme", name: "project")
        let unauthorized = await DeveloperServiceAPI.githubAction(repository: repo, branch: "main", token: "bad",
                                                                    transport: StubTransport(status: 401, body: "{}"))
        XCTAssertEqual(unauthorized.phase, .unauthorized)
        let empty = await DeveloperServiceAPI.githubAction(repository: repo, branch: "main", token: "test",
                                                             transport: StubTransport(status: 200, body: #"{"workflow_runs":[]}"#))
        XCTAssertEqual(empty.phase, .empty)
        let action = await DeveloperServiceAPI.githubAction(repository: repo, branch: "main", token: "test",
                                                              transport: StubTransport(status: 200, body: #"{"workflow_runs":[{"name":"CI","status":"completed","conclusion":"success","html_url":"https://github.com/acme/project/actions/runs/5"}]}"#))
        XCTAssertEqual(action.phase, .ready)
        XCTAssertEqual(action.url?.absoluteString, "https://github.com/acme/project/actions/runs/5")
        XCTAssertTrue(action.detail.contains("success"))
        let missing = await DeveloperServiceAPI.githubAction(repository: repo, branch: "main", token: "test",
                                                               transport: StubTransport(status: 404, body: "{}"))
        XCTAssertEqual(missing.phase, .unlinked)

        let transport = StubTransport(status: 200, body: #"{"deployments":[{"name":"site","target":"production","readyState":"READY","inspectorUrl":"https://vercel.com/acme/site/deploy-1"}]}"#)
        let ready = await DeveloperServiceAPI.vercelDeployment(link: VercelProjectLink(projectId: "prj_example", orgId: "team_example"),
                                                                 branch: "main", token: "test", transport: transport)
        XCTAssertEqual(ready.phase, .ready)
        XCTAssertEqual(ready.url?.host, "vercel.com")
        let latest = await transport.lastRequest()
        let request = try XCTUnwrap(latest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v7/deployments")
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "projectId" })?.value, "prj_example")
        XCTAssertEqual(query?.first(where: { $0.name == "teamId" })?.value, "team_example")
        XCTAssertEqual(query?.first(where: { $0.name == "branch" })?.value, "main")

        let personal = StubTransport(status: 200, body: #"{"deployments":[]}"#)
        let personalResult = await DeveloperServiceAPI.vercelDeployment(
            link: VercelProjectLink(projectId: "prj_example", orgId: "user_example"),
            branch: nil, token: "test", transport: personal)
        XCTAssertEqual(personalResult.phase, .empty)
        let personalRequest = await personal.lastRequest()
        let personalQuery = URLComponents(url: try XCTUnwrap(personalRequest?.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertNil(personalQuery?.first(where: { $0.name == "teamId" }))
    }

    @MainActor
    func testDisconnectRemovesOnlySelectedCredential() {
        let credentials = MemoryCredentials()
        let model = DeveloperServiceModel(credentials: credentials, transport: StubTransport(status: 200, body: "{}"))
        model.connect(.github, token: "github-test", project: nil, branch: nil)
        model.connect(.vercel, token: "vercel-test", project: nil, branch: nil)
        XCTAssertEqual(model.connected, [.github, .vercel])
        model.disconnect(.github)
        XCTAssertEqual(model.connected, [.vercel])
        XCTAssertNil(credentials.values[.github])
        XCTAssertEqual(credentials.values[.vercel], "vercel-test")
        XCTAssertEqual(model.pullRequest.phase, .disconnected)
        XCTAssertEqual(model.deployment.phase, .unlinked)
    }
}

private actor StubTransport: DeveloperServiceTransport {
    let status: Int
    let body: Data
    private var requests: [URLRequest] = []

    init(status: Int, body: String) {
        self.status = status
        self.body = Data(body.utf8)
    }

    func get(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
        return (body, response)
    }

    func lastRequest() -> URLRequest? { requests.last }
}

@MainActor
private final class MemoryCredentials: DeveloperServiceCredentialStore {
    var values: [DeveloperServiceProvider: String] = [:]
    func token(for provider: DeveloperServiceProvider) throws -> String? { values[provider] }
    func setToken(_ token: String, for provider: DeveloperServiceProvider) throws { values[provider] = token }
    func removeToken(for provider: DeveloperServiceProvider) throws { values.removeValue(forKey: provider) }
}
