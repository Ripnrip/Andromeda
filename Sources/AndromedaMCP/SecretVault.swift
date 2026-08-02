import Foundation

/// Host-side secret vault for MCP upstream credentials.
///
/// Guests never receive these values. Only boolean presence and capability
/// binding are exposed through doctor / audit surfaces.
public struct SecretVault: Sendable {
    public struct Snapshot: Sendable, Equatable {
        public let capability: MCPCapabilityID
        public let configured: Bool
        public let envKey: String
    }

    private let secrets: [MCPCapabilityID: String]

    public init(secrets: [MCPCapabilityID: String] = [:]) {
        self.secrets = secrets
    }

    /// Loads upstream tokens from process environment.
    ///
    /// - `SLACK_BOT_TOKEN` / `SLACK_TOKEN` → `slack_proxy`
    /// - `GITHUB_TOKEN` / `GH_TOKEN` → `github_proxy`
    public static func loadFromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SecretVault {
        var secrets: [MCPCapabilityID: String] = [:]
        if let slack = firstNonEmpty(environment, keys: ["SLACK_BOT_TOKEN", "SLACK_TOKEN"]) {
            secrets[.slackProxy] = slack
        }
        if let github = firstNonEmpty(environment, keys: ["GITHUB_TOKEN", "GH_TOKEN"]) {
            secrets[.githubProxy] = github
        }
        return SecretVault(secrets: secrets)
    }

    /// Returns the upstream credential for a capability without logging it.
    public func credential(for capability: MCPCapabilityID) -> String? {
        secrets[capability]
    }

    public func isConfigured(_ capability: MCPCapabilityID) -> Bool {
        guard let value = secrets[capability] else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var snapshots: [Snapshot] {
        MCPCapabilityID.allCases.map { capability in
            Snapshot(
                capability: capability,
                configured: isConfigured(capability),
                envKey: Self.envKey(for: capability)
            )
        }
    }

    public static func envKey(for capability: MCPCapabilityID) -> String {
        switch capability {
        case .slackProxy: "SLACK_BOT_TOKEN"
        case .githubProxy: "GITHUB_TOKEN"
        }
    }

    private static func firstNonEmpty(_ env: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = env[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }
}

/// Scrubs known secret material from strings before audit / guest output.
public struct SecretScrubber: Sendable {
    private let secrets: [String]

    public init(secrets: [String]) {
        self.secrets = secrets.filter { !$0.isEmpty }
    }

    public init(vault: SecretVault) {
        var values: [String] = []
        for capability in MCPCapabilityID.allCases {
            if let value = vault.credential(for: capability) {
                values.append(value)
            }
        }
        self.init(secrets: values)
    }

    /// Replaces any configured secret substring with a redaction token.
    public func scrub(_ text: String) -> String {
        var result = text
        for secret in secrets {
            result = result.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
        return result
    }

    /// Returns true when the text still appears to contain a known secret.
    public func containsSecret(_ text: String) -> Bool {
        secrets.contains { text.contains($0) }
    }
}
