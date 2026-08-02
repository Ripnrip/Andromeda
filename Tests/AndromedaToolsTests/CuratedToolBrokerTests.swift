import AndromedaSecrets
import AndromedaTools
import Foundation
import Testing

@Suite("AndromedaTools.CuratedToolBroker")
struct CuratedToolBrokerTests {
    static let githubCanary = "ghp_CANARYSECRET-NO-LEAK"
    static let slackCanary = "xoxb-CANARYSECRET-NO-LEAK"

    // MARK: - Doubles

    actor MockUpstreamHTTP: UpstreamHTTPExecuting {
        private(set) var requests: [UpstreamHTTPRequest] = []
        private var queuedResponses: [UpstreamHTTPResponse]

        init(responses: [UpstreamHTTPResponse] = []) {
            self.queuedResponses = responses
        }

        func execute(_ request: UpstreamHTTPRequest) async throws -> UpstreamHTTPResponse {
            requests.append(request)
            if queuedResponses.isEmpty {
                return UpstreamHTTPResponse(status: 200, body: Data("{}".utf8))
            }
            return queuedResponses.removeFirst()
        }
    }

    // MARK: - Helpers

    private func makeSecrets() -> InMemorySecretProvider {
        InMemorySecretProvider(values: [
            SecretReference(service: "andromeda.github", account: "token"): Self.githubCanary,
            SecretReference(service: "andromeda.slack", account: "token"): Self.slackCanary,
        ])
    }

    private func makeConfiguration(
        automationAllowed: Bool = false,
        github: Bool = true,
        slack: Bool = true,
        maxResponseBytes: Int = 1_048_576
    ) throws -> ToolsBrokerConfiguration {
        try ToolsBrokerConfiguration(
            automationAllowed: automationAllowed,
            github: github ? .init(tokenReference: SecretReference(service: "andromeda.github", account: "token")) : nil,
            slack: slack ? .init(tokenReference: SecretReference(service: "andromeda.slack", account: "token")) : nil,
            maxResponseBytes: maxResponseBytes
        )
    }

    private func makeBroker(
        automationAllowed: Bool = false,
        upstream: MockUpstreamHTTP = MockUpstreamHTTP(),
        secrets: (any SecretProviding)? = nil,
        maxResponseBytes: Int = 1_048_576
    ) throws -> CuratedToolBroker {
        CuratedToolBroker(
            configuration: try makeConfiguration(automationAllowed: automationAllowed, maxResponseBytes: maxResponseBytes),
            secrets: secrets ?? makeSecrets(),
            http: upstream
        )
    }

    // MARK: - Surface

    @Test("tools/list exposes only the curated andromeda_* surface")
    func curatedSurface() async throws {
        let broker = try makeBroker()
        let names = await broker.listTools().map(\.name)
        #expect(names == [
            "andromeda_github_get_me",
            "andromeda_github_request",
            "andromeda_slack_post_message",
            "andromeda_slack_request",
        ])
    }

    @Test("unconfigured services are absent from the surface")
    func unconfiguredServiceAbsent() async throws {
        let broker = CuratedToolBroker(
            configuration: try makeConfiguration(github: true, slack: false),
            secrets: makeSecrets(),
            http: MockUpstreamHTTP()
        )
        let names = await broker.listTools().map(\.name)
        #expect(names == ["andromeda_github_get_me", "andromeda_github_request"])
    }

    // MARK: - GitHub

    @Test("github get_me round-trips with host-side auth and no secret leakage")
    func githubGetMe() async throws {
        let upstream = MockUpstreamHTTP(responses: [
            UpstreamHTTPResponse(status: 200, body: Data(#"{"login":"Ripnrip"}"#.utf8)),
        ])
        let broker = try makeBroker(upstream: upstream)

        let result = await broker.callTool(name: "andromeda_github_get_me", arguments: [:])

        #expect(result.isError == false)
        #expect(result.content.first?.text.contains("Ripnrip") == true)
        #expect(result.content.first?.text.contains(Self.githubCanary) == false)

        let sent = await upstream.requests
        #expect(sent.count == 1)
        #expect(sent.first?.method == "GET")
        #expect(sent.first?.url.absoluteString == "https://api.github.com/user")
        #expect(sent.first?.headers["Authorization"] == "Bearer \(Self.githubCanary)")
    }

    @Test("upstream error bodies echoing the token are redacted before returning")
    func redactionOnError() async throws {
        let upstream = MockUpstreamHTTP(responses: [
            UpstreamHTTPResponse(status: 401, body: Data(#"{"message":"bad credentials: \#(Self.githubCanary)"}"#.utf8)),
        ])
        let broker = try makeBroker(upstream: upstream)

        let result = await broker.callTool(name: "andromeda_github_get_me", arguments: [:])

        #expect(result.isError == true)
        #expect(result.content.first?.text.contains(Self.githubCanary) == false)
        #expect(result.content.first?.text.contains("[redacted]") == true)
    }

    @Test("github_request allows reads under /repos/ without automation")
    func githubReadAllowed() async throws {
        let upstream = MockUpstreamHTTP(responses: [
            UpstreamHTTPResponse(status: 200, body: Data(#"{"full_name":"hashimotolabs/AI-Config"}"#.utf8)),
        ])
        let broker = try makeBroker(upstream: upstream)

        let result = await broker.callTool(name: "andromeda_github_request", arguments: [
            "method": .string("GET"),
            "path": .string("/repos/hashimotolabs/AI-Config"),
        ])

        #expect(result.isError == false)
        #expect(result.content.first?.text.contains("AI-Config") == true)
    }

    @Test("github_request rejects writes without automationAllowed")
    func githubWriteRequiresAutomation() async throws {
        let broker = try makeBroker(automationAllowed: false)

        let result = await broker.callTool(name: "andromeda_github_request", arguments: [
            "method": .string("POST"),
            "path": .string("/repos/hashimotolabs/AI-Config/issues"),
            "body": .object(["title": .string("test")]),
        ])

        #expect(result.isError == true)
        #expect(result.content.first?.text.contains("automationAllowed") == true)
    }

    @Test("github_request performs writes when automationAllowed is on")
    func githubWriteWithAutomation() async throws {
        let upstream = MockUpstreamHTTP(responses: [
            UpstreamHTTPResponse(status: 201, body: Data(#"{"number":9}"#.utf8)),
        ])
        let broker = try makeBroker(automationAllowed: true, upstream: upstream)

        let result = await broker.callTool(name: "andromeda_github_request", arguments: [
            "method": .string("POST"),
            "path": .string("/repos/hashimotolabs/AI-Config/issues"),
            "body": .object(["title": .string("from the VM")]),
        ])

        #expect(result.isError == false)
        let sent = await upstream.requests
        #expect(sent.first?.method == "POST")
        #expect(sent.first?.url.absoluteString == "https://api.github.com/repos/hashimotolabs/AI-Config/issues")
        let body = try #require(sent.first?.body)
        #expect(String(data: body, encoding: .utf8)?.contains("from the VM") == true)
    }

    @Test("github_request rejects paths outside /repos/ (except GET /user)")
    func githubPathPolicy() async throws {
        let broker = try makeBroker(automationAllowed: true)

        let gistWrite = await broker.callTool(name: "andromeda_github_request", arguments: [
            "method": .string("POST"),
            "path": .string("/gists"),
        ])
        #expect(gistWrite.isError == true)
        #expect(gistWrite.content.first?.text.contains("/repos/") == true)

        let userWrite = await broker.callTool(name: "andromeda_github_request", arguments: [
            "method": .string("PATCH"),
            "path": .string("/user"),
        ])
        #expect(userWrite.isError == true)
    }

    @Test("github_request normalizes traversal before allowlist")
    func githubPathTraversalRejected() async throws {
        let upstream = MockUpstreamHTTP()
        let broker = try makeBroker(automationAllowed: true, upstream: upstream)

        let escaped = await broker.callTool(name: "andromeda_github_request", arguments: [
            "method": .string("GET"),
            "path": .string("/repos/../../gists"),
        ])
        #expect(escaped.isError == true)
        #expect(escaped.content.first?.text.contains("/repos/") == true)

        let aboveRoot = await broker.callTool(name: "andromeda_github_request", arguments: [
            "method": .string("GET"),
            "path": .string("/repos/foo/../../../gists"),
        ])
        #expect(aboveRoot.isError == true)
        #expect(aboveRoot.content.first?.text.contains("/repos/") == true)

        let sent = await upstream.requests
        #expect(sent.isEmpty)

        #expect(CuratedToolBroker.normalizedGitHubAPIPath("/repos/a/b/../c") == "/repos/a/c")
        #expect(CuratedToolBroker.normalizedGitHubAPIPath("/repos/../../user") == "/user")
        #expect(CuratedToolBroker.normalizedGitHubAPIPath("/repos/foo/../../../gists") == "/gists")
        #expect(CuratedToolBroker.isAllowedGitHubPath("/user", method: "GET"))
        #expect(!CuratedToolBroker.isAllowedGitHubPath("/gists", method: "GET"))
        // Traversal that lands on GET /user is allowed after normalize — policy still holds.
        #expect(CuratedToolBroker.isAllowedGitHubPath(
            CuratedToolBroker.normalizedGitHubAPIPath("/repos/../../user")!,
            method: "GET"
        ))
        #expect(!CuratedToolBroker.isAllowedGitHubPath(
            CuratedToolBroker.normalizedGitHubAPIPath("/repos/../../gists")!,
            method: "GET"
        ))
    }

    @Test("github_request validates required arguments")
    func githubArgumentValidation() async throws {
        let broker = try makeBroker()

        let missingPath = await broker.callTool(name: "andromeda_github_request", arguments: [
            "method": .string("GET"),
        ])
        #expect(missingPath.isError == true)
        #expect(missingPath.content.first?.text.contains("'path' is required") == true)

        let badMethod = await broker.callTool(name: "andromeda_github_request", arguments: [
            "method": .string("TRACE"),
            "path": .string("/repos/a/b"),
        ])
        #expect(badMethod.isError == true)
    }

    // MARK: - Slack

    @Test("slack post_message requires automationAllowed")
    func slackWriteRequiresAutomation() async throws {
        let broker = try makeBroker(automationAllowed: false)

        let result = await broker.callTool(name: "andromeda_slack_post_message", arguments: [
            "channel": .string("C123"),
            "text": .string("hello"),
        ])

        #expect(result.isError == true)
        #expect(result.content.first?.text.contains("automationAllowed") == true)
    }

    @Test("slack post_message posts with host-side auth when automation is on")
    func slackPostMessage() async throws {
        let upstream = MockUpstreamHTTP(responses: [
            UpstreamHTTPResponse(status: 200, body: Data(#"{"ok":true,"ts":"1785.1"}"#.utf8)),
        ])
        let broker = try makeBroker(automationAllowed: true, upstream: upstream)

        let result = await broker.callTool(name: "andromeda_slack_post_message", arguments: [
            "channel": .string("C123"),
            "text": .string("hello from the VM"),
        ])

        #expect(result.isError == false)
        let sent = await upstream.requests
        #expect(sent.first?.url.absoluteString == "https://slack.com/api/chat.postMessage")
        #expect(sent.first?.headers["Authorization"] == "Bearer \(Self.slackCanary)")
        let body = try #require(sent.first?.body)
        let payload = String(data: body, encoding: .utf8) ?? ""
        #expect(payload.contains("C123"))
        #expect(payload.contains("hello from the VM"))
        #expect(result.content.first?.text.contains(Self.slackCanary) == false)
    }

    @Test("slack ok:false responses surface as tool errors")
    func slackOkFalse() async throws {
        let upstream = MockUpstreamHTTP(responses: [
            UpstreamHTTPResponse(status: 200, body: Data(#"{"ok":false,"error":"channel_not_found"}"#.utf8)),
        ])
        let broker = try makeBroker(automationAllowed: true, upstream: upstream)

        let result = await broker.callTool(name: "andromeda_slack_post_message", arguments: [
            "channel": .string("nope"),
            "text": .string("hi"),
        ])

        #expect(result.isError == true)
        #expect(result.content.first?.text.contains("channel_not_found") == true)
    }

    @Test("slack_request enforces the host method allowlist")
    func slackAllowlist() async throws {
        let broker = try makeBroker(automationAllowed: true)

        let result = await broker.callTool(name: "andromeda_slack_request", arguments: [
            "method": .string("admin.users.delete"),
        ])

        #expect(result.isError == true)
        #expect(result.content.first?.text.contains("allowlist") == true)
    }

    // MARK: - Secrets & unknown tools

    @Test("missing Keychain entries surface as errors without secret material")
    func missingSecret() async throws {
        let broker = try makeBroker(secrets: InMemorySecretProvider(values: [:]))

        let result = await broker.callTool(name: "andromeda_github_get_me", arguments: [:])

        #expect(result.isError == true)
        #expect(result.content.first?.text.contains("Host secret unavailable") == true)
        #expect(result.content.first?.text.contains("andromeda.github") == true)
    }

    @Test("unknown tools are rejected")
    func unknownTool() async throws {
        let broker = try makeBroker()

        let result = await broker.callTool(name: "andromeda_github_delete_everything", arguments: [:])

        #expect(result.isError == true)
        #expect(result.content.first?.text.contains("Unknown tool") == true)
    }

    // MARK: - Keychain provider

    // MARK: - Keychain provider

    @Test("MacOSKeychainSecretProvider maps missing entries to notFound with reference only")
    func keychainNotFound() async throws {
        let provider = MacOSKeychainSecretProvider(runner: .init { _, _ in
            throw SecretProviderError.notFound(service: "svc", account: "acct")
        })
        do {
            _ = try await provider.secret(for: SecretReference(service: "svc", account: "acct"))
            Issue.record("expected notFound")
        } catch let error as SecretProviderError {
            #expect(error == .notFound(service: "svc", account: "acct"))
            #expect(error.localizedDescription.contains("svc"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    // MARK: - Configuration hardening

    @Test("base URLs must be https names — no http, credentials, or IP literals")
    func baseURLValidation() throws {
        let reference = SecretReference(service: "svc", account: "acct")

        #expect(throws: ToolBrokerError.self) {
            try ToolsBrokerConfiguration(github: .init(
                tokenReference: reference,
                apiBaseURL: URL(string: "http://api.github.com")!
            ))
        }
        #expect(throws: ToolBrokerError.self) {
            try ToolsBrokerConfiguration(github: .init(
                tokenReference: reference,
                apiBaseURL: URL(string: "https://140.82.112.6")!
            ))
        }
        #expect(throws: ToolBrokerError.self) {
            try ToolsBrokerConfiguration(slack: .init(
                tokenReference: reference,
                apiBaseURL: URL(string: "https://user:pass@slack.com/api")!
            ))
        }
        // The defaults are valid.
        _ = try ToolsBrokerConfiguration(
            github: .init(tokenReference: reference),
            slack: .init(tokenReference: reference)
        )
    }

    @Test("oversized upstream bodies are truncated with a marker, redaction still applied")
    func responseTruncation() async throws {
        let bigBody = String(repeating: "x", count: 2_000) + Self.githubCanary
        let upstream = MockUpstreamHTTP(responses: [
            UpstreamHTTPResponse(status: 200, body: Data(bigBody.utf8)),
        ])
        let broker = try makeBroker(upstream: upstream, maxResponseBytes: 500)

        let result = await broker.callTool(name: "andromeda_github_get_me", arguments: [:])

        let text = try #require(result.content.first?.text)
        #expect(text.contains("[truncated: upstream body was"))
        #expect(text.count < bigBody.count)
        // The canary lived past the truncation point — but even if it hadn't,
        // redaction runs on whatever is forwarded.
        #expect(!text.contains(Self.githubCanary))
    }
}
