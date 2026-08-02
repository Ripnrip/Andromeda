import AndromedaSecrets
import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Curated tools broker: the third Andromeda pillar (tools/MCP).
///
/// VM agents see a small set of `andromeda_*` tools. The broker executes them
/// on the host against GitHub/Slack, resolving tokens from the Keychain at
/// call time. Resolved secrets are used only for the upstream Authorization
/// header and are scrubbed from anything returned to the caller.
public actor CuratedToolBroker {

    #if canImport(OSLog)
    private let logger = Logger(subsystem: "com.andromeda.tools-broker", category: "broker")
    #endif

    public static let githubGetMeTool = "andromeda_github_get_me"
    public static let githubRequestTool = "andromeda_github_request"
    public static let slackPostMessageTool = "andromeda_slack_post_message"
    public static let slackRequestTool = "andromeda_slack_request"

    private static let githubReadMethods: Set<String> = ["GET"]
    private static let githubWriteMethods: Set<String> = ["POST", "PATCH", "PUT", "DELETE"]

    private let configuration: ToolsBrokerConfiguration
    private let secrets: any SecretProviding
    private let http: any UpstreamHTTPExecuting

    public init(
        configuration: ToolsBrokerConfiguration,
        secrets: any SecretProviding,
        http: any UpstreamHTTPExecuting
    ) {
        self.configuration = configuration
        self.secrets = secrets
        self.http = http
    }

    // MARK: - Tool surface

    public func listTools() -> [ToolDefinition] {
        var tools: [ToolDefinition] = []
        if configuration.github != nil {
            tools.append(Self.githubGetMeDefinition)
            tools.append(Self.githubRequestDefinition)
        }
        if configuration.slack != nil {
            tools.append(Self.slackPostMessageDefinition)
            tools.append(Self.slackRequestDefinition)
        }
        return tools
    }

    public func callTool(name: String, arguments: [String: JSONValue]) async -> ToolCallResult {
        do {
            switch name {
            case Self.githubGetMeTool:
                return try await githubGetMe()
            case Self.githubRequestTool:
                return try await githubRequest(arguments: arguments)
            case Self.slackPostMessageTool:
                return try await slackPostMessage(arguments: arguments)
            case Self.slackRequestTool:
                return try await slackRequest(arguments: arguments)
            default:
                throw ToolBrokerError.unknownTool(name)
            }
        } catch let error as ToolBrokerError {
            return ToolCallResult(text: error.localizedDescription, isError: true)
        } catch {
            return ToolCallResult(text: "Tool call failed: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - GitHub

    private func githubGetMe() async throws -> ToolCallResult {
        let (github, token) = try await githubContext()
        let response = try await http.execute(githubRequest(
            base: github.apiBaseURL,
            method: "GET",
            path: "/user",
            token: token
        ))
        return try githubResult(response, token: token)
    }

    private func githubRequest(arguments: [String: JSONValue]) async throws -> ToolCallResult {
        guard let method = arguments["method"]?.stringValue?.uppercased(), !method.isEmpty else {
            throw ToolBrokerError.invalidArguments("'method' is required (GET, POST, PATCH, PUT, DELETE).")
        }
        guard let path = arguments["path"]?.stringValue, path.hasPrefix("/") else {
            throw ToolBrokerError.invalidArguments("'path' is required and must start with '/'.")
        }
        guard Self.githubReadMethods.contains(method) || Self.githubWriteMethods.contains(method) else {
            throw ToolBrokerError.policyDenied("GitHub method '\(method)' is not allowed.")
        }
        guard path.hasPrefix("/repos/") || (path == "/user" && Self.githubReadMethods.contains(method)) else {
            throw ToolBrokerError.policyDenied("GitHub paths must start with '/repos/' (only GET /user is allowed outside that).")
        }
        if Self.githubWriteMethods.contains(method), !configuration.automationAllowed {
            throw ToolBrokerError.policyDenied("GitHub write operations require automationAllowed on the host.")
        }

        let (github, token) = try await githubContext()
        var body: Data?
        if let payload = arguments["body"] {
            body = try JSONEncoder().encode(payload)
        }
        let response = try await http.execute(githubRequest(
            base: github.apiBaseURL,
            method: method,
            path: path,
            token: token,
            body: body
        ))
        return try githubResult(response, token: token)
    }

    private func githubContext() async throws -> (ToolsBrokerConfiguration.GitHub, String) {
        guard let github = configuration.github else {
            throw ToolBrokerError.serviceNotConfigured("GitHub")
        }
        let token = try await resolveSecret(github.tokenReference)
        return (github, token)
    }

    private func githubRequest(base: URL, method: String, path: String, token: String, body: Data? = nil) -> UpstreamHTTPRequest {
        // Parse path and query separately — URL.appending(path:) would
        // percent-encode ? in /repos/org/repo?state=open, breaking
        // pagination and filtering.
        let url: URL
        if let questionMark = path.firstIndex(of: "?") {
            let pathPart = String(path[..<questionMark])
            let queryPart = String(path[path.index(after: questionMark)...])
            url = base.appending(path: pathPart).appending(query: queryPart)
        } else {
            url = base.appending(path: path)
        }
        return UpstreamHTTPRequest(
            method: method,
            url: url,
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "andromeda-tools-broker",
            ],
            body: body
        )
    }

    private func githubResult(_ response: UpstreamHTTPResponse, token: String) throws -> ToolCallResult {
        let text = redact(bodyText(response), secrets: [token])
        guard (200 ..< 300).contains(response.status) else {
            return ToolCallResult(
                text: ToolBrokerError.upstreamError(service: "GitHub", status: response.status, body: text).localizedDescription,
                isError: true
            )
        }
        return ToolCallResult(text: text)
    }

    // MARK: - Slack

    private func slackPostMessage(arguments: [String: JSONValue]) async throws -> ToolCallResult {
        guard configuration.automationAllowed else {
            throw ToolBrokerError.policyDenied("Slack write operations require automationAllowed on the host.")
        }
        guard let channel = arguments["channel"]?.stringValue, !channel.isEmpty else {
            throw ToolBrokerError.invalidArguments("'channel' is required.")
        }
        guard let text = arguments["text"]?.stringValue, !text.isEmpty else {
            throw ToolBrokerError.invalidArguments("'text' is required.")
        }
        return try await slackCall(method: "chat.postMessage", payload: [
            "channel": .string(channel),
            "text": .string(text),
        ])
    }

    private func slackRequest(arguments: [String: JSONValue]) async throws -> ToolCallResult {
        guard let method = arguments["method"]?.stringValue, !method.isEmpty else {
            throw ToolBrokerError.invalidArguments("'method' is required (Slack Web API method name).")
        }
        guard configuration.allowedSlackMethods.contains(method) else {
            throw ToolBrokerError.policyDenied("Slack method '\(method)' is not in the host allowlist.")
        }
        if !configuration.automationAllowed {
            throw ToolBrokerError.policyDenied("Slack write operations require automationAllowed on the host.")
        }
        let payload = arguments["arguments"]?.objectValue ?? [:]
        return try await slackCall(method: method, payload: payload)
    }

    private func slackCall(method: String, payload: [String: JSONValue]) async throws -> ToolCallResult {
        guard let slack = configuration.slack else {
            throw ToolBrokerError.serviceNotConfigured("Slack")
        }
        let token = try await resolveSecret(slack.tokenReference)
        let response = try await http.execute(UpstreamHTTPRequest(
            method: "POST",
            url: slack.apiBaseURL.appending(path: method),
            headers: [
                "Authorization": "Bearer \(token)",
                "Content-Type": "application/json; charset=utf-8",
            ],
            body: try JSONEncoder().encode(payload)
        ))
        let text = redact(bodyText(response), secrets: [token])
        // Slack signals errors with 200 + {"ok": false}.
        if let object = try? JSONDecoder().decode(JSONValue.self, from: response.body).objectValue,
           case .bool(false)? = object["ok"]
        {
            return ToolCallResult(text: "Slack API error: \(text)", isError: true)
        }
        guard (200 ..< 300).contains(response.status) else {
            return ToolCallResult(
                text: ToolBrokerError.upstreamError(service: "Slack", status: response.status, body: text).localizedDescription,
                isError: true
            )
        }
        return ToolCallResult(text: text)
    }

    // MARK: - Secrets & redaction

    private func resolveSecret(_ reference: SecretReference) async throws -> String {
        do {
            return try await secrets.secret(for: reference)
        } catch {
            throw ToolBrokerError.secretUnavailable(error.localizedDescription)
        }
    }

    private func bodyText(_ response: UpstreamHTTPResponse) -> String {
        let limit = configuration.maxResponseBytes
        if response.body.count > limit {
            let prefix = response.body.prefix(limit)
            let text = String(data: prefix, encoding: .utf8) ?? "<non-utf8 body prefix: \(prefix.count) bytes>"
            return text + "\n[truncated: upstream body was \(response.body.count) bytes, limit is \(limit)]"
        }
        return String(data: response.body, encoding: .utf8) ?? "<non-utf8 body: \(response.body.count) bytes>"
    }

    /// Guarantees resolved secrets never leave the host: any occurrence of a
    /// secret value in an upstream body is scrubbed before the text is
    /// returned toward the VM.
    private func redact(_ text: String, secrets: [String]) -> String {
        secrets.reduce(text) { partial, secret in
            secret.isEmpty ? partial : partial.replacingOccurrences(of: secret, with: "[redacted]")
        }
    }

    // MARK: - Tool definitions

    private static let githubGetMeDefinition = ToolDefinition(
        name: githubGetMeTool,
        description: "Return the authenticated GitHub user. Safe read; use it to verify connectivity.",
        inputSchema: .object(["type": .string("object"), "properties": .object([String: JSONValue]())])
    )

    private static let githubRequestDefinition = ToolDefinition(
        name: githubRequestTool,
        description: "Call the GitHub REST API. Paths must start with '/repos/' (GET /user is also allowed). Write methods require host automation to be enabled.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "method": .object(["type": .string("string"), "enum": .array([.string("GET"), .string("POST"), .string("PATCH"), .string("PUT"), .string("DELETE")])]),
                "path": .object(["type": .string("string"), "description": .string("API path starting with /repos/")]),
                "body": .object(["type": .string("object"), "description": .string("Optional JSON request body")]),
            ]),
            "required": .array([.string("method"), .string("path")]),
        ])
    )

    private static let slackPostMessageDefinition = ToolDefinition(
        name: slackPostMessageTool,
        description: "Post a message to a Slack channel via chat.postMessage.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "channel": .object(["type": .string("string")]),
                "text": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("channel"), .string("text")]),
        ])
    )

    private static let slackRequestDefinition = ToolDefinition(
        name: slackRequestTool,
        description: "Call an allowlisted Slack Web API method. The host allowlist and automation gate apply.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "method": .object(["type": .string("string"), "description": .string("Slack Web API method, e.g. chat.postMessage")]),
                "arguments": .object(["type": .string("object"), "description": .string("Method arguments as a JSON object")]),
            ]),
            "required": .array([.string("method")]),
        ])
    )
}
