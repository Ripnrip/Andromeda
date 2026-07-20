/**
 * 🎭 CaptureServiceTests - The Hot-Path Capture Quality Ritual
 *
 * "Before the cold world of Obsidian and vectors may stir, we prove the quill:
 * hash the narrative, commit the ACID row, seal the ledger, return the id —
 * and never once knock on Qdrant's door."
 *
 * - The Spellbinding Museum Director of Testing
 */

import Testing
@testable import MemoryKit
import Foundation
import CryptoKit

@Suite("📥 The Store Memory Capture Rituals")
struct CaptureServiceTests {

    // 🌟 Helper — fresh in-memory vault + capture service with a live seal ledger
    private func makeCaptureService(withLedger: Bool = true) async throws -> CaptureService {
        let vault = try await SwiftDataContainer.createInMemory()
        let ledger: AnimaLedger? = withLedger ? AnimaLedger() : nil
        return CaptureService(container: vault, ledger: ledger)
    }

    // 🌟 Helper — vault alone so we can round-trip fetch after capture
    private func makeVaultAndService(withLedger: Bool = true) async throws -> (SwiftDataContainer, CaptureService) {
        let vault = try await SwiftDataContainer.createInMemory()
        let ledger: AnimaLedger? = withLedger ? AnimaLedger() : nil
        let service = CaptureService(container: vault, ledger: ledger)
        return (vault, service)
    }

    @Test("🧮 content_hash is deterministic SHA-256 of the narrative")
    func testContentHashDeterminism() {
        let narrative = "The cafe remembers every order."
        let hashA = CaptureService.contentHash(for: narrative)
        let hashB = CaptureService.contentHash(for: narrative)

        #expect(hashA == hashB)
        #expect(hashA.hasPrefix("sha256:"))

        let digest = SHA256.hash(data: Data(narrative.utf8))
        let expectedHex = digest.map { String(format: "%02x", $0) }.joined()
        #expect(hashA == "sha256:\(expectedHex)")

        let different = CaptureService.contentHash(for: "A different tale entirely.")
        #expect(different != hashA)
    }

    @Test("📥 store_memory returns MemoryID immediately and persists the snapshot")
    func testStoreMemoryReturnsIDAndPersists() async throws {
        let (vault, service) = try await makeVaultAndService()
        let narrative = "Task 4: hot capture without cold-path waits."

        let memoryID = try await service.storeMemory(
            narrative: narrative,
            project: "MemoryKit",
            agent: "cursor-proof",
            provenance: "proof://anima-memory/task4/store-memory"
        )

        #expect(memoryID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))

        let fetched = try await vault.fetch(id: memoryID)
        #expect(fetched != nil)
        #expect(fetched?.id == memoryID)
        #expect(fetched?.narrative == narrative)
        #expect(fetched?.contentHash == CaptureService.contentHash(for: narrative))
        #expect(fetched?.visibility == "private")
        #expect(fetched?.materializedPath == nil)
    }

    @Test("🔒 Default visibility is private; override is honored")
    func testVisibilityDefaultAndOverride() async throws {
        let (vault, service) = try await makeVaultAndService()

        let privateID = try await service.storeMemory(
            narrative: "A private whisper for the vault alone.",
            project: "Anima",
            agent: "test",
            provenance: "unit-test"
        )
        let privateRecord = try await vault.fetch(id: privateID)
        #expect(privateRecord?.visibility == "private")

        let publicID = try await service.storeMemory(
            narrative: "A public proclamation for the hive.",
            project: "Anima",
            agent: "test",
            provenance: "unit-test",
            visibility: "public"
        )
        let publicRecord = try await vault.fetch(id: publicID)
        #expect(publicRecord?.visibility == "public")

        let friendsID = try await service.storeMemory(
            narrative: "A friends-circle anecdote.",
            project: "Anima",
            agent: "test",
            provenance: "unit-test",
            visibility: "friends"
        )
        let friendsRecord = try await vault.fetch(id: friendsID)
        #expect(friendsRecord?.visibility == "friends")

        // Unknown visibility falls back to private
        let fallbackID = try await service.storeMemory(
            narrative: "Mystery cloak that is not a known class.",
            project: "Anima",
            agent: "test",
            provenance: "unit-test",
            visibility: "totally-made-up"
        )
        let fallbackRecord = try await vault.fetch(id: fallbackID)
        #expect(fallbackRecord?.visibility == "private")
    }

    @Test("🛡️ AnimaSeal ledger appends and verifies after store_memory")
    func testSealWhenLedgerAvailable() async throws {
        let service = try await makeCaptureService(withLedger: true)

        let id1 = try await service.storeMemory(
            narrative: "First sealed thought.",
            project: "Anima",
            agent: "test",
            provenance: "unit-test"
        )
        let id2 = try await service.storeMemory(
            narrative: "Second sealed thought.",
            project: "Anima",
            agent: "test",
            provenance: "unit-test"
        )

        let ledger = await service.currentLedger()
        #expect(ledger != nil)
        #expect(ledger?.blocks.count == 2)
        #expect(ledger?.blocks[0].id == id1)
        #expect(ledger?.blocks[1].id == id2)
        #expect(ledger?.blocks[0].contentHash == CaptureService.contentHash(for: "First sealed thought."))
        #expect(await service.latestSeal == ledger?.latestSeal)

        let verification = await service.verifySealChain()
        #expect(verification != nil)
        guard case .success = verification else {
            Issue.record("Seal chain should verify after two successful captures.")
            return
        }
    }

    @Test("🌙 store_memory succeeds without a ledger (seal optional)")
    func testStoreWithoutLedger() async throws {
        let (vault, service) = try await makeVaultAndService(withLedger: false)

        let memoryID = try await service.storeMemory(
            narrative: "Unsealed but durable capture.",
            project: "Anima",
            agent: "test",
            provenance: "unit-test"
        )

        #expect(try await vault.fetch(id: memoryID) != nil)
        #expect(await service.currentLedger() == nil)
        #expect(await service.latestSeal == nil)
        #expect(await service.verifySealChain() == nil)
    }

    @Test("🌩️ Empty narrative is rejected before any insert")
    func testEmptyNarrativeRejected() async throws {
        let (vault, service) = try await makeVaultAndService()

        await #expect(throws: CaptureServiceError.self) {
            try await service.storeMemory(
                narrative: "   \n\t  ",
                project: "Anima",
                agent: "test",
                provenance: "unit-test"
            )
        }
        #expect(try await vault.count() == 0)
    }

    @Test("🛡️ Duplicate narrative content_hash is rejected")
    func testDuplicateContentHashRejected() async throws {
        let service = try await makeCaptureService()
        let narrative = "The same thought twice is still one thought."

        _ = try await service.storeMemory(
            narrative: narrative,
            project: "Anima",
            agent: "test",
            provenance: "unit-test"
        )

        await #expect(throws: CaptureServiceError.self) {
            try await service.storeMemory(
                narrative: narrative,
                project: "Anima",
                agent: "test",
                provenance: "unit-test"
            )
        }
    }

    /// 🧪 Task #4 Proof Harness — DATA-CONTRACTS.md §12 store_memory hot path.
    ///
    /// Structural boundary: CaptureService imports Foundation + CryptoKit only at the
    /// service layer; it calls SwiftDataContainer.insert and optionally AnimaLedger.append.
    /// It does NOT construct CloudKitSyncEngine, QdrantIndexer, LadybugIndexer, or write
    /// Obsidian paths. After store, materializedPath remains nil.
    @Test("🧾 Task4 Proof Harness — hash, insert, seal, return ID; no cold-path side effects")
    func testTask4StoreMemoryProofHarness() async throws {
        let (vault, service) = try await makeVaultAndService(withLedger: true)
        let narrative = "Task 4 proof: transactional store_memory seals locally and returns."
        let provenance = "proof://anima-memory/task4/store-memory"
        let expectedHash = CaptureService.contentHash(for: narrative)

        let memoryID = try await service.storeMemory(
            narrative: narrative,
            project: "MemoryKit",
            agent: "cursor-proof",
            provenance: provenance,
            visibility: "private",
            tags: ["proof/task4", "store-memory"]
        )

        let roundTrip = try await vault.fetch(id: memoryID)
        #expect(roundTrip != nil)
        #expect(roundTrip?.contentHash == expectedHash)
        #expect(roundTrip?.visibility == "private")
        #expect(roundTrip?.provenance == provenance)
        #expect(roundTrip?.materializedPath == nil, "Cold Obsidian projection must not run on hot path")

        let byHash = try await vault.fetchByContentHash(expectedHash)
        #expect(byHash?.id == memoryID)

        let verification = await service.verifySealChain()
        guard case .success = verification else {
            Issue.record("AnimaSeal chain must verify after store_memory")
            return
        }
        #expect(await service.latestSeal != nil)
        #expect(await service.latestSeal != AnimaSeal.defaultGenesisPreviousSeal)
    }
}
