import AndromedaTools
import Foundation

/// Operator-internal request the runtime hands to a hosted ingress backend.
/// The MCP curtain never uses the word Letta in tool names or client-facing text.
public struct LettaIngressRequest: Sendable, Equatable {
    public let agentID: String
    public let title: String
    public let body: String
    public let visibility: String
    public let tags: [String]
    public let source: String

    public init(
        agentID: String,
        title: String,
        body: String,
        visibility: String,
        tags: [String],
        source: String
    ) {
        self.agentID = agentID
        self.title = title
        self.body = body
        self.visibility = visibility
        self.tags = tags
        self.source = source
    }
}

/// Proof a hosted ingress write sealed. `commitSHA` is the backend receipt,
/// not a brand clients are expected to interpret.
public struct LettaIngressReceipt: Sendable, Equatable, Codable {
    public let agentID: String
    public let relativePath: String
    public let commitSHA: String
    public let unchanged: Bool

    public init(agentID: String, relativePath: String, commitSHA: String, unchanged: Bool) {
        self.agentID = agentID
        self.relativePath = relativePath
        self.commitSHA = commitSHA
        self.unchanged = unchanged
    }
}

/// Seam the long-running runtime uses to host ingress without a second daemon.
public protocol LettaIngressHandling: Sendable {
    func write(_ request: LettaIngressRequest) async throws -> LettaIngressReceipt
}

/// `memory.ingress` — upsert a tagged fact into a named agent's core memory.
/// Mounted only when serve hosts an ingress handler behind the MCP bearer.
public actor LettaIngressMCPToolServer: MCPToolServing {
    public static let toolName = "memory.ingress"

    private let handler: any LettaIngressHandling

    public init(handler: any LettaIngressHandling) {
        self.handler = handler
    }

    /// Advertises the one ingress capability. No backend brand in the name.
    public func listTools() async -> [ToolDefinition] { [Self.definition] }

    /// Validates required fields, then delegates. Untagged writes are rejected here.
    public func callTool(name: String, arguments: [String: JSONValue]) async -> ToolCallResult {
        guard name == Self.toolName else {
            return ToolCallResult(text: "Unknown memory capability: \(name)", isError: true)
        }
        do {
            let request = try Self.request(from: arguments)
            let receipt = try await handler.write(request)
            let data = try JSONEncoder().encode(receipt)
            return ToolCallResult(text: String(decoding: data, as: UTF8.self))
        } catch {
            return ToolCallResult(
                text: "Memory ingress failed: \(error.localizedDescription)",
                isError: true
            )
        }
    }

    /// Builds a request or throws when a required field is blank or untagged.
    private static func request(from arguments: [String: JSONValue]) throws -> LettaIngressRequest {
        func required(_ key: String) throws -> String {
            guard let value = arguments[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else {
                throw IngressToolError.invalidArgument("'\(key)' is required and must not be blank.")
            }
            return value
        }
        let visibility = try required("visibility")
        guard ["public", "friends", "private", "internal"].contains(visibility) else {
            throw IngressToolError.invalidArgument(
                "'visibility' must be one of public, friends, private, internal."
            )
        }
        let tags = arguments["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let source = arguments["source"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LettaIngressRequest(
            agentID: try required("agent_id"),
            title: try required("title"),
            body: try required("body"),
            visibility: visibility,
            tags: tags,
            source: (source?.isEmpty == false) ? source! : "authenticated-agent"
        )
    }

    private static let definition = ToolDefinition(
        name: toolName,
        description: "Upsert a tagged fact into a named agent's core memory. A visibility tag is required.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "agent_id": .object(["type": .string("string")]),
                "title": .object(["type": .string("string")]),
                "body": .object(["type": .string("string")]),
                "visibility": .object(["type": .string("string")]),
                "tags": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "source": .object(["type": .string("string")]),
            ]),
            "required": .array([
                .string("agent_id"), .string("title"), .string("body"), .string("visibility"),
            ]),
        ])
    )
}

private enum IngressToolError: LocalizedError {
    case invalidArgument(String)

    var errorDescription: String? {
        if case let .invalidArgument(message) = self { message } else { nil }
    }
}
