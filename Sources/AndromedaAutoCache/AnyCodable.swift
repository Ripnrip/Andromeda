import Foundation

/// Minimal JSON value for tool schemas and dynamic Anthropic fields.
public enum JSONValue: Codable, Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    /// Stable description used for heuristic token counting of schemas.
    public var debugDescription: String {
        switch self {
        case .null: "null"
        case .bool(let value): String(value)
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .string(let value): value
        case .array(let values):
            "[" + values.map(\.debugDescription).joined(separator: ",") + "]"
        case .object(let values):
            "{" + values.map { "\($0.key):\($0.value.debugDescription)" }
                .sorted()
                .joined(separator: ",") + "}"
        }
    }

    /// Convenience builder from common Foundation JSON objects.
    public static func from(_ any: Any) -> JSONValue {
        switch any {
        case is NSNull:
            return .null
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return .array(array.map(JSONValue.from))
        case let dictionary as [String: Any]:
            return .object(dictionary.mapValues(JSONValue.from))
        default:
            return .string(String(describing: any))
        }
    }
}

/// Compatibility alias used by request models.
public typealias AnyCodable = JSONValue
