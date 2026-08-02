import AndromedaSecrets
import Foundation

/// Host-side configuration for the tools broker. Holds secret *references*
/// (Keychain service/account names) — never raw tokens.
public struct ToolsBrokerConfiguration: Sendable, Equatable {
    public struct GitHub: Sendable, Equatable {
        public let tokenReference: SecretReference
        public let apiBaseURL: URL

        public init(
            tokenReference: SecretReference,
            apiBaseURL: URL = URL(string: "https://api.github.com")!
        ) {
            self.tokenReference = tokenReference
            self.apiBaseURL = apiBaseURL
        }
    }

    public struct Slack: Sendable, Equatable {
        public let tokenReference: SecretReference
        public let apiBaseURL: URL

        public init(
            tokenReference: SecretReference,
            apiBaseURL: URL = URL(string: "https://slack.com/api")!
        ) {
            self.tokenReference = tokenReference
            self.apiBaseURL = apiBaseURL
        }
    }

    /// Write operations (GitHub POST/PATCH/PUT/DELETE, any Slack write method)
    /// are rejected unless this is true — mirrors the AI-Config broker's
    /// `automation_allowed` policy gate.
    public let automationAllowed: Bool
    public let github: GitHub?
    public let slack: Slack?
    /// Slack Web API methods VM agents may invoke. Default is post-only.
    public let allowedSlackMethods: Set<String>
    /// Maximum upstream response body forwarded toward the VM. Larger bodies
    /// are truncated with a marker (SSRF/size hardening à la osaurus.fetch).
    public let maxResponseBytes: Int

    public init(
        automationAllowed: Bool = false,
        github: GitHub? = nil,
        slack: Slack? = nil,
        allowedSlackMethods: Set<String> = ["chat.postMessage"],
        maxResponseBytes: Int = 1_048_576
    ) throws {
        if let github {
            try Self.validateBaseURL(github.apiBaseURL, service: "GitHub")
        }
        if let slack {
            try Self.validateBaseURL(slack.apiBaseURL, service: "Slack")
        }
        self.automationAllowed = automationAllowed
        self.github = github
        self.slack = slack
        self.allowedSlackMethods = allowedSlackMethods
        self.maxResponseBytes = maxResponseBytes
    }

    /// Base URLs are host-side trust anchors: TLS only, explicit host, no
    /// userinfo, no IP literals. If a phase-2 backend ever lets the VM
    /// influence the origin, this must grow into full vetted-connect
    /// (host-side resolution + blocked-range checks à la SandboxEgressProxy).
    private static func validateBaseURL(_ url: URL, service: String) throws {
        guard url.scheme == "https", let host = url.host, !host.isEmpty else {
            throw ToolBrokerError.invalidConfiguration("\(service) base URL must be https with an explicit host.")
        }
        guard url.user == nil, url.password == nil else {
            throw ToolBrokerError.invalidConfiguration("\(service) base URL must not embed credentials.")
        }
        let isIPLiteral = host.split(separator: ".").count == 4
            && host.split(separator: ".").allSatisfy { $0.allSatisfy(\.isNumber) }
        guard !isIPLiteral, !host.contains(":") else {
            throw ToolBrokerError.invalidConfiguration("\(service) base URL host must be a name, not an IP literal.")
        }
    }
}

public enum ToolBrokerError: Error, Equatable, LocalizedError {
    case unknownTool(String)
    case serviceNotConfigured(String)
    case invalidConfiguration(String)
    case policyDenied(String)
    case invalidArguments(String)
    case secretUnavailable(String)
    case upstreamError(service: String, status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case let .unknownTool(name):
            return "Unknown tool: \(name)"
        case let .serviceNotConfigured(service):
            return "\(service) upstream is not configured on the host."
        case let .invalidConfiguration(reason):
            return "Invalid tools broker configuration: \(reason)"
        case let .policyDenied(reason):
            return "Policy denied: \(reason)"
        case let .invalidArguments(reason):
            return "Invalid tool arguments: \(reason)"
        case let .secretUnavailable(reason):
            return "Host secret unavailable: \(reason)"
        case let .upstreamError(service, status, body):
            return "\(service) upstream returned HTTP \(status): \(body)"
        }
    }
}
