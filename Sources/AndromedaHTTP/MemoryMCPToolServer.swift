import AndromedaDomain
import AndromedaMemory
import AndromedaTools
import Foundation

/// Provider-neutral `memory.*` MCP capabilities backed by the canonical journal and SQLite hot store.
public actor MemoryMCPToolServer: MCPToolServing {
    public static let storeTool = "memory.store"
    public static let recallTool = "memory.recall"
    private let runtime: MemoryRuntime

    public init(runtime: MemoryRuntime) { self.runtime = runtime }

    /// Advertises universal read/write capabilities without database or provider brands.
    public func listTools() -> [ToolDefinition] { [Self.storeDefinition, Self.recallDefinition] }

    /// Validates portable MCP arguments and invokes the append-first memory runtime.
    public func callTool(name: String, arguments: [String: JSONValue]) async -> ToolCallResult {
        do {
            switch name {
            case Self.storeTool: try await store(arguments)
            case Self.recallTool: try await recall(arguments)
            default: ToolCallResult(text: "Unknown memory capability: \(name)", isError: true)
            }
        } catch {
            ToolCallResult(text: "Memory capability failed: \(error.localizedDescription)", isError: true)
        }
    }

    /// Stores agent-authored memory with explicit provenance and replay-safe idempotency.
    private func store(_ arguments: [String: JSONValue]) async throws -> ToolCallResult {
        let content = try requiredString("content", in: arguments)
        let agentID = try requiredString("agent_id", in: arguments)
        let response = try await runtime.remember(RememberIntent(
            scope: .init(),
            source: .init(subsystem: "mcp", actor: agentID, label: "authenticated-agent"),
            content: content,
            kind: MemoryKind(rawValue: arguments["kind"]?.stringValue ?? "note") ?? .note,
            privacyLevel: PrivacyLevel(rawValue: arguments["privacy"]?.stringValue ?? "project") ?? .project,
            tags: arguments["tags"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            idempotencyKey: .init(rawValue: arguments["idempotency_key"]?.stringValue ?? UUID().uuidString)
        ))
        return try encoded(response)
    }

    /// Recalls shared memory up to the caller's explicit privacy ceiling.
    private func recall(_ arguments: [String: JSONValue]) async throws -> ToolCallResult {
        let response = try await runtime.recall(RecallRequest(
            query: try requiredString("query", in: arguments),
            purpose: arguments["purpose"]?.stringValue,
            scope: .init(),
            privacyCeiling: PrivacyLevel(rawValue: arguments["privacy_ceiling"]?.stringValue ?? "project") ?? .project,
            resultLimit: Int(arguments["limit"]?.numberValue ?? 5)
        ))
        return try encoded(response)
    }

    /// Rejects missing or blank strings before they reach persistence.
    private func requiredString(_ key: String, in arguments: [String: JSONValue]) throws -> String {
        guard let value = arguments[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw MemoryMCPError.invalidArgument("'\(key)' is required and must not be blank.")
        }
        return value
    }

    /// Encodes runtime receipts and provenance as portable JSON text content.
    private func encoded(_ value: some Encodable) throws -> ToolCallResult {
        ToolCallResult(text: String(decoding: try JSONEncoder().encode(value), as: UTF8.self))
    }

    private static let storeDefinition = ToolDefinition(name: storeTool, description: "Store shared memory for any authenticated agent.", inputSchema: .object([
        "type": .string("object"), "properties": .object([
            "content": .object(["type": .string("string")]), "agent_id": .object(["type": .string("string")]),
            "idempotency_key": .object(["type": .string("string")]), "kind": .object(["type": .string("string")]),
            "privacy": .object(["type": .string("string")]), "tags": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
        ]), "required": .array([.string("content"), .string("agent_id")]),
    ]))

    private static let recallDefinition = ToolDefinition(name: recallTool, description: "Recall shared memory for any authenticated agent.", inputSchema: .object([
        "type": .string("object"), "properties": .object([
            "query": .object(["type": .string("string")]), "purpose": .object(["type": .string("string")]),
            "limit": .object(["type": .string("number")]), "privacy_ceiling": .object(["type": .string("string")]),
        ]), "required": .array([.string("query")]),
    ]))
}

private enum MemoryMCPError: LocalizedError {
    case invalidArgument(String)
    var errorDescription: String? { if case let .invalidArgument(message) = self { message } else { nil } }
}
