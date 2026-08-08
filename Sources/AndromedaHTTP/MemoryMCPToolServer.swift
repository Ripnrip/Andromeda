import AndromedaDomain
import AndromedaMemory
import AndromedaTools
import CryptoKit
import Foundation

/// Provider-neutral `memory.*` MCP capabilities backed by the canonical journal and SQLite hot store.
public actor MemoryMCPToolServer: MCPToolServing {
    public static let storeTool = "memory.store"
    public static let recallTool = "memory.recall"

    /// Stable shared project scope so default `project` privacy remains recallable across agents.
    public static let sharedProjectID = ProjectID(
        rawValue: UUID(uuidString: "a11d0000-1111-4000-8000-000000000001")!
    )

    private static let maxRecallLimit = 100
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
        let privacy = PrivacyLevel(rawValue: arguments["privacy"]?.stringValue ?? "project") ?? .project
        let callerKey = arguments["idempotency_key"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let idempotencyKey = Self.namespacedIdempotencyKey(agentID: agentID, callerKey: callerKey)
        let response = try await runtime.remember(RememberIntent(
            scope: Self.scope(privacy: privacy, agentID: agentID),
            source: .init(subsystem: "mcp", actor: agentID, label: "authenticated-agent"),
            content: content,
            kind: MemoryKind(rawValue: arguments["kind"]?.stringValue ?? "note") ?? .note,
            privacyLevel: privacy,
            tags: arguments["tags"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            idempotencyKey: idempotencyKey
        ))
        return try encoded(response)
    }

    /// Recalls shared memory up to the caller's explicit privacy ceiling.
    private func recall(_ arguments: [String: JSONValue]) async throws -> ToolCallResult {
        let privacyCeiling = PrivacyLevel(rawValue: arguments["privacy_ceiling"]?.stringValue ?? "project") ?? .project
        let agentID: String?
        if privacyCeiling == .private {
            agentID = try requiredString("agent_id", in: arguments)
        } else {
            agentID = arguments["agent_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let response = try await runtime.recall(RecallRequest(
            query: try requiredString("query", in: arguments),
            purpose: arguments["purpose"]?.stringValue,
            scope: Self.scope(privacy: privacyCeiling, agentID: agentID),
            privacyCeiling: privacyCeiling,
            resultLimit: try Self.positiveLimit(arguments["limit"], default: 5)
        ))
        return try encoded(response)
    }

    /// Builds a recallable scope: shared project for public/project, plus agent session for private.
    private static func scope(privacy: PrivacyLevel, agentID: String?) -> EventScope {
        switch privacy {
        case .public, .project:
            return EventScope(projectID: sharedProjectID)
        case .private:
            let identity = agentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sessionID = SessionID(rawValue: deterministicUUID(namespace: "mcp.memory.private", name: identity))
            return EventScope(projectID: sharedProjectID, sessionID: sessionID)
        }
    }

    /// Namespaces caller keys by agent so journal-wide dedupe cannot cross agent boundaries.
    private static func namespacedIdempotencyKey(agentID: String, callerKey: String?) -> IdempotencyKey {
        let suffix: String
        if let callerKey, !callerKey.isEmpty {
            suffix = callerKey
        } else {
            suffix = UUID().uuidString
        }
        return IdempotencyKey(rawValue: "mcp.memory.store:\(agentID):\(suffix)")
    }

    /// Validates finite, integral, positive limits before `Int` conversion so oversized JSON numbers cannot trap.
    private static func positiveLimit(_ value: JSONValue?, default defaultValue: Int) throws -> Int {
        guard let raw = value?.numberValue else { return defaultValue }
        guard raw.isFinite,
              raw >= 1,
              raw <= Double(maxRecallLimit),
              raw.rounded(.towardZero) == raw
        else {
            throw MemoryMCPError.invalidArgument(
                "'limit' must be a positive integer between 1 and \(maxRecallLimit)."
            )
        }
        return Int(raw)
    }

    /// Derives a stable UUID from an agent identity string for private session scoping.
    private static func deterministicUUID(namespace: String, name: String) -> UUID {
        let digest = SHA256.hash(data: Data("\(namespace)\u{0}\(name)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
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
            "agent_id": .object(["type": .string("string")]),
            "limit": .object(["type": .string("number")]), "privacy_ceiling": .object(["type": .string("string")]),
        ]), "required": .array([.string("query")]),
    ]))
}

private enum MemoryMCPError: LocalizedError {
    case invalidArgument(String)
    var errorDescription: String? { if case let .invalidArgument(message) = self { message } else { nil } }
}
