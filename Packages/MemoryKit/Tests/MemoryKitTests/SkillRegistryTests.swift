/**
 * SkillRegistry observe tests (HAB-598) — catalog + disk presence, never invoke.
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
    func scanAllMissing() {
        let registry = SkillRegistry(enumerator: NullSkillPathEnumerator())
        let result = registry.scan()
        #expect(result.entities.count == 4)
        #expect(result.presentCount == 0)
        #expect(result.missingCount == 4)
        #expect(result.entities.allSatisfy { !$0.presentOnDisk })
    }

    @Test("scan marks knowledge-sync present when path discovered")
    func scanKnowledgeSyncPresent() {
        let registry = SkillRegistry(
            enumerator: MockSkillPathEnumerator(paths: [
                "knowledge-sync": "/tmp/fake/.claude/skills/knowledge-sync",
                "checkpoint": "/tmp/fake/.claude/skills/checkpoint",
            ]),
            source: .claude
        )
        let result = registry.scan()
        let sync = result.entities.first { $0.kind == .knowledgeSync }
        let close = result.entities.first { $0.kind == .close }
        #expect(sync?.presentOnDisk == true)
        #expect(sync?.path?.contains("knowledge-sync") == true)
        #expect(close?.presentOnDisk == false)
        #expect(result.presentCount == 2)
        #expect(result.missingCount == 2)
    }

    @Test("listCapabilityIDs always returns full catalog")
    func listAlwaysFull() {
        let registry = SkillRegistry(enumerator: NullSkillPathEnumerator())
        #expect(registry.listCapabilityIDs() == SkillRegistry.catalogCapabilityIDs)
    }

    @Test("knowledge-sync plan lists live destinations and excludes Ladybug")
    func knowledgeSyncPlan() {
        let plan = SkillRegistry().knowledgeSyncPlan()
        #expect(plan.capabilityID == "skill.knowledge-sync")
        #expect(plan.rows.count == KnowledgeSyncDestination.allCases.count)
        #expect(plan.rows.contains { $0.destination == .qdrant && $0.status == .live })
        #expect(plan.excluded.contains(where: { $0.lowercased().contains("ladybug") }))
        #expect(!plan.rows.contains { $0.destination.rawValue.lowercased().contains("ladybug") })
    }
}
