/**
 * Andromida complexity curtain tests (BIN-246–251).
 *
 * Covers verb surface, JSON outbox authority, fail-open live projection,
 * fused recall + tombstones, and health/drift/replay.
 */

import Foundation
import Testing
@testable import MemoryKit

@Suite("MemoryVerbSurface")
struct MemoryVerbSurfaceTests {
    @Test("Canonical underscore verbs resolve hot-path")
    func canonicalVerbs() {
        #expect(MemoryVerbSurface.resolve("memory_recall") == .canonical(.recall))
        #expect(MemoryVerbSurface.resolve("memory_retain") == .canonical(.retain))
        #expect(MemoryVerbSurface.resolve("memory_forget") == .canonical(.forget))
        #expect(MemoryVerbSurface.resolve("memory_health") == .canonical(.health))
        #expect(MemoryVerbSurface.isCanonicalHotPath("memory_retain"))
    }

    @Test("Legacy aliases remain compatibility shims")
    func shims() {
        guard case .compatibilityShim(.retain, let alias, let hot)? = MemoryVerbSurface.resolve("memory.store") else {
            Issue.record("Expected store shim")
            return
        }
        #expect(alias == "memory.store")
        #expect(hot)

        guard case .compatibilityShim(.retain, _, let journalHot)? = MemoryVerbSurface.resolve("memory.journal") else {
            Issue.record("Expected journal shim")
            return
        }
        #expect(!journalHot)
        #expect(CurtainWriteKindResolver.resolve(capabilityAlias: "infer.write") == .inferAliasDeprecated)
        #expect(CurtainWriteKindResolver.resolve(capabilityAlias: "session dump") == .sessionDump)
    }
}

@Suite("JSONOutboxAuthority")
struct JSONOutboxAuthorityTests {
    @Test("Retain is durable before any backend delivery")
    func retainDurable() async throws {
        let outbox = try JSONOutboxAuthority.makeTemporary()
        let record = try await outbox.retain(
            narrative: "cloak router restored",
            project: "andromeda",
            agent: "test",
            provenance: "memory_retain"
        )
        #expect(record.deliveryState == .pending)
        #expect(record.contentHash.hasPrefix("sha256:"))
        let all = await outbox.allRecords()
        #expect(all.count == 1)
        #expect(FileManager.default.fileExists(atPath: outbox.seedsURL.path))
    }

    @Test("Replay marks delivered without losing seeds")
    func markDeliveredKeepsSeed() async throws {
        let outbox = try JSONOutboxAuthority.makeTemporary()
        let record = try await outbox.retain(
            narrative: "durable fact",
            project: "p",
            agent: "a",
            provenance: "t"
        )
        try await outbox.mark(record.id, state: .delivered)
        let refreshed = await outbox.allRecords()
        #expect(refreshed.count == 1)
        #expect(refreshed[0].deliveryState == .delivered)
    }
}

@Suite("RealmOutboxLiveProjection")
struct RealmOutboxLiveProjectionTests {
    @Test("Fail-open never blocks retain when projection is down")
    func failOpen() async throws {
        let outbox = try JSONOutboxAuthority.makeTemporary()
        let projection = RealmOutboxLiveProjection()
        await projection.setForceFailOpen(true)
        let curtain = MemoryComplexityCurtain(outbox: outbox, projection: projection)
        let receipt = try await curtain.retain(
            narrative: "still durable",
            project: "p",
            agent: "a"
        )
        #expect(!receipt.memoryID.uuidString.isEmpty)
        #expect(receipt.warnings.contains(where: { $0.contains("fail-open") }))
        let authorityCount = await outbox.allRecords().count
        #expect(authorityCount == 1)
        let projected = await projection.snapshot()
        #expect(projected.isEmpty)
    }

    @Test("Rebuild restores projection from JSON seeds")
    func rebuildFromAuthority() async throws {
        let outbox = try JSONOutboxAuthority.makeTemporary()
        let projection = RealmOutboxLiveProjection()
        let curtain = MemoryComplexityCurtain(outbox: outbox, projection: projection)
        _ = try await curtain.retain(narrative: "one", project: "p", agent: "a")
        _ = try await curtain.retain(narrative: "two", project: "p", agent: "a")
        await projection.setForceFailOpen(true)
        await projection.setForceFailOpen(false)
        await curtain.rebuildProjectionFromAuthority()
        let snap = await projection.snapshot()
        #expect(snap.count == 2)
    }
}

@Suite("RetrievalPlannerFusion")
struct RetrievalPlannerFusionTests {
    @Test("Planner classifies temporal and code-graph intents")
    func classify() {
        let planner = RecallPlanner()
        #expect(planner.classify(query: "what happened last week") == .temporal)
        #expect(planner.classify(query: "which function depends on AuthClient") == .codeGraph)
        #expect(planner.classify(query: "summarize what do we know about cloaks") == .synthesis)
        let plan = planner.plan(for: .longDocument)
        #expect(plan.steps.contains(where: { $0.route == .longDocumentIndex }))
    }

    @Test("Rank fusion merges lists and suppresses tombstones")
    func fusionTombstones() {
        let idKeep = UUID()
        let idGone = UUID()
        let a = [
            RawRecallHit(id: idKeep, title: "Keep", body: "alpha", route: .durableOutbox, score: 20),
            RawRecallHit(id: idGone, title: "Gone", body: "beta", route: .durableOutbox, score: 15),
        ]
        let b = [
            RawRecallHit(id: idKeep, title: "Keep", body: "alpha", route: .hotWorking, score: 10),
        ]
        let fused = RankFusion.fuse(lists: [a, b], tombstones: [idGone], limit: 5)
        #expect(fused.count == 1)
        #expect(fused[0].id == idKeep)
        #expect(fused[0].contributingRoutes.contains(.durableOutbox))
        #expect(fused[0].contributingRoutes.contains(.hotWorking))
    }
}

@Suite("MemoryComplexityCurtain")
struct MemoryComplexityCurtainTests {
    @Test("Retain → recall finds durable narrative")
    func retainRecallRoundTrip() async throws {
        let curtain = try await MemoryComplexityCurtain.makeEphemeral()
        let receipt = try await curtain.retain(
            narrative: "Andromida curtain hides Graphiti behind memory_retain",
            project: "andromeda",
            agent: "test"
        )
        let response = await curtain.recall(query: "Graphiti curtain")
        #expect(response.hits.contains(where: { $0.id == receipt.memoryID }))
        #expect(response.intent == .exact || response.intent == .codeGraph || response.intent == .synthesis)
    }

    @Test("Forget tombstone suppresses recall hits")
    func forgetSuppresses() async throws {
        let curtain = try await MemoryComplexityCurtain.makeEphemeral()
        let receipt = try await curtain.retain(
            narrative: "secret should vanish",
            project: "p",
            agent: "a"
        )
        _ = try await curtain.forget(targetMemoryID: receipt.memoryID, reason: "redact")
        let response = await curtain.recall(query: "secret vanish")
        #expect(!response.hits.contains(where: { $0.id == receipt.memoryID }))
    }

    @Test("Health reports green with matching projection")
    func healthGreen() async throws {
        let curtain = try await MemoryComplexityCurtain.makeEphemeral()
        _ = try await curtain.retain(narrative: "healthy row", project: "p", agent: "a")
        let report = await curtain.health()
        #expect(report.level == .green || report.level == .yellow)
        #expect(!report.drift.drifted)
    }

    @Test("Drift detection flags missing projection rows")
    func driftDetection() async throws {
        let outbox = try JSONOutboxAuthority.makeTemporary()
        let projection = RealmOutboxLiveProjection()
        let curtain = MemoryComplexityCurtain(outbox: outbox, projection: projection)
        _ = try await curtain.retain(narrative: "authority only after fail", project: "p", agent: "a")
        await projection.setForceFailOpen(true)
        _ = try await curtain.retain(narrative: "second without mirror", project: "p", agent: "a")
        let report = await curtain.health()
        #expect(report.drift.drifted)
        #expect(report.drift.missingInProjection >= 1)
    }

    @Test("Replay delivers pending rows")
    func replayPending() async throws {
        let curtain = try await MemoryComplexityCurtain.makeEphemeral()
        _ = try await curtain.retain(narrative: "needs delivery", project: "p", agent: "a")
        let result = await curtain.replayPending { _ in }
        #expect(result.delivered == 1)
        #expect(result.deadLetter == 0)
        let insights = await curtain.outboxQueueInsights()
        #expect(insights.delivered == 1)
        #expect(insights.pending == 0)
    }
}
