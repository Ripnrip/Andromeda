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
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let runtime = MemoryRuntime(
            journal: try JSONLineEventJournal(fileURL: directory.appending(path: "journal.jsonl")),
            operationalStore: try SQLiteMemoryOperationalStore(databaseURL: directory.appending(path: "memory.sqlite3"))
        )
        let server = MemoryMCPToolServer(runtime: runtime)

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
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = MemoryMCPToolServer(runtime: MemoryRuntime(
            journal: try JSONLineEventJournal(fileURL: directory.appending(path: "journal.jsonl")),
            operationalStore: try SQLiteMemoryOperationalStore(databaseURL: directory.appending(path: "memory.sqlite3"))
        ))

        let result = await server.callTool(name: "memory.store", arguments: ["content": .string("orphan")])
        #expect(result.isError)
        #expect(result.content.first?.text.contains("agent_id") == true)
    }
}
