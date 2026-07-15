/**
 * 🎭 ObsidianMaterializerTests - The Dream-Scribe Quality Ritual
 *
 * "We conjure a fixture vault under /tmp moonlight, pour unmarked neurons
 * from the hot store, and prove the scribe writes §6 markdown, append-merges
 * kindly, stamps materializedPath, and never corrupts the café when the quill breaks."
 *
 * - The Spellbinding Museum Director of Testing
 */

import Foundation
import Testing
@testable import MemoryKit

@Suite("🔮 Obsidian Materializer Dream Rituals")
struct ObsidianMaterializerTests {

    // MARK: - Fixtures

    private func makeVaultRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("anima-materializer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeRecord(
        id: UUID = UUID(),
        hash: String,
        project: String = "multibrain",
        agent: String = "claude-code",
        narrative: String,
        visibility: String = "private",
        createdAt: Date = Date(timeIntervalSince1970: 1_720_137_600), // 2024-07-05 UTC
        tags: [String] = ["insight/discovery"]
    ) -> AnimaEpisodicRecordSnapshot {
        AnimaEpisodicRecordSnapshot(
            id: id,
            contentHash: hash,
            createdAt: createdAt,
            project: project,
            agent: agent,
            narrative: narrative,
            visibility: visibility,
            provenance: "test://obsidian-materializer",
            tags: tags,
            materializedPath: nil
        )
    }

    // MARK: - Tests

    @Test("📝 Materialize nil-path records into §6 markdown and stamp materializedPath")
    func testMaterializeWritesMarkdownAndStampsPath() async throws {
        let vault = try await SwiftDataContainer.createInMemory()
        let vaultRoot = try makeVaultRoot()
        defer { try? FileManager.default.removeItem(at: vaultRoot) }

        let record = makeRecord(
            hash: "sha256:mat-1",
            narrative: "Hot store must never wait on Obsidian IO."
        )
        try await vault.insert(record)

        let before = try await vault.fetch(id: record.id)
        #expect(before?.materializedPath == nil, "Insert must leave cold projection unset — café stays open! ☕")

        let materializer = ObsidianMaterializer(store: vault, vaultRoot: vaultRoot)
        let report = await materializer.materializePending()

        #expect(report.writtenCount == 1)
        #expect(report.failedCount == 0)

        let after = try await vault.fetch(id: record.id)
        let expectedRelative = "07-Sessions/2024-07-05--multibrain--claude-code.md"
        #expect(after?.materializedPath == expectedRelative)
        #expect(after?.narrative == record.narrative)
        #expect(after?.contentHash == record.contentHash)

        let noteURL = vaultRoot.appendingPathComponent(expectedRelative)
        let data = try Data(contentsOf: noteURL)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("type: session-learning"))
        #expect(text.contains("visibility: private"), "Frontmatter must carry the cloak tag! 🧥")
        #expect(text.contains("## Key Insights"))
        #expect(text.contains("Hot store must never wait on Obsidian IO."))
        #expect(text.contains(ObsidianMaterializer.contentHashMarker(for: "sha256:mat-1")))
    }

    @Test("🌿 Append-merge grafts new insights without wiping the existing note")
    func testAppendMergeDoesNotOverwrite() async throws {
        let vault = try await SwiftDataContainer.createInMemory()
        let vaultRoot = try makeVaultRoot()
        defer { try? FileManager.default.removeItem(at: vaultRoot) }

        let first = makeRecord(hash: "sha256:merge-a", narrative: "First insight from the morning pour.")
        let second = makeRecord(hash: "sha256:merge-b", narrative: "Second insight after the afternoon roast.")
        try await vault.insert(first)
        try await vault.insert(second)

        let materializer = ObsidianMaterializer(store: vault, vaultRoot: vaultRoot)
        let report1 = await materializer.materializePending()

        #expect(report1.writtenCount == 1)
        #expect(report1.mergedCount == 1)

        let relative = "07-Sessions/2024-07-05--multibrain--claude-code.md"
        let data = try Data(contentsOf: vaultRoot.appendingPathComponent(relative))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("First insight from the morning pour."))
        #expect(text.contains("Second insight after the afternoon roast."))
        #expect(text.contains("visibility:"))

        let a = try await vault.fetchByContentHash("sha256:merge-a")
        let b = try await vault.fetchByContentHash("sha256:merge-b")
        #expect(a?.materializedPath == relative)
        #expect(b?.materializedPath == relative)
    }

    @Test("🔁 Duplicate content_hash on re-run skips grafting and stays idempotent")
    func testDuplicateHashSkippedOnRerun() async throws {
        let vault = try await SwiftDataContainer.createInMemory()
        let vaultRoot = try makeVaultRoot()
        defer { try? FileManager.default.removeItem(at: vaultRoot) }

        let record = makeRecord(hash: "sha256:idem", narrative: "Only once, please.")
        try await vault.insert(record)

        let materializer = ObsidianMaterializer(store: vault, vaultRoot: vaultRoot)
        _ = await materializer.materializePending()

        let stamped = try #require(await vault.fetch(id: record.id))
        let unstamped = AnimaEpisodicRecordSnapshot(
            id: stamped.id,
            contentHash: stamped.contentHash,
            createdAt: stamped.createdAt,
            project: stamped.project,
            agent: stamped.agent,
            narrative: stamped.narrative,
            visibility: stamped.visibility,
            provenance: stamped.provenance,
            tags: stamped.tags,
            materializedPath: nil
        )
        try await vault.update(unstamped)

        let report = await materializer.materializePending()
        #expect(report.results.count == 1)
        #expect(report.results.first?.outcome == .skippedDuplicate)

        let data = try Data(
            contentsOf: vaultRoot.appendingPathComponent("07-Sessions/2024-07-05--multibrain--claude-code.md")
        )
        let text = String(decoding: data, as: UTF8.self)
        // Narrative also appears under ## What Changed — count the hash marker, not raw prose.
        let marker = ObsidianMaterializer.contentHashMarker(for: "sha256:idem")
        let markerOccurrences = text.components(separatedBy: marker).count - 1
        #expect(markerOccurrences == 1, "Append-merge must not duplicate the same content_hash bullet! 🪞")
    }

    @Test("🛡️ Vault write failure must not corrupt the hot store")
    func testWriteFailureLeavesHotStoreIntact() async throws {
        let vault = try await SwiftDataContainer.createInMemory()
        let vaultRoot = try makeVaultRoot()
        defer { try? FileManager.default.removeItem(at: vaultRoot) }

        let record = makeRecord(
            hash: "sha256:fail-open",
            narrative: "This neuron must survive a broken quill.",
            visibility: "friends"
        )
        try await vault.insert(record)

        let failingWriter = FailingVaultWriter(underlying: FileSystemVaultWriter())
        let materializer = ObsidianMaterializer(
            store: vault,
            vaultRoot: vaultRoot,
            writer: failingWriter
        )
        let report = await materializer.materializePending()

        #expect(report.failedCount == 1)
        #expect(report.writtenCount == 0)

        let after = try #require(await vault.fetch(id: record.id))
        #expect(after.materializedPath == nil, "Failed materialization must leave path nil")
        #expect(after.narrative == record.narrative)
        #expect(after.contentHash == record.contentHash)
        #expect(after.visibility == "friends")
        #expect(after.project == record.project)
        #expect(try await vault.count() == 1)
    }

    @Test("☕ Hot insert stays non-blocking — materializedPath nil until dream pass")
    func testStorePathNeverInvokesMaterializer() async throws {
        let vault = try await SwiftDataContainer.createInMemory()
        let record = makeRecord(hash: "sha256:hot-only", narrative: "Café order accepted.")
        try await vault.insert(record)

        let fetched = try #require(await vault.fetchByContentHash("sha256:hot-only"))
        #expect(fetched.materializedPath == nil)
        #expect(try await vault.count() == 1)
    }

    @Test("🧥 Frontmatter visibility + §6 required keys are present in rendered note")
    func testRenderedFrontmatterContract() async throws {
        let vault = try await SwiftDataContainer.createInMemory()
        let vaultRoot = try makeVaultRoot()
        defer { try? FileManager.default.removeItem(at: vaultRoot) }

        let record = makeRecord(
            hash: "sha256:frontmatter",
            narrative: "Visibility belongs in YAML.",
            visibility: "internal",
            tags: ["concept/gotcha"]
        )
        try await vault.insert(record)

        let materializer = ObsidianMaterializer(store: vault, vaultRoot: vaultRoot)
        let note = await materializer.renderSessionNote(for: record)

        for key in [
            "type: session-learning",
            "created:",
            "date:",
            "agent:",
            "project:",
            "tags:",
            "visibility: internal",
            "confidence:"
        ] {
            #expect(note.contains(key), "Missing §6/Anima frontmatter key fragment: \(key)")
        }
        for section in [
            "## Key Insights",
            "## What Changed",
            "## Problem → Solution",
            "## Files Touched",
            "## Connections"
        ] {
            #expect(note.contains(section), "Missing body section: \(section)")
        }
    }

    @Test("🧹 Already-materialized records are ignored on subsequent dream passes")
    func testSkipsAlreadyMaterialized() async throws {
        let vault = try await SwiftDataContainer.createInMemory()
        let vaultRoot = try makeVaultRoot()
        defer { try? FileManager.default.removeItem(at: vaultRoot) }

        let done = AnimaEpisodicRecordSnapshot(
            id: UUID(),
            contentHash: "sha256:already",
            createdAt: Date(timeIntervalSince1970: 1_720_137_600),
            project: "multibrain",
            agent: "codex",
            narrative: "Already projected.",
            visibility: "public",
            provenance: "test",
            tags: [],
            materializedPath: "07-Sessions/2024-07-05--multibrain--codex.md"
        )
        let pending = makeRecord(
            hash: "sha256:still-pending",
            project: "multibrain",
            agent: "codex",
            narrative: "Needs ink."
        )
        try await vault.insert(done)
        try await vault.insert(pending)

        let materializer = ObsidianMaterializer(store: vault, vaultRoot: vaultRoot)
        let report = await materializer.materializePending()

        #expect(report.results.count == 1)
        #expect(report.results.first?.contentHash == "sha256:still-pending")
        #expect(report.writtenCount == 1)
    }
}

// MARK: - Test Doubles

/// 🌩️ A quill that always snaps on write — proves fail-open vs the hot store
private struct FailingVaultWriter: VaultFileWriting {
    let underlying: FileSystemVaultWriter

    func fileExists(at url: URL) -> Bool { underlying.fileExists(at: url) }
    func createDirectoryIfNeeded(at url: URL) throws { try underlying.createDirectoryIfNeeded(at: url) }
    func readUTF8(from url: URL) throws -> String { try underlying.readUTF8(from: url) }
    func writeUTF8(_ contents: String, to url: URL) throws {
        throw ObsidianMaterializationError.writeFailed("intentional test quill snap 💥")
    }
}
