import AndromedaTools
import Foundation
import HTTPTypes
import Hummingbird

/// Bearer-token gate for the VM-facing MCP endpoint. The token authenticates
/// the *VM to Andromeda*; upstream GitHub/Slack tokens never leave the host.
public struct MCPBearerAuth: Sendable {
    public let token: String

    public init(token: String) {
        self.token = token
    }

    func isAuthorized(_ request: Request) -> Bool {
        guard !token.isEmpty else { return false }
        return request.headers[.authorization] == "Bearer \(token)"
    }
}

/// MCP (Model Context Protocol) server endpoint — streamable-HTTP flavor:
/// JSON-RPC 2.0 over POST /mcp. This is the single door VM agents use; their
/// MCP config contains only this URL and a bearer token, never upstream keys.
public struct MCPRoute: Sendable {
    public static let protocolVersion = "2025-03-26"

    private let broker: CuratedToolBroker
    private let auth: MCPBearerAuth
    private let serverName: String
    private let serverVersion: String

    public init(
        broker: CuratedToolBroker,
        auth: MCPBearerAuth,
        serverName: String = "andromeda",
        serverVersion: String
    ) {
        self.broker = broker
        self.auth = auth
        self.serverName = serverName
        self.serverVersion = serverVersion
    }

    public func register(on router: Router<BasicRequestContext>) {
        let broker = self.broker
        let auth = self.auth
        let serverName = self.serverName
        let serverVersion = self.serverVersion

        router.post("/mcp") { request, _ -> Response in
            guard auth.isAuthorized(request) else {
                return Self.unauthorized()
            }

            let body = try? await request.body.collect(upTo: 4 * 1024 * 1024)
            let data = body.map { Data($0.readableBytesView) } ?? Data()

            guard let payload = try? JSONDecoder().decode(MCPPayload.self, from: data) else {
                return Self.rpcResponse(
                    JSONRPCMessage.failure(id: .null, code: -32700, message: "Parse error")
                )
            }

            switch payload {
            case let .single(envelope):
                if envelope.id == nil {
                    // Pure notification (e.g. notifications/initialized): accept, no reply.
                    return Response(status: .accepted)
                }
                let message = await Self.handle(envelope, broker: broker, serverName: serverName, serverVersion: serverVersion)
                return Self.rpcResponse(message)
            case let .batch(envelopes):
                let withIDs = envelopes.filter { $0.id != nil }
                if withIDs.isEmpty {
                    return Response(status: .accepted)
                }
                var messages: [JSONRPCMessage] = []
                for envelope in withIDs {
                    messages.append(await Self.handle(envelope, broker: broker, serverName: serverName, serverVersion: serverVersion))
                }
                return Self.rpcBatchResponse(messages)
            }
        }
    }

    // MARK: - Method handling

    private static func handle(
        _ envelope: JSONRPCEnvelope,
        broker: CuratedToolBroker,
        serverName: String,
        serverVersion: String
    ) async -> JSONRPCMessage {
        let id = envelope.id.flatMap { $0 } ?? JSONValue.null
        switch envelope.method {
        case "initialize":
            // We answer with the newest version we support; clients that
            // requested an older compatible version accept this per spec.
            return .success(id: id, result: .object([
                "protocolVersion": .string(protocolVersion),
                "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
                "serverInfo": .object([
                    "name": .string(serverName),
                    "version": .string(serverVersion),
                ]),
            ]))
        case "ping":
            return .success(id: id, result: .object([:]))
        case "tools/list":
            let tools = await broker.listTools().map { tool -> JSONValue in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "inputSchema": tool.inputSchema,
                ])
            }
            return .success(id: id, result: .object(["tools": .array(tools)]))
        case "tools/call":
            guard let params = envelope.params?.objectValue,
                  let name = params["name"]?.stringValue
            else {
                return .failure(id: id, code: -32602, message: "Invalid params: 'name' is required.")
            }
            let arguments = params["arguments"]?.objectValue ?? [:]
            let result = await broker.callTool(name: name, arguments: arguments)
            return .success(id: id, result: .object([
                "content": .array(result.content.map { content in
                    .object(["type": .string(content.type), "text": .string(content.text)])
                }),
                "isError": .bool(result.isError),
            ]))
        default:
            if envelope.method.hasPrefix("notifications/") {
                // Notifications with an id are unusual but legal to answer.
                return .success(id: id, result: .object([:]))
            }
            return .failure(id: id, code: -32601, message: "Method not found: \(envelope.method)")
        }
    }

    // MARK: - Responses

    private static func rpcResponse(_ message: JSONRPCMessage) -> Response {
        encode(message, status: .ok)
    }

    private static func rpcBatchResponse(_ messages: [JSONRPCMessage]) -> Response {
        encode(messages, status: .ok)
    }

    private static func unauthorized() -> Response {
        encode(["error": "unauthorized: valid bearer token required"], status: .unauthorized)
    }

    private static func encode(_ value: some Encodable, status: HTTPResponse.Status) -> Response {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: status, headers: headers, body: .init(byteBuffer: .init(data: data)))
    }
}

// MARK: - JSON-RPC wire types

private enum MCPPayload: Decodable {
    case single(JSONRPCEnvelope)
    case batch([JSONRPCEnvelope])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let batch = try? container.decode([JSONRPCEnvelope].self) {
            self = .batch(batch)
        } else {
            self = .single(try container.decode(JSONRPCEnvelope.self))
        }
    }
}

private struct JSONRPCEnvelope: Decodable {
    let id: JSONValue??
    let method: String
    let params: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case id, method, params
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Distinguish "no id field" (notification) from explicit null id.
        if container.contains(.id) {
            id = try container.decode(JSONValue.self, forKey: .id)
        } else {
            id = nil
        }
        method = try container.decode(String.self, forKey: .method)
        params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
    }
}

private enum JSONRPCMessage: Encodable {
    case success(id: JSONValue, result: JSONValue)
    case failure(id: JSONValue, code: Int, message: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("2.0", forKey: .jsonrpc)
        switch self {
        case let .success(id, result):
            try container.encode(id, forKey: .id)
            try container.encode(result, forKey: .result)
        case let .failure(id, code, message):
            try container.encode(id, forKey: .id)
            try container.encode(RPCErrorBody(code: code, message: message), forKey: .error)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }

    private struct RPCErrorBody: Encodable {
        let code: Int
        let message: String
    }
}
