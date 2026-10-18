/**
 * SkillRegistry observe tests (HAB-598) — catalog + disk presence, never invoke.
 * Review 5513453513: typed scan status (P1-1), actor isolation (P1-2),
 * opaque-ID curtain plan (P1-3).
 */

import Foundation
import Testing
@testable import MemoryKit

@Suite("SkillRegistry")
struct SkillRegistryTests {
    @Test("catalog exposes stable skill.* capability ids")
    func catalogIDs() {
        let ids = SkillRegistry.catalogCapabilityIDs
        #expect(ids.contains("skill.checkpoint"))
        #expect(ids.contains("skill.knowledge-sync"))
        #expect(ids.contains("skill.close"))
        #expect(ids.contains("skill.graphify"))
        #expect(ids.count == SkillKind.allCases.count)
    }

    @Test("scan marks missing skills when enumerator is empty")
    func scanAllMissing() async {
        let registry = SkillRegistry(enumerator: NullSkillPathEnumerator())
        let result = await registry.scan()
        #expect(result.entities.count == 4)
        #expect(result.presentCount == 0)
        #expect(result.missingCount == 4)
        #expect(result.entities.allSatisfy { !$0.presentOnDisk })
        #expect(result.status == .ok)
    }

    @Test("scan marks knowledge-sync present when path discovered")
    func scanKnowledgeSyncPresent() async {
        let registry = SkillRegistry(
            enumerator: MockSkillPathEnumerator(paths: [
                "knowledge-sync": "/tmp/fake/.claude/skills/knowledge-sync",
                "checkpoint": "/tmp/fake/.claude/skills/checkpoint",
            ]),
            source: .claude
        )
        let result = await registry.scan()
        let sync = result.entities.first { $0.kind == .knowledgeSync }
        let close = result.entities.first { $0.kind == .close }
        #expect(sync?.presentOnDisk == true)
        #expect(sync?.path?.contains("knowledge-sync") == true)
        #expect(close?.presentOnDisk == false)
        #expect(result.presentCount == 2)
        #expect(result.missingCount == 2)
        #expect(result.status == .ok)
    }

    @Test("listCapabilityIDs always returns full catalog")
    func listAlwaysFull() async {
        let registry = SkillRegistry(enumerator: NullSkillPathEnumerator())
        let ids = await registry.listCapabilityIDs()
        #expect(ids == SkillRegistry.catalogCapabilityIDs)
    }

    // MARK: P1-1 — typed scan status

    @Test("failed scan surfaces typed status instead of collapsing into missingCount")
    func scanFailureSurfacesTypedStatus() async {
        let registry = SkillRegistry(
            enumerator: MockSkillPathEnumerator(failed: .rootUnreadable, detail: "Operation not permitted")
        )
        let result = await registry.scan()
        #expect(result.status == .failed(code: .rootUnreadable, detail: "Operation not permitted"))
        #expect(!result.status.isOK)
        // Catalog rows remain visible as absent, but missingCount is not evidence.
        #expect(result.entities.count == 4)
        #expect(result.presentCount == 0)
    }

    @Test("missing skills root reports rootMissing, not an empty success")
    func missingRootIsTypedFailure() {
        let root = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/skills", isDirectory: true)
        let discovery = ClaudeSkillsPathEnumerator(skillsRoot: root).discoverSkills()
        #expect(discovery.paths.isEmpty)
        guard case let .failed(code, _) = discovery.status else {
            Issue.record("expected .failed, got \(discovery.status)")
            return
        }
        #expect(code == .rootMissing)
    }

    @Test("inaccessible skills root reports rootUnreadable via typed status")
    func inaccessibleRootIsTypedFailure() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt93-inaccessible-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)

        let discovery = ClaudeSkillsPathEnumerator(skillsRoot: root).discoverSkills()
        #expect(discovery.paths.isEmpty)
        guard case let .failed(code, detail) = discovery.status else {
            Issue.record("expected .failed for inaccessible root, got \(discovery.status)")
            return
        }
        #expect(code == .rootUnreadable)
        #expect(!detail.isEmpty)
    }

    // MARK: P1-3 — opaque curtain plan

    @Test("knowledge-sync plan lists opaque destination ids and excludes the nightly index")
    func knowledgeSyncPlan() async {
        let plan = await SkillRegistry().knowledgeSyncPlan()
        #expect(plan.capabilityID == "skill.knowledge-sync")
        #expect(plan.items.count == KnowledgeSyncDestination.allCases.count)
        #expect(plan.items.contains { $0.id == "destination.vector-index" && $0.status == .live })
        #expect(plan.items.contains { $0.id == "destination.session-stage" && $0.status == .staged })
        #expect(plan.excluded == [KnowledgeSyncDestination.excludedNightlyIndexCapabilityID])
    }

    @Test("encoded plan leaks no provider or topology identifiers (curtain)")
    func encodedPlanIsCurtainClean() async throws {
        let plan = await SkillRegistry().knowledgeSyncPlan()
        let data = try JSONEncoder().encode(plan)
        let json = String(decoding: data, as: UTF8.self)

        let bannedSubstrings = [
            "claude-mem", "claudeMem", "multibrain", "qdrant", "SecondBrain", "secondbrain",
            "Ladybug", "ladybug", "127.0.0.1", "6333", "~/.claude", "Letta", "memfs",
        ]
        for banned in bannedSubstrings {
            #expect(!json.contains(banned), "curtain leak: encoded plan contains `\(banned)`")
        }

        // Opaque ids and statuses are the only destination vocabulary on the wire.
        #expect(json.contains("destination.vector-index"))
        #expect(json.contains("\"live\""))
    }

    @Test("operator projection retains raw detail server-side")
    func operatorRowsRetainRawDetail() async {
        let plan = await SkillRegistry().knowledgeSyncPlan()
        let rows = plan.operatorRows()
        #expect(rows.count == KnowledgeSyncDestination.allCases.count)
        let vectorRow = rows.first { $0.destination == .qdrant }
        #expect(vectorRow?.id == "qdrant")
        #expect(vectorRow?.pathHint.contains("6333") == true)
        #expect(vectorRow?.displayName.contains("qdrant") == true)
    }
}
