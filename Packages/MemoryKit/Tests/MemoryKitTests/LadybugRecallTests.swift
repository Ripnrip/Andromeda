/**
 * 🐞 LadybugRecallTests — the §13 semantic-probe lane of `recall_memory`
 *
 * "A neighbour whispered across the wire is still a neighbour — unless the
 * hot ledger already knows them by name, in which case the whisper bows out."
 *
 * - The Polite Protocol of Duplicated Recollections
 *
 * Covers: merged ranking, hot-wins dedup (contentHash + path), fail-open
 * degradation flags, includeLadybugFallback gating, and payload parsing.
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

@Test("ladybug hits merge into recall with source tag and thin narrative")
func ladybugHitsMergeIntoRecall() async throws {
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
    #expect(result.ladybugHitCount == 1)
    #expect(result.ladybugDegraded == false)

    let ladybugHits = result.hits.filter { $0.source == .ladybug }
    #expect(ladybugHits.count == 1)
    let hit = try #require(ladybugHits.first)
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

@Test("hot store wins identity collisions against ladybug cache hits")
func hotWinsOverLadybug() async throws {
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
    let ladybugHits = result.hits.filter { $0.source == .ladybug }
    #expect(ladybugHits.count == 1)
    #expect(ladybugHits.first?.contentHash == "sha256:path-collision")
    #expect(result.hits.filter { $0.source == .hotStore }.count == 1)
}

@Test("dark ladybug server degrades recall, never fails it")
func ladybugFailOpen() async throws {
    let mock = MockLadybugSearch(outcome: LadybugSearchOutcome(
        hits: [], degraded: true, reason: "ladybug unreachable: connection refused"))
    let service = RetrievalService(
        container: try SwiftDataContainer.createInMemory(),
        vaultURL: nil,
        ladybugSearch: mock
    )
    let result = try await service.recallMemory(RecallQuery(text: "anything"))
    #expect(result.ladybugDegraded == true)
    #expect(result.ladybugDegradationReason?.contains("unreachable") == true)
    #expect(result.ladybugHitCount == 0)
    #expect(result.hits.filter { $0.source == .ladybug }.isEmpty)
}

@Test("includeLadybugFallback=false skips the probe entirely")
func ladybugGating() async throws {
    let mock = MockLadybugSearch(outcome: LadybugSearchOutcome(
        hits: [LadybugSearchHit(title: "never", distance: 0.0)], degraded: false))
    let service = RetrievalService(
        container: try SwiftDataContainer.createInMemory(),
        vaultURL: nil,
        ladybugSearch: mock
    )
    _ = try await service.recallMemory(RecallQuery(
        text: "needle", includeLadybugFallback: false))
    #expect(await mock.callLog().isEmpty)
}

@Test("no text needle means no ladybug probe (tags-only query)")
func ladybugSkippedWithoutText() async throws {
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

@Test("bare-array /query payloads parse with uniform + thin keys")
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
    #expect(hits.count == 2)
    #expect(hits[0].path == "07-Sessions/note.md")
    #expect(hits[0].table == "note")
    #expect(hits[0].pointID == nil)
    #expect(hits[1].pointID == "pid-9")
    #expect(hits[1].contentHash == "sha256:abc")
    #expect(hits[1].visibility == "private")
    #expect(hits[1].tags == ["hud"])
    #expect(hits[1].path == "07-Sessions/cache.md")

    // malformed payloads yield zero hits, never a crash
    #expect(LadybugVectorSearch.parseHits(Data("not json".utf8)).isEmpty)
    #expect(LadybugVectorSearch.parseHits(Data("[{\"title\": \"no distance\"}]".utf8)).isEmpty)
}
