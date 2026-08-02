import Foundation

/// Guest-facing MCP config fragment for runtime v2 — never includes Slack/GitHub secrets.
/// VM agents only get the Andromeda `/mcp` URL plus a broker bearer token reference.
public struct GuestMCPConfig: Sendable, Equatable, Codable {
    public let serverName: String
    public let url: String
    /// Broker credential for Andromeda only (not upstream provider tokens).
    public let headers: [String: String]
    public let notes: String

    public init(serverName: String, url: String, headers: [String: String], notes: String) {
        self.serverName = serverName
        self.url = url
        self.headers = headers
        self.notes = notes
    }

    /// Builds a Cursor/Claude-compatible mcp.json entry pointing at Andromeda Runtime.
    public static func make(
        runtimeBaseURL: String,
        brokerToken: String?,
        includeBrokerTokenInline: Bool = false
    ) -> GuestMCPConfig {
        let trimmed = runtimeBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = trimmed.hasSuffix("/mcp") ? trimmed : trimmed + "/mcp"
        var headers: [String: String] = [:]
        if includeBrokerTokenInline, let brokerToken, !brokerToken.isEmpty {
            headers["Authorization"] = "Bearer \(brokerToken)"
        } else {
            headers["Authorization"] = "Bearer ${ANDROMEDA_MCP_BEARER_TOKEN}"
        }
        return GuestMCPConfig(
            serverName: "andromeda",
            url: url,
            headers: headers,
            notes: "Host Andromeda keeps Slack/GitHub tokens in Keychain. Guest configs must not contain SLACK_* or GITHUB_* secrets."
        )
    }

    /// Renders a Cursor-style mcp.json document.
    public func renderMCPJSON() throws -> String {
        let document: [String: Any] = [
            "mcpServers": [
                serverName: [
                    "url": url,
                    "headers": headers,
                ] as [String: Any],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw HostOpsError.encodeFailed("failed to encode guest mcp.json")
        }
        return text + "\n"
    }

    /// Returns true when the rendered config still contains forbidden upstream secret patterns.
    public static func containsUpstreamSecrets(_ text: String) -> Bool {
        let patterns = [
            "xoxb-",
            "xoxp-",
            "ghp_",
            "github_pat_",
            "SLACK_BOT_TOKEN",
            "SLACK_TOKEN",
            "GITHUB_TOKEN",
            "GH_TOKEN",
        ]
        return patterns.contains { text.contains($0) }
    }
}

/// Errors from host-ops helpers. Messages never include secret bytes.
public enum HostOpsError: Error, Equatable, LocalizedError {
    case encodeFailed(String)
    case keychainWriteFailed(String)
    case invalidURL(String)

    public var errorDescription: String? {
        switch self {
        case let .encodeFailed(reason):
            return reason
        case let .keychainWriteFailed(reason):
            return "Keychain write failed: \(reason)"
        case let .invalidURL(value):
            return "Invalid URL: \(value)"
        }
    }
}
