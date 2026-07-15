/**
 * 🎭 RetrievalServiceTests - The Recall Memory Quality Ritual
 *
 * "We light the hot-store lantern first, then mock ripgrep's foghorn —
 * proving the librarian never needs Qdrant's constellation to answer."
 *
 * - The Spellbinding Museum Director of Testing
 */

import Testing
@testable import MemoryKit
import Foundation

// MARK: - Mock Process Runner

/// 🧪 MockProcessRunner — records invocations and returns scripted ripgrep theatre.
actor MockProcessRunner: ProcessRunning {
    struct Invocation: Sendable, Equatable {
        let executable: String
        let arguments: [String]
        let workingDirectory: URL?
    }

    private(set) var invocations: [Invocation] = []
    var result: ProcessRunResult
    var errorToThrow: (any Error)?

    init(
        result: ProcessRunResult = ProcessRunResult(exitCode: 1, stdout: "", stderr: ""),
        errorToThrow: (any Error)? = nil
    ) {
        self.result = result
        self.errorToThrow = errorToThrow
    }

    func setResult(_ result: ProcessRunResult) {
        self.result = result
    }

    func setError(_ error: (any Error)?) {
        self.errorToThrow = error
    }

    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?
    ) async throws -> ProcessRunResult {
        invocations.append(
            Invocation(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
        )
        if let errorToThrow {
            throw errorToThrow
        }
        return result
    }

    func invocationCount() -> Int {
        invocations.count
    }

    func lastInvocation() -> Invocation? {
        invocations.last
    }
}

private enum MockRunnerError: Error {
    case boom
}

// MARK: - Suite

@Suite("🔍 The Recall Memory Retrieval Rituals")
struct RetrievalServiceTests {

    // 🌟 Fresh in-memory vault for each rite
    private func makeVault() throws -> SwiftDataContainer {
        try SwiftDataContainer.createInMemory()
    }

    private func seed(
        _ vault: SwiftDataContainer,
        narrative: String,
        project: String = "Anima",
        visibility: String = "private",
        tags: [String] = [],
        createdAt: Date = Date(),
        contentHash: String? = nil
    ) async throws -> AnimaEpisodicRecordSnapshot {
        let snapshot = AnimaEpisodicRecordSnapshot(
            id: UUID(),
            contentHash: contentHash ?? "sha256:\(UUID().uuidString)",
            createdAt: createdAt,
            project: project,
            agent: "cursor-proof",
            narrative: narrative,
            visibility: visibility,
            provenance: "proof://anima-memory/task6/recall-memory",
            tags: tags
        )
        try await vault.insert(snapshot)
        return snapshot
    }

    // MARK: - Hot store filters

    @Test("📥 Hot store filters by project, visibility, tags, and date range")
    func testHotStoreStructuredFilters() async throws {
        let vault = try makeVault()
        let calendar = Calendar.current
        let older = calendar.date(byAdding: .day, value: -10, to: Date())!
        let newer = calendar.date(byAdding: .day, value: -1, to: Date())!

        _ = try await seed(
            vault,
            narrative: "Old private note about cafes",
            project: "Anima",
            visibility: "private",
            tags: ["cafe", "insight"],
            createdAt: older,
            contentHash: "sha256:old"
        )
        let match = try await seed(
            vault,
            narrative: "Fresh public note about cafes and pour-overs",
            project: "Anima",
            visibility: "public",
            tags: ["cafe", "pour-over"],
            createdAt: newer,
            contentHash: "sha256:new"
        )
        _ = try await seed(
            vault,
            narrative: "Wrong project entirely",
            project: "Other",
            visibility: "public",
            tags: ["cafe"],
            createdAt: newer,
            contentHash: "sha256:other"
        )

        let runner = MockProcessRunner()
        let retrieval = RetrievalService(
            container: vault,
            vaultURL: nil,
            processRunner: runner
        )

        let result = try await retrieval.recallMemory(
            RecallQuery(
                text: "cafes",
                tags: ["cafe"],
                project: "Anima",
                visibility: "public",
                dateFrom: calendar.date(byAdding: .day, value: -3, to: Date())!,
                dateTo: Date(),
                limit: 10,
                includeVaultFallback: false
            )
        )

        #expect(result.hits.count == 1)
        #expect(result.hits.first?.memoryID == match.id)
        #expect(result.hits.first?.source == .hotStore)
        #expect(result.hotHitCount == 1)
        #expect(result.vaultHitCount == 0)
        #expect(await runner.invocationCount() == 0)
    }

    @Test("🏷️ Tag filter requires all listed tags on hot records")
    func testTagConjunctionFilter() async throws {
        let vault = try makeVault()
        _ = try await seed(
            vault,
            narrative: "Only cafe tag",
            tags: ["cafe"],
            contentHash: "sha256:cafe-only"
        )
        let both = try await seed(
            vault,
            narrative: "Cafe and insight together",
            tags: ["cafe", "insight"],
            contentHash: "sha256:both"
        )

        let retrieval = RetrievalService(
            container: vault,
            vaultURL: nil,
            processRunner: MockProcessRunner()
        )

        let result = try await retrieval.recallMemory(
            RecallQuery(tags: ["cafe", "insight"], includeVaultFallback: false)
        )

        #expect(result.hits.count == 1)
        #expect(result.hits.first?.memoryID == both.id)
    }

    @Test("📅 Date range excludes out-of-window hot records")
    func testDateRangeFilter() async throws {
        let vault = try makeVault()
        let calendar = Calendar.current
        let inside = calendar.date(byAdding: .day, value: -2, to: Date())!
        let outside = calendar.date(byAdding: .day, value: -30, to: Date())!

        _ = try await seed(
            vault,
            narrative: "Ancient wisdom",
            createdAt: outside,
            contentHash: "sha256:ancient"
        )
        let recent = try await seed(
            vault,
            narrative: "Recent wisdom",
            createdAt: inside,
            contentHash: "sha256:recent"
        )

        let retrieval = RetrievalService(
            container: vault,
            processRunner: MockProcessRunner()
        )

        let result = try await retrieval.recallMemory(
            RecallQuery(
                text: "wisdom",
                dateFrom: calendar.date(byAdding: .day, value: -7, to: Date())!,
                includeVaultFallback: false
            )
        )

        #expect(result.hits.count == 1)
        #expect(result.hits.first?.memoryID == recent.id)
    }

    // MARK: - Vault fallback

    @Test("📜 Vault ripgrep fallback merges mock rg JSON when hot hits are thin")
    func testVaultRipgrepFallbackMergesHits() async throws {
        let vault = try makeVault()
        _ = try await seed(
            vault,
            narrative: "Only one hot hit about alchemy",
            contentHash: "sha256:hot-alchemy"
        )

        let fixtureVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("anima-recall-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureVault, withIntermediateDirectories: true)

        let rgJSON = """
        {"type":"match","data":{"path":{"text":"\(fixtureVault.path)/07-Sessions/note.md"},"lines":{"text":"Vault lore about alchemy and pour-overs\\n"},"line_number":3}}
        """
        let runner = MockProcessRunner(
            result: ProcessRunResult(exitCode: 0, stdout: rgJSON, stderr: "")
        )

        let retrieval = RetrievalService(
            container: vault,
            vaultURL: fixtureVault,
            processRunner: runner,
            ripgrepExecutable: "/usr/bin/rg"
        )

        let result = try await retrieval.recallMemory(
            RecallQuery(text: "alchemy", limit: 10, includeVaultFallback: true)
        )

        #expect(result.hotHitCount == 1)
        #expect(result.vaultHitCount == 1)
        #expect(result.vaultDegraded == false)
        #expect(result.hits.count == 2)
        #expect(result.hits.contains { $0.source == .vault })
        #expect(result.hits.contains { $0.source == .hotStore })

        let invocation = await runner.lastInvocation()
        #expect(invocation != nil)
        #expect(invocation?.executable == "/usr/bin/rg")
        #expect(invocation?.arguments.contains("--json") == true)
        #expect(invocation?.arguments.contains("alchemy") == true)

        try? FileManager.default.removeItem(at: fixtureVault)
    }

    @Test("🌊 Missing vault degrades gracefully without failing recall")
    func testMissingVaultDegrades() async throws {
        let vault = try makeVault()
        _ = try await seed(
            vault,
            narrative: "Hot store still answers when vault ghosts away",
            contentHash: "sha256:ghost"
        )

        let missingVault = URL(fileURLWithPath: "/tmp/anima-does-not-exist-\(UUID().uuidString)")
        let runner = MockProcessRunner()
        let retrieval = RetrievalService(
            container: vault,
            vaultURL: missingVault,
            processRunner: runner
        )

        let result = try await retrieval.recallMemory(
            RecallQuery(text: "ghosts", includeVaultFallback: true)
        )

        #expect(result.hits.count == 1)
        #expect(result.hits.first?.source == .hotStore)
        #expect(result.vaultDegraded == true)
        #expect(result.degradationReason?.contains("vault missing") == true)
        #expect(await runner.invocationCount() == 0)
    }

    @Test("🌊 Nil vault URL degrades without invoking process runner")
    func testNilVaultURLDegrades() async throws {
        let vault = try makeVault()
        _ = try await seed(vault, narrative: "Lantern without fog", contentHash: "sha256:fog")

        let runner = MockProcessRunner()
        let retrieval = RetrievalService(
            container: vault,
            vaultURL: nil,
            processRunner: runner
        )

        let result = try await retrieval.recallMemory(
            RecallQuery(text: "Lantern", includeVaultFallback: true)
        )

        #expect(result.hits.count >= 1)
        #expect(result.vaultDegraded == true)
        #expect(result.degradationReason == "vault URL not configured")
        #expect(await runner.invocationCount() == 0)
    }

    @Test("🌊 Ripgrep runner failure degrades and still returns hot hits")
    func testRipgrepFailureDegrades() async throws {
        let vault = try makeVault()
        _ = try await seed(vault, narrative: "Survives the storm", contentHash: "sha256:storm")

        let fixtureVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("anima-recall-vault-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureVault, withIntermediateDirectories: true)

        let runner = MockProcessRunner(errorToThrow: MockRunnerError.boom)
        let retrieval = RetrievalService(
            container: vault,
            vaultURL: fixtureVault,
            processRunner: runner
        )

        let result = try await retrieval.recallMemory(
            RecallQuery(text: "Survives", includeVaultFallback: true)
        )

        #expect(result.hits.count == 1)
        #expect(result.hits.first?.source == .hotStore)
        #expect(result.vaultDegraded == true)
        #expect(result.degradationReason?.contains("ripgrep runner failed") == true)
        #expect(await runner.invocationCount() == 1)

        try? FileManager.default.removeItem(at: fixtureVault)
    }

    @Test("🌙 includeVaultFallback=false never calls the process runner")
    func testVaultFallbackOptOut() async throws {
        let vault = try makeVault()
        _ = try await seed(vault, narrative: "Stay local", contentHash: "sha256:local")

        let fixtureVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("anima-recall-optout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureVault, withIntermediateDirectories: true)

        let runner = MockProcessRunner(
            result: ProcessRunResult(
                exitCode: 0,
                stdout: #"{"type":"match","data":{"path":{"text":"x.md"},"lines":{"text":"should not appear"}}}"#,
                stderr: ""
            )
        )
        let retrieval = RetrievalService(
            container: vault,
            vaultURL: fixtureVault,
            processRunner: runner
        )

        let result = try await retrieval.recallMemory(
            RecallQuery(text: "local", includeVaultFallback: false)
        )

        #expect(result.hits.allSatisfy { $0.source == .hotStore })
        #expect(await runner.invocationCount() == 0)

        try? FileManager.default.removeItem(at: fixtureVault)
    }

    // MARK: - Contract invariants

    @Test("🚫 Empty query throws — lantern refuses the void")
    func testEmptyQueryThrows() async throws {
        let vault = try makeVault()
        let retrieval = RetrievalService(container: vault, processRunner: MockProcessRunner())

        await #expect(throws: RetrievalServiceError.self) {
            try await retrieval.recallMemory(RecallQuery())
        }
    }

    @Test("🧾 Task6 proof harness — hot filters + vault degrade; no Qdrant/Ladybug required")
    func testTask6RecallMemoryProofHarness() async throws {
        let vault = try makeVault()
        let calendar = Calendar.current

        let kept = try await seed(
            vault,
            narrative: "Task 6 proof: recall from hot store without vector backends.",
            project: "MemoryKit",
            visibility: "private",
            tags: ["proof/task6", "recall"],
            createdAt: calendar.date(byAdding: .hour, value: -1, to: Date())!,
            contentHash: "sha256:task6-proof-recall"
        )
        _ = try await seed(
            vault,
            narrative: "Distractor in another project",
            project: "Distractor",
            visibility: "public",
            tags: ["proof/task6"],
            contentHash: "sha256:task6-distractor"
        )

        let runner = MockProcessRunner()
        let retrieval = RetrievalService(
            container: vault,
            vaultURL: URL(fileURLWithPath: "/tmp/anima-task6-missing-vault"),
            processRunner: runner
        )

        let result = try await retrieval.recallMemory(
            RecallQuery(
                text: "Task 6 proof",
                tags: ["proof/task6", "recall"],
                project: "MemoryKit",
                visibility: "private",
                limit: 5,
                includeVaultFallback: true
            )
        )

        #expect(result.hits.count == 1)
        #expect(result.hits.first?.memoryID == kept.id)
        #expect(result.hits.first?.contentHash == "sha256:task6-proof-recall")
        #expect(result.hits.first?.visibility == "private")
        #expect(result.vaultDegraded == true)
        #expect(result.degradationReason?.contains("vault missing") == true)
        // 🌙 Process runner never contacted for missing vault — success without Qdrant/Ladybug.
        #expect(await runner.invocationCount() == 0)
    }

    @Test("🏆 Hot hits rank above vault hits with comparable text")
    func testHotRanksAboveVault() async throws {
        let vault = try makeVault()
        _ = try await seed(
            vault,
            narrative: "Shared keyword ranking duel",
            contentHash: "sha256:rank-hot"
        )

        let fixtureVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("anima-recall-rank-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureVault, withIntermediateDirectories: true)

        let rgJSON = """
        {"type":"match","data":{"path":{"text":"\(fixtureVault.path)/note.md"},"lines":{"text":"Shared keyword ranking duel from vault\\n"}}}
        """
        let runner = MockProcessRunner(
            result: ProcessRunResult(exitCode: 0, stdout: rgJSON, stderr: "")
        )
        let retrieval = RetrievalService(
            container: vault,
            vaultURL: fixtureVault,
            processRunner: runner
        )

        let result = try await retrieval.recallMemory(
            RecallQuery(text: "ranking duel", limit: 5, includeVaultFallback: true)
        )

        #expect(result.hits.count == 2)
        #expect(result.hits.first?.source == .hotStore)

        try? FileManager.default.removeItem(at: fixtureVault)
    }
}
