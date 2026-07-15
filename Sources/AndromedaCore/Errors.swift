/// Typed errors for Andromeda gateway and Autocache surfaces.
///
/// - Invariants: `code` is machine-stable; `message` is human-readable.
/// - Concurrency: value type, `Sendable`.
/// - Privacy: never embed secrets or raw prompts in `message`.
public enum AndromedaError: Error, Sendable, Equatable {
    case invalidConfiguration(String)
    case invalidRequest(String)
    case upstreamFailure(status: Int, message: String)
    case decodingFailed(String)
    case encodingFailed(String)
    case missingAPIKey
    case cancelled

    public var code: String {
        switch self {
        case .invalidConfiguration: "invalid_configuration"
        case .invalidRequest: "invalid_request"
        case .upstreamFailure: "upstream_failure"
        case .decodingFailed: "decoding_failed"
        case .encodingFailed: "encoding_failed"
        case .missingAPIKey: "missing_api_key"
        case .cancelled: "cancelled"
        }
    }

    public var message: String {
        switch self {
        case .invalidConfiguration(let detail): detail
        case .invalidRequest(let detail): detail
        case .upstreamFailure(_, let message): message
        case .decodingFailed(let detail): detail
        case .encodingFailed(let detail): detail
        case .missingAPIKey: "Anthropic API key missing from request headers and configuration"
        case .cancelled: "Operation cancelled"
        }
    }
}
