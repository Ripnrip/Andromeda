import Foundation

/// Stable capability curtain IDs exposed to guests — never provider brand menus.
public enum MCPCapabilityID: String, Sendable, Codable, CaseIterable {
    case slackProxy = "slack_proxy"
    case githubProxy = "github_proxy"
}

/// MCP tool descriptor returned by `tools/list`.
public struct MCPToolDescriptor: Sendable, Codable, Equatable {
    public let name: String
    public let description: String
    public let inputSchema: [String: AnyCodable]

    public init(name: String, description: String, inputSchema: [String: AnyCodable] = [:]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// Result of an MCP `tools/call` invocation (never embeds host secrets).
public struct MCPToolCallResult: Sendable, Codable, Equatable {
    public let content: [MCPContentBlock]
    public let isError: Bool

    public init(content: [MCPContentBlock], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    public static func text(_ value: String, isError: Bool = false) -> MCPToolCallResult {
        MCPToolCallResult(content: [.init(type: "text", text: value)], isError: isError)
    }
}

public struct MCPContentBlock: Sendable, Codable, Equatable {
    public let type: String
    public let text: String?

    public init(type: String, text: String?) {
        self.type = type
        self.text = text
    }
}

/// JSON-RPC 2.0 envelope used by MCP Streamable HTTP / JSON transports.
public struct MCPJSONRPCRequest: Sendable, Codable, Equatable {
    public let jsonrpc: String
    public let id: MCPJSONRPCID?
    public let method: String
    public let params: [String: AnyCodable]?

    public init(
        id: MCPJSONRPCID? = nil,
        method: String,
        params: [String: AnyCodable]? = nil
    ) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct MCPJSONRPCResponse: Sendable, Codable, Equatable {
    public let jsonrpc: String
    public let id: MCPJSONRPCID?
    public let result: AnyCodable?
    public let error: MCPJSONRPCError?

    public init(
        id: MCPJSONRPCID?,
        result: AnyCodable? = nil,
        error: MCPJSONRPCError? = nil
    ) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct MCPJSONRPCError: Sendable, Codable, Equatable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public enum MCPJSONRPCID: Sendable, Codable, Equatable {
    case string(String)
    case number(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.typeMismatch(
                MCPJSONRPCID.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected string or number id")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        }
    }
}

/// Minimal `AnyCodable` for schema/result dictionaries without pulling AutoCache.
public struct AnyCodable: @unchecked Sendable, Codable, Equatable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(AnyCodable.init))
        case let dict as [String: Any]:
            try container.encode(dict.mapValues(AnyCodable.init))
        default:
            throw EncodingError.invalidValue(
                value,
                .init(codingPath: encoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}
