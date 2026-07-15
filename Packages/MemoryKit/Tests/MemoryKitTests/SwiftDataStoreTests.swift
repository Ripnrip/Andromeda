/**
 * 🎭 SwiftDataStoreTests - The Quality Assurance Ritual
 *
 * "A grand spectacle of assertions, concurrently squeezing our Memory Vault
 * to prove its resilience under extreme theatrical conditions.
 * May our tests run like rivers and shine like stars!"
 *
 * - The Spellbinding Museum Director of Testing
 */

import Testing
@testable import MemoryKit
import Foundation
import SwiftData

@Suite("🔮 The Sacred Vault Testing Rituals")
struct SwiftDataStoreTests {
    
    // 🌟 Helper to conjure a fresh, empty in-memory vault for testing
    private func createFreshVault() async throws -> SwiftDataContainer {
        try await SwiftDataContainer.createInMemory()
    }

    @Test("📥 Insertion & Retrieval Magic - Storing and recalling a unique memory neuron")
    func testInsertionAndRetrieval() async throws {
        let vault = try await createFreshVault()
        
        let record = AnimaEpisodicRecordSnapshot(
            id: UUID(),
            contentHash: "sha256:magic123",
            createdAt: Date(),
            project: "Anima",
            agent: "claude-code",
            narrative: "I have discovered the elixir of state consistency.",
            visibility: "private",
            provenance: "Unit Test Source",
            tags: ["insight/discovery", "elixir"]
        )
        
        // Let's insert the snapshot
        try await vault.insert(record)
        
        // Let's count them
        let totalCount = try await vault.count()
        #expect(totalCount == 1, "There should be exactly one memory lingering in the vault.")
        
        // Let's fetch by ID
        let fetchedByID = try await vault.fetch(id: record.id)
        #expect(fetchedByID != nil, "We must find our newborn memory by its UUID!")
        #expect(fetchedByID?.contentHash == "sha256:magic123")
        #expect(fetchedByID?.narrative == "I have discovered the elixir of state consistency.")
        #expect(fetchedByID?.tags == ["insight/discovery", "elixir"])
        
        // Let's fetch by content hash
        let fetchedByHash = try await vault.fetchByContentHash("sha256:magic123")
        #expect(fetchedByHash != nil, "We must find our newborn memory by its content hash!")
        #expect(fetchedByHash?.id == record.id)
    }

    /// 🧪 Task #1 Proof Harness — DATA-CONTRACTS.md §12 hot capture store.
    ///
    /// Hot-path boundary (documented, structural):
    /// `SwiftDataContainer.insert` only touches ModelContext + SwiftData save.
    /// It does NOT import, construct, or await Obsidian writers, QdrantIndexer,
    /// or LadybugIndexer. Cold projection (`materializedPath`) stays nil until
    /// a separate materialization pass — proving store returns after local txn.
    @Test("🧾 Task1 Proof Harness — in-memory insert, unique hash, private visibility, no cold-path side effects")
    func testTask1HotStoreProofHarness() async throws {
        let vault = try await createFreshVault()
        let contentHash = "sha256:task1-proof-hot-store"
        let provenance = "proof://anima-memory/task1/swiftdata-hot-store"

        let snapshot = AnimaEpisodicRecordSnapshot(
            id: UUID(),
            contentHash: contentHash,
            createdAt: Date(),
            project: "MemoryKit",
            agent: "cursor-proof",
            narrative: "Task 1 proof: local ACID insert without Obsidian/Qdrant.",
            visibility: "private",
            provenance: provenance,
            tags: ["proof/task1", "hot-store"],
            materializedPath: nil
        )

        try await vault.insert(snapshot, checkUniqueHash: true)

        let roundTrip = try await vault.fetchByContentHash(contentHash)
        #expect(roundTrip != nil)
        #expect(roundTrip?.id == snapshot.id)
        #expect(roundTrip?.visibility == "private")
        #expect(roundTrip?.provenance == provenance)
        #expect(roundTrip?.contentHash == contentHash)
        // 🌙 Cold path not invoked: Obsidian projection path remains unset after store.
        #expect(roundTrip?.materializedPath == nil)

        let duplicate = AnimaEpisodicRecordSnapshot(
            id: UUID(),
            contentHash: contentHash,
            project: "MemoryKit",
            agent: "cursor-proof",
            narrative: "Duplicate must be rejected when uniqueness is enforced.",
            visibility: "private",
            provenance: provenance
        )
        await #expect(throws: AnimaStorageError.self) {
            try await vault.insert(duplicate, checkUniqueHash: true)
        }

        #expect(try await vault.count() == 1)
    }

    @Test("🛡️ Guard of Uniqueness - Throws duplicate error when configured to check")
    func testUniqueConstraintCheck() async throws {
        let vault = try await createFreshVault()
        
        let record1 = AnimaEpisodicRecordSnapshot(
            id: UUID(),
            contentHash: "sha256:same_hash",
            createdAt: Date(),
            project: "Anima",
            agent: "claude-code",
            narrative: "The original idea was perfect.",
            provenance: "Unit Test"
        )
        
        let record2 = AnimaEpisodicRecordSnapshot(
            id: UUID(),
            contentHash: "sha256:same_hash", // Same content hash!
            createdAt: Date(),
            project: "Andromeda",
            agent: "codex",
            narrative: "An identical copy of the same idea.",
            provenance: "Unit Test"
        )
        
        try await vault.insert(record1, checkUniqueHash: true)
        
        // Try inserting the duplicate record with validation and assert it throws
        await #expect(throws: AnimaStorageError.self) {
            try await vault.insert(record2, checkUniqueHash: true)
        }
    }

    @Test("🔄 SwiftData Native Upsert - Updates model values when duplicate hash is inserted")
    func testNativeUpsert() async throws {
        let vault = try await createFreshVault()
        
        let originalID = UUID()
        let record1 = AnimaEpisodicRecordSnapshot(
            id: originalID,
            contentHash: "sha256:native_upsert",
            createdAt: Date(),
            project: "Anima",
            agent: "claude-code",
            narrative: "First draft",
            provenance: "Unit Test"
        )
        
        let record2 = AnimaEpisodicRecordSnapshot(
            id: originalID, // Same ID & contentHash to trigger default unique resolution
            contentHash: "sha256:native_upsert",
            createdAt: Date(),
            project: "Anima-New",
            agent: "claude-code",
            narrative: "Second draft (refined)",
            provenance: "Unit Test"
        )
        
        try await vault.insert(record1, checkUniqueHash: false)
        try await vault.insert(record2, checkUniqueHash: false)
        
        // The count should still be 1 (upserted)
        let count = try await vault.count()
        #expect(count == 1, "SwiftData should have upserted the record, leaving count at 1.")
        
        let fetched = try await vault.fetch(id: originalID)
        #expect(fetched?.project == "Anima-New", "Project should have updated to the refined draft.")
        #expect(fetched?.narrative == "Second draft (refined)", "Narrative should have updated to the refined draft.")
    }

    @Test("🎨 The Selective Filter - Queries with specific properties")
    func testSelectiveFiltering() async throws {
        let vault = try await createFreshVault()
        
        let records = [
            AnimaEpisodicRecordSnapshot(
                contentHash: "hash1", project: "ProjectA", agent: "claude", visibility: "public", provenance: "Test"
            ),
            AnimaEpisodicRecordSnapshot(
                contentHash: "hash2", project: "ProjectA", agent: "codex", visibility: "private", provenance: "Test"
            ),
            AnimaEpisodicRecordSnapshot(
                contentHash: "hash3", project: "ProjectB", agent: "claude", visibility: "private", provenance: "Test"
            )
        ]
        
        for record in records {
            try await vault.insert(record)
        }
        
        // Filter by project "ProjectA"
        let projectAOnly = try await vault.fetchWithFilters(project: "ProjectA")
        #expect(projectAOnly.count == 2, "We should get exactly two ProjectA records!")
        
        // Filter by agent "claude" and visibility "private"
        let privateClaude = try await vault.fetchWithFilters(agent: "claude", visibility: "private")
        #expect(privateClaude.count == 1, "We should find exactly one private claude memory!")
        #expect(privateClaude.first?.project == "ProjectB")
    }

    @Test("💅 Refashioning - Updating an existing record in the vault")
    func testUpdateRecord() async throws {
        let vault = try await createFreshVault()
        
        let id = UUID()
        let record = AnimaEpisodicRecordSnapshot(
            id: id,
            contentHash: "sha256:update_me",
            project: "OldProject",
            agent: "old-agent",
            narrative: "Original tale",
            provenance: "Test"
        )
        
        try await vault.insert(record)
        
        let updatedRecord = AnimaEpisodicRecordSnapshot(
            id: id,
            contentHash: "sha256:update_me",
            project: "NewProject",
            agent: "new-agent",
            narrative: "New tale",
            provenance: "Test",
            materializedPath: "/path/to/obsidian"
        )
        
        try await vault.update(updatedRecord)
        
        let fetched = try await vault.fetch(id: id)
        #expect(fetched?.project == "NewProject", "The project name must reflect our changes!")
        #expect(fetched?.agent == "new-agent", "The agent name must be updated!")
        #expect(fetched?.narrative == "New tale", "The narrative must be updated!")
        #expect(fetched?.materializedPath == "/path/to/obsidian", "The projection path should now be set!")
    }

    @Test("🩹 Vanishing Act - Erasing a memory from the scroll")
    func testDeleteRecord() async throws {
        let vault = try await createFreshVault()
        let id = UUID()
        let record = AnimaEpisodicRecordSnapshot(
            id: id, contentHash: "hash", project: "P", agent: "A", narrative: "N", provenance: "P"
        )
        
        try await vault.insert(record)
        try await vault.delete(id: id)
        
        let fetched = try await vault.fetch(id: id)
        #expect(fetched == nil, "The erased memory must no longer linger in the archives.")
        
        let count = try await vault.count()
        #expect(count == 0, "Our vault should be empty once more.")
    }

    @Test("🧹 Tabula Rasa - Erasing everything at once")
    func testClearAllRecords() async throws {
        let vault = try await createFreshVault()
        try await vault.insert(AnimaEpisodicRecordSnapshot(
            contentHash: "1", project: "P", agent: "A", narrative: "N", provenance: "P"
        ))
        try await vault.insert(AnimaEpisodicRecordSnapshot(
            contentHash: "2", project: "P", agent: "A", narrative: "N2", provenance: "P"
        ))
        
        try await vault.clearAll()
        
        let count = try await vault.count()
        #expect(count == 0, "All traces of thoughts must have evaporated!")
    }

    @Test("🎪 Concurrent Symphony - Blazing reads and writes across parallel tasks")
    func testConcurrentOperations() async throws {
        let vault = try await createFreshVault()
        let writeCount = 50
        
        // 🔮 Act 1: Trigger 50 parallel writes to the memory vault
        try await withTaskGroup(of: Void.self) { group in
            for index in 0..<writeCount {
                group.addTask {
                    let snapshot = AnimaEpisodicRecordSnapshot(
                        id: UUID(),
                        contentHash: "sha256:concurrent_\(index)",
                        createdAt: Date(),
                        project: "Project_\(index % 3)",
                        agent: "Agent_\(index % 2)",
                        narrative: "Concurrent thought \(index)",
                        provenance: "Stress Test"
                    )
                    do {
                        try await vault.insert(snapshot)
                    } catch {
                        Issue.record("Failed to insert concurrent record: \(error)")
                    }
                }
            }
            
            // Wait for all parallel transactions to seal
            await group.waitForAll()
        }
        
        let totalCount = try await vault.count()
        #expect(totalCount == writeCount, "All concurrent writes should have safely landed in the vault without data races.")
        
        // 🔮 Act 2: Trigger 50 parallel reads from the memory vault
        try await withTaskGroup(of: AnimaEpisodicRecordSnapshot?.self) { group in
            for index in 0..<writeCount {
                group.addTask {
                    try? await vault.fetchByContentHash("sha256:concurrent_\(index)")
                }
            }
            
            var readResults: [AnimaEpisodicRecordSnapshot] = []
            for await result in group {
                if let snapshot = result {
                    readResults.append(snapshot)
                }
            }
            
            #expect(
                readResults.count == writeCount,
                "All concurrent reads should have fetched their respective targets successfully!"
            )
        }
    }
}
