import AndromedaHTTP
import AndromedaJournal
import AndromedaMemory
import AndromedaTools
import Foundation
import Testing

@Suite("AndromedaHTTP.MemoryMCPToolServer")
struct MemoryMCPToolServerTests {
    /// Proves that an arbitrary agent identity can write and then read the shared SQLite-backed memory surface.
    @Test("any authenticated agent identity can store and recall shared memory")
    func universalAgentRoundTrip() async throws {
        let server = try makeServer()

        let write = await server.callTool(name: "memory.store", arguments: [
            "agent_id": .string("hermes-squad-7"),
            "content": .string("Universal agents share this memory backend."),
            "idempotency_key": .string("universal-agent-round-trip"),
        ])
        #expect(!write.isError)
        #expect(write.content.first?.text.contains("memoryID") == true)

        let read = await server.callTool(name: "memory.recall", arguments: [
            "query": .string("Universal agents shared backend"),
            "privacy_ceiling": .string("project"),
        ])
        #expect(!read.isError)
        #expect(read.content.first?.text.contains("Universal agents share this memory backend.") == true)
    }

    /// Ensures protocol callers receive an observable error instead of a silent empty write.
    @Test("store rejects a missing portable agent identity")
    func storeRequiresAgentIdentity() async throws {
        let server = try makeServer()

        let result = await server.callTool(name: "memory.store", arguments: ["content": .string("orphan")])
        #expect(result.isError)
        #expect(result.content.first?.text.contains("agent_id") == true)
    }

    /// Two agents reusing the same caller key must keep independent canonical memories.
    @Test("idempotency keys are namespaced by agent identity")
    func idempotencyKeysAreAgentNamespaced() async throws {
        let server = try makeServer()

        let first = await server.callTool(name: "memory.store", arguments: [
            "agent_id": .string("agent-a"),
            "content": .string("Alpha memory payload."),
            "idempotency_key": .string("shared-caller-key"),
        ])
        let second = await server.callTool(name: "memory.store", arguments: [
            "agent_id": .string("agent-b"),
            "content": .string("Beta memory payload."),
            "idempotency_key": .string("shared-caller-key"),
        ])

        #expect(!first.isError)
        #expect(!second.isError)
        #expect(first.content.first?.text != second.content.first?.text)

        let alpha = await server.callTool(name: "memory.recall", arguments: [
            "query": .string("Alpha memory payload"),
            "privacy_ceiling": .string("project"),
        ])
        let beta = await server.callTool(name: "memory.recall", arguments: [
            "query": .string("Beta memory payload"),
            "privacy_ceiling": .string("project"),
        ])
        #expect(alpha.content.first?.text.contains("Alpha memory payload.") == true)
        #expect(beta.content.first?.text.contains("Beta memory payload.") == true)
    }

    /// Same agent + same key + different content must fail observably instead of discarding the write.
    @Test("store rejects idempotent replay with a different intent")
    func storeRejectsConflictingIdempotentReplay() async throws {
        let server = try makeServer()

        let first = await server.callTool(name: "memory.store", arguments: [
            "agent_id": .string("agent-a"),
            "content": .string("Canonical payload."),
            "idempotency_key": .string("conflict-key"),
        ])
        let conflict = await server.callTool(name: "memory.store", arguments: [
            "agent_id": .string("agent-a"),
            "content": .string("Different payload."),
            "idempotency_key": .string("conflict-key"),
        ])

        #expect(!first.isError)
        #expect(conflict.isError)
        #expect(conflict.content.first?.text.contains("Idempotency key") == true)
    }

    /// Oversized finite JSON numbers must return a tool error instead of trapping Int conversion.
    @Test("recall rejects oversized limit values without trapping")
    func recallRejectsOversizedLimit() async throws {
        let server = try makeServer()

        let result = await server.callTool(name: "memory.recall", arguments: [
            "query": .string("anything"),
            "limit": .number(1e300),
        ])
        #expect(result.isError)
        #expect(result.content.first?.text.contains("limit") == true)
    }

    /// Builds an isolated journal + SQLite runtime for each hermetic MCP tool case.
    private func makeServer() throws -> MemoryMCPToolServer {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let runtime = MemoryRuntime(
            journal: try JSONLineEventJournal(fileURL: directory.appending(path: "journal.jsonl")),
            operationalStore: try SQLiteMemoryOperationalStore(databaseURL: directory.appending(path: "memory.sqlite3"))
        )
        return MemoryMCPToolServer(runtime: runtime)
    }
}
