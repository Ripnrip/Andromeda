import AndromedaSecrets
import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Curated tools broker spans pillar 2 (MCP host) and pillar 5 (secrets broker).
/// Pillar 3 is the skills home; this component is not that pillar or proof of
/// complete MCP lifecycle consolidation or live secrets-broker readiness.
///
/// VM agents see a small set of `andromeda_*` tools. The broker executes them
/// on the host against GitHub/Slack, resolving tokens from the Keychain at
/// call time. The resolved token is used for upstream Authorization and is
/// redacted from supported response-text representations before truncation.
/// This is known-token output filtering, not generic secret discovery or DLP.
public actor CuratedToolBroker: MCPToolServing {

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
    private let outputCancellationCheck: SafeBrokerOutput.CancellationCheck

    /// Preserves the existing injected, Sendable secret and HTTP interfaces.
    /// Construction does not resolve credentials or start background work.
    public init(
        configuration: ToolsBrokerConfiguration,
        secrets: any SecretProviding,
        http: any UpstreamHTTPExecuting
    ) {
        self.configuration = configuration
        self.secrets = secrets
        self.http = http
        self.outputCancellationCheck = { _ in try Task.checkCancellation() }
    }

    /// Internal deterministic output-check seam; the public initializer and
    /// protocols are unchanged. Tests inject finite synchronous throwing checks,
    /// never a detached task, blocking gate, or global mutable handler.
    init(
        configuration: ToolsBrokerConfiguration,
        secrets: any SecretProviding,
        http: any UpstreamHTTPExecuting,
        outputCancellationCheck: @escaping SafeBrokerOutput.CancellationCheck
    ) {
        self.configuration = configuration
        self.secrets = secrets
        self.http = http
        self.outputCancellationCheck = outputCancellationCheck
    }

    // MARK: - Caller-safe failures

    /// Only broker-owned, payload-free cases may supply detailed error copy.
    /// An injected backend can throw the public ToolBrokerError, so that type
    /// must not be treated as trusted merely because its type is familiar.
    /// Keeping this enum private in this file prevents such error forgery and
    /// avoids changing public error types or other owners' source files.
    private enum CallerFailure: Error, Sendable {
        case unknownTool
        case githubNotConfigured
        case slackNotConfigured
        case githubMethodRequired
        case githubPathRequired
        case githubPathInvalid
        case githubMethodDenied
        case githubPathDenied
        case githubAutomationRequired
        case slackAutomationRequired
        case slackChannelRequired
        case slackTextRequired
        case slackMethodRequired
        case slackMethodDenied
        case secretUnavailable
        case slackMalformedResponse
        case responseTooLarge

        /// Emits constants only: no tool name, method, path, credential
        /// reference, decoder diagnostic, or exception payload is interpolated.
        var message: String {
            switch self {
            case .unknownTool:
                return "Unknown tool."
            case .githubNotConfigured:
                return "GitHub upstream is not configured on the host."
            case .slackNotConfigured:
                return "Slack upstream is not configured on the host."
            case .githubMethodRequired:
                return "Invalid tool arguments: 'method' is required (GET, POST, PATCH, PUT, DELETE)."
            case .githubPathRequired:
                return "Invalid tool arguments: 'path' is required and must start with '/'."
            case .githubPathInvalid:
                return "Invalid tool arguments: 'path' must be an absolute GitHub API path."
            case .githubMethodDenied:
                return "Policy denied: GitHub method is not allowed."
            case .githubPathDenied:
                return "Policy denied: GitHub paths must start with '/repos/' (only GET /user is allowed outside that)."
            case .githubAutomationRequired:
                return "Policy denied: GitHub write operations require automationAllowed on the host."
            case .slackAutomationRequired:
                return "Policy denied: Slack write operations require automationAllowed on the host."
            case .slackChannelRequired:
                return "Invalid tool arguments: 'channel' is required."
            case .slackTextRequired:
                return "Invalid tool arguments: 'text' is required."
            case .slackMethodRequired:
                return "Invalid tool arguments: 'method' is required (Slack Web API method name)."
            case .slackMethodDenied:
                return "Policy denied: Slack method is not in the host allowlist."
            case .secretUnavailable:
                return "Host secret unavailable."
            case .slackMalformedResponse:
                return "Slack API error: malformed response."
            case .responseTooLarge:
                return "Upstream response body withheld: accepted size limit exceeded."
            }
        }
    }

    /// Success must positively establish Boolean ok:true. Missing, null, and
    /// wrong-type status are malformed, not benign success compatibility.
    private struct SlackResponseStatus: Decodable, Sendable {
        let ok: Bool
    }

    /// Decode the error field only on ok:false. Its value is never forwarded;
    /// one exact, compatibility-tested code maps to broker-owned constant copy.
    private struct SlackResponseError: Decodable, Sendable {
        let error: String?
    }

    // MARK: - Tool surface

    /// Lists the same configuration-dependent curated surface as before.
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

    /// Dispatches through the existing seams and classifies failures without
    /// reading arbitrary localizedDescription/errorDescription values. A
    /// cancelled task gets fixed copy, not backend diagnostics or a late body.
    /// Cancellation remains cooperative; this does not stop an adapter that
    /// ignores cancellation or roll back an upstream write already performed.
    public func callTool(name: String, arguments: [String: JSONValue]) async -> ToolCallResult {
        do {
            try Task.checkCancellation()
            let result: ToolCallResult
            switch name {
            case Self.githubGetMeTool:
                result = try await githubGetMe()
            case Self.githubRequestTool:
                result = try await githubRequest(arguments: arguments)
            case Self.slackPostMessageTool:
                result = try await slackPostMessage(arguments: arguments)
            case Self.slackRequestTool:
                result = try await slackRequest(arguments: arguments)
            default:
                throw CallerFailure.unknownTool
            }
            try Task.checkCancellation()
            return result
        } catch is CancellationError {
            return ToolCallResult(text: "Tool call cancelled.", isError: true)
        } catch let failure as CallerFailure {
            return ToolCallResult(text: failure.message, isError: true)
        } catch {
            // The exception may contain request URLs, headers, body values,
            // secret bytes, or even a forged public ToolBrokerError payload.
            return ToolCallResult(text: "Tool call failed.", isError: true)
        }
    }

    // MARK: - GitHub

    /// Resolves one per-call token, performs the existing authenticated read,
    /// and delegates successful text output to the known-token filter.
    private func githubGetMe() async throws -> ToolCallResult {
        let (github, token) = try await githubContext()
        let response = try await http.execute(githubRequest(
            base: github.apiBaseURL,
            method: "GET",
            path: "/user",
            token: token
        ))
        try Task.checkCancellation()
        return try githubResult(response, token: token)
    }

    /// Keeps the existing request policy and encoding while ensuring rejected
    /// caller-controlled method/path values cannot become error-message text.
    private func githubRequest(arguments: [String: JSONValue]) async throws -> ToolCallResult {
        guard let method = arguments["method"]?.stringValue?.uppercased(), !method.isEmpty else {
            throw CallerFailure.githubMethodRequired
        }
        guard let rawPath = arguments["path"]?.stringValue, rawPath.hasPrefix("/") else {
            throw CallerFailure.githubPathRequired
        }
        // Normalize before allowlist — raw `/repos/../../user` would otherwise bypass the prefix check
        // and be collapsed by URLSession to `/user` (or other out-of-policy endpoints).
        guard let path = Self.normalizedGitHubAPIPath(rawPath) else {
            throw CallerFailure.githubPathInvalid
        }
        guard Self.githubReadMethods.contains(method) || Self.githubWriteMethods.contains(method) else {
            throw CallerFailure.githubMethodDenied
        }
        guard Self.isAllowedGitHubPath(path, method: method) else {
            throw CallerFailure.githubPathDenied
        }
        if Self.githubWriteMethods.contains(method), !configuration.automationAllowed {
            throw CallerFailure.githubAutomationRequired
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
        try Task.checkCancellation()
        return try githubResult(response, token: token)
    }

    /// Collapses `.` / `..` segments the same way URLSession resolves paths (clamp at `/`).
    /// Query strings are preserved after the normalized path.
    public static func normalizedGitHubAPIPath(_ raw: String) -> String? {
        let pathOnly: String
        let querySuffix: String
        if let questionMark = raw.firstIndex(of: "?") {
            pathOnly = String(raw[..<questionMark])
            querySuffix = String(raw[questionMark...])
        } else {
            pathOnly = raw
            querySuffix = ""
        }
        guard pathOnly.hasPrefix("/") else { return nil }

        var segments: [String] = []
        for segment in pathOnly.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            if segment == "." { continue }
            if segment == ".." {
                // Match URL path resolution: `..` at root stays at root (does not error).
                if !segments.isEmpty {
                    segments.removeLast()
                }
                continue
            }
            segments.append(segment)
        }
        let normalized = "/" + segments.joined(separator: "/")
        return normalized + querySuffix
    }

    /// Allowlist check on an already-normalized path (query stripped).
    public static func isAllowedGitHubPath(_ path: String, method: String) -> Bool {
        let pathOnly: String
        if let questionMark = path.firstIndex(of: "?") {
            pathOnly = String(path[..<questionMark])
        } else {
            pathOnly = path
        }
        if pathOnly.hasPrefix("/repos/") {
            return true
        }
        return pathOnly == "/user" && githubReadMethods.contains(method)
    }

    /// Returns configuration and a call-local token without publishing its
    /// reference or any credential-backend failure details.
    private func githubContext() async throws -> (ToolsBrokerConfiguration.GitHub, String) {
        guard let github = configuration.github else {
            throw CallerFailure.githubNotConfigured
        }
        let token = try await resolveSecret(github.tokenReference)
        return (github, token)
    }

    /// Preserves the existing host-side request construction and auth headers.
    /// URL/path policy changes are deliberately outside this output-only draft.
    private func githubRequest(base: URL, method: String, path: String, token: String, body: Data? = nil) -> UpstreamHTTPRequest {
        // Parse path and query separately — URL.appending(path:) would
        // percent-encode ? in /repos/org/repo?state=open, breaking
        // pagination and filtering.
        let url: URL
        if let questionMark = path.firstIndex(of: "?") {
            let pathPart = String(path[..<questionMark])
            let queryPart = String(path[path.index(after: questionMark)...])
            var components = URLComponents(url: base.appending(path: pathPart), resolvingAgainstBaseURL: false)!
            components.query = queryPart
            url = components.url!
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

    /// Successful bodies are filtered before truncation. HTTP failures expose
    /// the numeric status and fixed copy only: arbitrary upstream error bodies
    /// are withheld wholesale, not merely searched for one known credential.
    private func githubResult(_ response: UpstreamHTTPResponse, token: String) throws -> ToolCallResult {
        guard (200 ..< 300).contains(response.status) else {
            return ToolCallResult(
                text: "GitHub upstream returned HTTP \(response.status): [redacted]",
                isError: true
            )
        }
        try requireAcceptedBody(response.body)
        return ToolCallResult(text: try SafeBrokerOutput.checkedBodyText(
            response.body,
            resolvedToken: token,
            maxBytes: configuration.maxResponseBytes,
            checkCancellation: outputCancellationCheck
        ))
    }

    // MARK: - Slack

    /// Retains the existing write gate and required-field checks; none of the
    /// rejected channel/text values are interpolated into caller-facing copy.
    private func slackPostMessage(arguments: [String: JSONValue]) async throws -> ToolCallResult {
        guard configuration.automationAllowed else {
            throw CallerFailure.slackAutomationRequired
        }
        guard let channel = arguments["channel"]?.stringValue, !channel.isEmpty else {
            throw CallerFailure.slackChannelRequired
        }
        guard let text = arguments["text"]?.stringValue, !text.isEmpty else {
            throw CallerFailure.slackTextRequired
        }
        return try await slackCall(method: "chat.postMessage", payload: [
            "channel": .string(channel),
            "text": .string(text),
        ])
    }

    /// Retains the host allowlist and write gate but omits rejected method
    /// values, including secret-bearing values supplied before resolution.
    private func slackRequest(arguments: [String: JSONValue]) async throws -> ToolCallResult {
        guard let method = arguments["method"]?.stringValue, !method.isEmpty else {
            throw CallerFailure.slackMethodRequired
        }
        guard configuration.allowedSlackMethods.contains(method) else {
            throw CallerFailure.slackMethodDenied
        }
        if !configuration.automationAllowed {
            throw CallerFailure.slackAutomationRequired
        }
        let payload = arguments["arguments"]?.objectValue ?? [:]
        return try await slackCall(method: method, payload: payload)
    }

    /// Performs the existing injected Slack call. HTTP and logical errors are
    /// classified structurally, not by echoing arbitrary body/error strings.
    /// Decode failures get fixed copy; no try? collapses malformed into absent.
    private func slackCall(method: String, payload: [String: JSONValue]) async throws -> ToolCallResult {
        guard let slack = configuration.slack else {
            throw CallerFailure.slackNotConfigured
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
        try Task.checkCancellation()
        guard (200 ..< 300).contains(response.status) else {
            return ToolCallResult(
                text: "Slack upstream returned HTTP \(response.status): [redacted]",
                isError: true
            )
        }
        try requireAcceptedBody(response.body)
        try outputCancellationCheck(.beforeSlackDecode)
        let status: SlackResponseStatus
        do {
            status = try JSONDecoder().decode(SlackResponseStatus.self, from: response.body)
        } catch {
            try outputCancellationCheck(.afterSlackDecode)
            throw CallerFailure.slackMalformedResponse
        }
        try outputCancellationCheck(.afterSlackDecode)
        // Slack signals logical errors with HTTP 200 + {"ok": false}.
        if !status.ok {
            return try slackErrorResult(response.body)
        }
        return ToolCallResult(text: try SafeBrokerOutput.checkedBodyText(
            response.body,
            resolvedToken: token,
            maxBytes: configuration.maxResponseBytes,
            checkCancellation: outputCancellationCheck
        ))
    }

    /// Preserves only the safe, existing channel_not_found compatibility
    /// message. Unknown, missing, or incorrectly typed error values are all
    /// withheld. Additional codes must be reviewed as explicit constant cases;
    /// a character/length regex would still permit arbitrary caller data.
    private func slackErrorResult(_ body: Data) throws -> ToolCallResult {
        try outputCancellationCheck(.beforeSlackErrorDecode)
        let envelope: SlackResponseError
        do {
            envelope = try JSONDecoder().decode(SlackResponseError.self, from: body)
        } catch {
            try outputCancellationCheck(.afterSlackErrorDecode)
            return ToolCallResult(text: "Slack API error.", isError: true)
        }
        try outputCancellationCheck(.afterSlackErrorDecode)
        switch envelope.error {
        case .some("channel_not_found"):
            return ToolCallResult(text: "Slack API error: channel_not_found", isError: true)
        default:
            return ToolCallResult(text: "Slack API error.", isError: true)
        }
    }

    /// Independent, inclusive 1 MiB acceptance ceiling before UTF-8 or Slack
    /// decoding, even for an injected transport. Root transport defaults to
    /// 8 MiB and is not changed here. Non-2xx bodies are never decoded at all.
    private func requireAcceptedBody(_ body: Data) throws {
        guard body.count <= SafeBrokerOutput.maxAcceptedBodyBytes else {
            throw CallerFailure.responseTooLarge
        }
    }

    // MARK: - Secrets

    /// Maps all credential lookup failures to a private constant without
    /// evaluating backend exception descriptions, service, or account values.
    /// Checks cancellation around the await so a cancelled lookup cannot
    /// proceed to an HTTP call when the provider returns despite cancellation.
    /// Generic lookup stays byte-exact; bearer validation belongs to this consumer.
    private func resolveSecret(_ reference: SecretReference) async throws -> String {
        do {
            try Task.checkCancellation()
            let token = try await secrets.secret(for: reference)
            try Task.checkCancellation()
            guard Self.isValidBearerToken(token) else { throw CallerFailure.secretUnavailable }
            return token
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CallerFailure.secretUnavailable
        }
    }

    /// Broker-only RFC 6750 section 2.1 b64token policy:
    /// 1*( ALPHA / DIGIT / "-" / "." / "_" / "~" / "+" / "/" ) *"=".
    /// ASCII, nonempty, at most 4096 bytes including optional trailing '='.
    /// Padding need not have a Base64 quantum length: b64token is a grammar,
    /// not Base64 decoding. No trimming/normalization, provider-prefix rules,
    /// or generic-secret mutation. Whitespace, CR/LF/NUL, non-ASCII, a leading
    /// '=', or a non-padding byte after '=' fails before request construction.
    private static func isValidBearerToken(_ token: String) -> Bool {
        var count = 0
        var coreCount = 0
        var padding = false
        for byte in token.utf8 {
            count += 1
            guard count <= SafeBrokerOutput.maxTokenBytes else { return false }
            if byte == 0x3D {
                guard coreCount > 0 else { return false }
                padding = true
                continue
            }
            guard !padding else { return false }
            switch byte {
            case 0x41 ... 0x5A, 0x61 ... 0x7A, 0x30 ... 0x39,
                 0x2D, 0x2E, 0x5F, 0x7E, 0x2B, 0x2F:
                coreCount += 1
            default:
                return false
            }
        }
        return coreCount > 0
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
