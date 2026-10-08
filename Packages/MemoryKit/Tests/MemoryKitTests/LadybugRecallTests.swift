/**
 * 🔮 LadybugRecallTests — the §13 semantic-probe lane of `recall_memory`
 *
 * "A neighbour whispered across the wire is still a neighbour — unless the
 * hot ledger already knows them by name, the seeker's filter bars their
 * project at the door, in which case the whisper bows out."
 *
 * - The Polite Protocol of Duplicated Recollections
 *
 * Covers: merged ranking, hot-wins dedup (contentHash + normalized path),
 * structured-filter pruning, fail-open degradation flags (incl. malformed
 * payloads), includeSemanticFallback gating, and payload parsing.
 * The real HTTP client's network behaviour is exercised by the Python-side
 * E2E (bin/index_ladybug.py --serve battery); here the probe is mocked.
 */

import Testing
import Foundation
@testable import MemoryKit

// MARK: - Mocks

/// 🎭 Scripted Ladybug probe — returns canned outcomes per needle.
actor MockLadybugSearch: LadybugVectorSearching {
    struct Call: Equatable { let text: String; let k: Int }
    private(set) var calls: [Call] = []

    private let outcome: LadybugSearchOutcome

    /// 🌟 Prime the mock with the outcome every probe shall return.
    init(outcome: LadybugSearchOutcome) {
        self.outcome = outcome
    }

    func search(text: String, k: Int) async -> LadybugSearchOutcome {
        calls.append(Call(text: text, k: k))
        return outcome
    }

    /// 🔎 Awaitable call log for assertions in async tests.
    func callLog() -> [Call] { calls }
}

// MARK: - Hit shaping

@Test("semantic hits merge into recall with source tag and thin narrative")
func semanticHitsMergeIntoRecall() async throws {
    let mock = MockLadybugSearch(outcome: LadybugSearchOutcome(hits: [
        LadybugSearchHit(
            pointID: "pid-1",
            contentHash: "sha256:cache-only",
            visibility: "internal",
            project: "multibrain",
            path: "07-Sessions/2026-10-08--ladybug--merge.md",
            title: "merge.md",
            date: "2026-10-08",
            tags: ["wal", "checkpoint"],
            table: "cache",
            distance: 0.12
        )
    ], degraded: false))

    let service = RetrievalService(
        container: try SwiftDataContainer.createInMemory(),
        vaultURL: nil,
        ladybugSearch: mock
    )

    let result = try await service.recallMemory(RecallQuery(text: "graceful shutdown checkpoint WAL"))
    #expect(result.semanticHitCount == 1)
    #expect(result.semanticDegraded == false)

    let semanticHits = result.hits.filter { $0.source == .semantic }
    #expect(semanticHits.count == 1)
    let hit = try #require(semanticHits.first)
    #expect(hit.contentHash == "sha256:cache-only")
    #expect(hit.visibility == "internal")
    #expect(hit.project == "multibrain")
    #expect(hit.tags == ["wal", "checkpoint"])
    #expect(hit.path == "07-Sessions/2026-10-08--ladybug--merge.md")
    #expect(hit.narrative.contains("merge.md"))
    // distance 0.12 → score 1 + (2-0.12)*2 = 4.76
    #expect(abs(hit.score - 4.76) < 0.001)
    // §13 date carried through as createdAt
    let comps = Calendar(identifier: .gregorian).dateComponents(
        in: TimeZone(identifier: "UTC")!, from: hit.createdAt ?? .distantPast)
    #expect(comps.year == 2026 && comps.month == 10 && comps.day == 8)
}

@Test("hot store wins identity collisions against semantic cache hits")
func hotWinsOverSemantic() async throws {
    let container = try SwiftDataContainer.createInMemory()
    let narrative = "the hot copy of a dreamt insight"
    let hotHash = CaptureService.contentHash(for: narrative)
    try await CaptureService(container: container).storeMemory(
        narrative: narrative,
        project: "multibrain",
        agent: "berserker",
        provenance: "test"
    )

    let mock = MockLadybugSearch(outcome: LadybugSearchOutcome(hits: [
        LadybugSearchHit(contentHash: hotHash, path: nil,
                         title: "stale echo", distance: 0.01),
        LadybugSearchHit(contentHash: "sha256:path-collision",
                         path: "07-Sessions/hot-path.md",
                         title: "path echo", distance: 0.02)
    ], degraded: false))

    let service = RetrievalService(
        container: container,
        vaultURL: nil,
        ladybugSearch: mock
    )
    let result = try await service.recallMemory(RecallQuery(text: "dreamt insight"))
    // hash collision deduped; path-collision hit survives (hot path differs)
    let semanticHits = result.hits.filter { $0.source == .semantic }
    #expect(semanticHits.count == 1)
    #expect(semanticHits.first?.contentHash == "sha256:path-collision")
    #expect(result.hits.filter { $0.source == .hotStore }.count == 1)
}

@Test("structured filters prune out-of-scope semantic hits")
func structuredFiltersPruneSemanticHits() async throws {
    let mock = MockLadybugSearch(outcome: LadybugSearchOutcome(hits: [
        // wrong project — pruned
        LadybugSearchHit(contentHash: "sha256:p1", visibility: "public",
                         project: "andromeda", title: "wrong project",
                         date: "2026-10-08", tags: ["wal"], distance: 0.05),
        // wrong visibility — pruned
        LadybugSearchHit(contentHash: "sha256:p2", visibility: "internal",
                         project: "multibrain", title: "wrong visibility",
                         date: "2026-10-08", tags: ["wal"], distance: 0.06),
        // missing required tag — pruned
        LadybugSearchHit(contentHash: "sha256:p3", visibility: "public",
                         project: "multibrain", title: "missing tag",
                         date: "2026-10-08", tags: ["checkpoint"], distance: 0.07),
        // outside date range — pruned
        LadybugSearchHit(contentHash: "sha256:p4", visibility: "public",
                         project: "multibrain", title: "too old",
                         date: "2020-01-01", tags: ["wal"], distance: 0.08),
        // in scope on every dimension — survives
        LadybugSearchHit(contentHash: "sha256:p5", visibility: "public",
                         project: "multibrain", title: "keeper",
                         date: "2026-10-08", tags: ["wal", "checkpoint"], distance: 0.09)
    ], degraded: false))

    let service = RetrievalService(
        container: try SwiftDataContainer.createInMemory(),
        vaultURL: nil,
        ladybugSearch: mock
    )
    let result = try await service.recallMemory(RecallQuery(
        text: "needle", tags: ["wal"], project: "multibrain", visibility: "public",
        dateFrom: Date(timeIntervalSince1970: 1_782_000_000)))
    #expect(result.semanticHitCount == 1)
    let keeper = try #require(result.hits.filter { $0.source == .semantic }.first)
    #expect(keeper.contentHash == "sha256:p5")
}

@Test("dark ladybug server degrades recall, never fails it")
func semanticFailOpen() async throws {
    let mock = MockLadybugSearch(outcome: LadybugSearchOutcome(
        hits: [], degraded: true, reason: "ladybug unreachable: connection refused"))
    let service = RetrievalService(
        container: try SwiftDataContainer.createInMemory(),
        vaultURL: nil,
        ladybugSearch: mock
    )
    let result = try await service.recallMemory(RecallQuery(text: "anything"))
    #expect(result.semanticDegraded == true)
    #expect(result.semanticDegradationReason?.contains("unreachable") == true)
    #expect(result.semanticHitCount == 0)
    #expect(result.hits.filter { $0.source == .semantic }.isEmpty)
}

@Test("includeSemanticFallback=false skips the probe entirely")
func semanticGating() async throws {
    let mock = MockLadybugSearch(outcome: LadybugSearchOutcome(
        hits: [LadybugSearchHit(title: "never", distance: 0.0)], degraded: false))
    let service = RetrievalService(
        container: try SwiftDataContainer.createInMemory(),
        vaultURL: nil,
        ladybugSearch: mock
    )
    _ = try await service.recallMemory(RecallQuery(
        text: "needle", includeSemanticFallback: false))
    #expect(await mock.callLog().isEmpty)
}

@Test("no text needle means no semantic probe (tags-only query)")
func semanticSkippedWithoutText() async throws {
    let mock = MockLadybugSearch(outcome: LadybugSearchOutcome(
        hits: [LadybugSearchHit(title: "never", distance: 0.0)], degraded: false))
    let service = RetrievalService(
        container: try SwiftDataContainer.createInMemory(),
        vaultURL: nil,
        ladybugSearch: mock
    )
    _ = try await service.recallMemory(RecallQuery(tags: ["wal"]))
    #expect(await mock.callLog().isEmpty)
}

@Test("bare-array /query payloads parse with uniform + thin keys; malformed bodies are nil")
func queryPayloadParsing() {
    let json = """
    [
      {"id": 41, "path": "07-Sessions/note.md", "project": "multibrain",
       "agent": "berserker", "title": "note", "distance": 0.42, "table": "note"},
      {"point_id": "pid-9", "content_hash": "sha256:abc", "visibility": "private",
       "project": "andromeda", "date": "2026-10-08", "tags": ["hud"],
       "source_path": "07-Sessions/cache.md", "distance": 0.05, "table": "cache"}
    ]
    """
    let hits = LadybugVectorSearch.parseHits(Data(json.utf8))
    #expect(hits != nil)
    let parsed = try! #require(hits)
    #expect(parsed.count == 2)
    #expect(parsed[0].path == "07-Sessions/note.md")
    #expect(parsed[0].table == "note")
    #expect(parsed[0].pointID == nil)
    #expect(parsed[1].pointID == "pid-9")
    #expect(parsed[1].contentHash == "sha256:abc")
    #expect(parsed[1].visibility == "private")
    #expect(parsed[1].tags == ["hud"])
    #expect(parsed[1].path == "07-Sessions/cache.md")

    // malformed payloads are nil (degraded), never a crash, never a fake empty index
    #expect(LadybugVectorSearch.parseHits(Data("not json".utf8)) == nil)
    #expect(LadybugVectorSearch.parseHits(Data("{\"hits\": []}".utf8)) == nil)
    // rows without distance are noise, not failure
    let noisy = LadybugVectorSearch.parseHits(Data("[{\"title\": \"no distance\"}]".utf8))
    #expect(noisy != nil)
    #expect(try! #require(noisy).isEmpty)

    // healthy empty index stays non-degraded
    let empty = LadybugVectorSearch.parseHits(Data("[]".utf8))
    #expect(empty != nil)
    #expect(try! #require(empty).isEmpty)
}

@Test("absolute vault paths and relative source_paths dedupe across stages")
func vaultPathNormalizationDedup() async throws {
    let mock = MockLadybugSearch(outcome: LadybugSearchOutcome(hits: [
        LadybugSearchHit(contentHash: nil,
                         path: "07-Sessions/dup.md",
                         title: "dup.md", distance: 0.03)
    ], degraded: false))
    let service = RetrievalService(
        container: try SwiftDataContainer.createInMemory(),
        vaultURL: URL(fileURLWithPath: "/tmp/vault-fixture"),
        processRunner: MockProcessRunner(result: ProcessRunResult(
            exitCode: 0,
            stdout: """
            {"type":"match","data":{"path":{"text":"/tmp/vault-fixture/07-Sessions/dup.md"},"lines":{"text":"the duplicated line"}}}
            """,
            stderr: "")),
        ladybugSearch: mock
    )
    let result = try await service.recallMemory(RecallQuery(
        text: "duplicated", limit: 10, includeVaultFallback: true))
    // Same note from ripgrep (absolute) and the index (relative): one survivor.
    let dupSources = result.hits.filter { $0.path?.contains("dup.md") == true }
    #expect(dupSources.count == 1)
}
