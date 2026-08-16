// RPC.swift — typed JSON-RPC 2.0 envelope models.
//
// The wire protocol is closed: this server defines every method, tool, and
// argument, so every message gets Codable models instead of a dynamic JSON
// enum. Method routing decodes in two typed passes over the same bytes
// (header first, then the full per-method request).

import Foundation

// MARK: - Request id

/// JSON-RPC ids are numbers or strings; `null` is a reply target but never
/// a request id, so decoding rejects it.
enum RPCID: Hashable, Sendable {
    case number(Int)
    case string(String)
}

extension RPCID: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Union probing: each attempt is a legitimate case of the id shape,
        // and failure of the last is a real decode error, not a silent nil.
        if let number = try? container.decode(Int.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected number or string request id"
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let number): try container.encode(number)
        case .string(let string): try container.encode(string)
        }
    }
}

// MARK: - Optional-wire-key encoding

/// Encodes the wrapped optional as a present key — `null` when nil —
/// instead of letting synthesized conformance drop the key entirely.
///
/// JSON-RPC 2.0: the `id` member is REQUIRED on responses and MUST be
/// null — not absent — when the request id could not be determined
/// (parse errors, invalid requests). Synthesized conformance would
/// `encodeIfPresent` and silently omit the key.
@propertyWrapper
struct EncodeNull<Value: Encodable & Sendable>: Encodable, Sendable {
    var wrappedValue: Value?

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let wrappedValue {
            try container.encode(wrappedValue)
        } else {
            try container.encodeNil()
        }
    }
}

// MARK: - Envelopes

/// First decode pass: enough of any message to route it.
struct RPCRequestHeader: Decodable, Sendable {
    let jsonrpc: String?
    let id: RPCID?
    let method: String
}

/// Second decode pass: a full request with typed params.
struct RPCRequest<Params: Decodable>: Decodable {
    let id: RPCID?
    let params: Params?
}

/// A `tools/call` request; `Arguments` is the tool-specific payload.
struct ToolCallRequest<Arguments: Decodable>: Decodable {
    struct Params: Decodable {
        let name: String
        let arguments: Arguments?
    }

    let id: RPCID?
    let params: Params
}

struct RPCResult<Response: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: RPCID?
    let result: Response
}

struct RPCErrorResponse: Encodable, Sendable {
    enum Code: Int, Sendable {
        case parseError = -32700
        case methodNotFound = -32601
        case invalidParams = -32602
        case internalError = -32603
    }

    struct Error: Encodable, Sendable {
        let code: Int
        let message: String
    }

    let jsonrpc = "2.0"

    @EncodeNull var id: RPCID?

    let error: Error

    init(id: RPCID?, code: Code, message: String) {
        self._id = EncodeNull(wrappedValue: id)
        self.error = Error(code: code.rawValue, message: message)
    }
}

// MARK: - Method payloads

struct InitializeResult: Encodable, Sendable {
    struct ServerInfo: Encodable, Sendable {
        let name: String
        let version: String
    }

    struct ToolsCapabilities: Encodable, Sendable {}

    struct Capabilities: Encodable, Sendable {
        let tools: ToolsCapabilities
    }

    let protocolVersion = "2025-06-18"
    let capabilities = Capabilities(tools: ToolsCapabilities())
    let serverInfo = ServerInfo(name: "andromeda-mcp", version: "1.1.0")
}

struct ToolsListResult: Encodable, Sendable {
    let tools: [Tool]
}

struct CallToolResult: Encodable, Sendable {
    struct TextContent: Encodable, Sendable {
        let type = "text"
        let text: String
    }

    let content: [TextContent]
    var isError = false

    static func text(_ message: String, isError: Bool = false) -> CallToolResult {
        CallToolResult(content: [TextContent(text: message)], isError: isError)
    }
}

/// Arguments payload for `tools/call` requests whose tool is not recognized;
/// only the id is needed to reply.
struct EmptyArguments: Decodable, Sendable {}

/// Empty `{}` result payload — the reply shape for `ping`.
struct EmptyResult: Encodable, Sendable {}

// MARK: - Decode evidence

extension DecodingError {
    /// Compact, caller-facing description that keeps the coding path — the
    /// evidence a client needs to fix the message — instead of collapsing
    /// to an opaque string.
    var brief: String {
        func path(_ context: Context) -> String {
            let joined = context.codingPath.map(\.stringValue).joined(separator: ".")
            return joined.isEmpty ? "root" : joined
        }
        switch self {
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context))"
        case .valueNotFound(_, let context):
            return "unexpected null at \(path(context))"
        case .typeMismatch(_, let context), .dataCorrupted(let context):
            return "\(localizedDescription) at \(path(context))"
        @unknown default:
            return localizedDescription
        }
    }
}
