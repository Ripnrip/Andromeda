/**
 * ✅ AndromedaHome project.state live panel — capability curtain (no tracker brands)
 */

import AndromedaHomeCore
import Foundation
import MemoryKit
import Testing

@Suite("AndromedaHome project.state")
@MainActor
struct AndromedaHomeProjectStateTests {

    @Test("Refresh applies project.state.list from injected surface")
    func refreshListsFromSurface() async throws {
        let seed = ProjectState(
            id: ProjectStateID(rawValue: "andromeda"),
            title: "Andromeda",
            status: .active,
            items: [
                ProjectStateItem(
                    id: ProjectStateItemID(rawValue: "seed-1"),
                    title: "Capability curtain",
                    status: .active
                )
            ]
        )
        let store = InMemoryProjectStateStore(seed: [seed])
        let model = AndromedaHomeModel(projectSurface: store)

        await model.refreshProjectState()

        #expect(model.projectState.projects.count == 1)
        #expect(model.projectState.projects.first?.title == "Andromeda")
        #expect(model.projectState.projects.first?.items.first?.title == "Capability curtain")
        #expect(model.projectState.lastMessage?.contains("project.state.list") == true)
        #expect(model.projectState.lastMessage?.localizedCaseInsensitiveContains("Linear") == false)
        #expect(model.projectState.lastMessage?.localizedCaseInsensitiveContains("Multica") == false)
    }

    @Test("Create uses project.state.create then re-lists")
    func createThenList() async throws {
        let seed = ProjectState(
            id: ProjectStateID(rawValue: "andromeda"),
            title: "Andromeda",
            status: .active,
            items: []
        )
        let store = InMemoryProjectStateStore(seed: [seed])
        let model = AndromedaHomeModel(projectSurface: store)
        await model.refreshProjectState()

        model.projectState.draftTitle = "Ship live panel"
        await model.createProjectItem()

        #expect(model.projectState.draftTitle.isEmpty)
        #expect(model.projectState.selectedProject?.items.contains(where: { $0.title == "Ship live panel" }) == true)
        #expect(model.projectState.lastMessage?.contains("project.state.list") == true)
    }

    @Test("Fixtures stay brand-neutral on the glass")
    func fixturesStayBrandNeutral() {
        let healthy = AndromedaHomeFixtures.healthyHome()
        let titles = healthy.projectState.projects.flatMap(\.items).map(\.title)
            + [healthy.projectState.lastMessage ?? ""]
        for text in titles {
            #expect(!text.localizedCaseInsensitiveContains("Linear"))
            #expect(!text.localizedCaseInsensitiveContains("Multica"))
            #expect(!text.contains("BIN-"))
            #expect(!text.contains("HAB-"))
        }
    }

    @Test("clientSafeMessage redacts tracker brands")
    func clientSafeMessageRedacts() {
        let raw = ProjectStateError.providerFailure("Linear BIN-42 Multica HAB-9 failed")
        let safe = ProjectStatePanelModel.clientSafeMessage(from: raw)
        #expect(!safe.localizedCaseInsensitiveContains("Linear"))
        #expect(!safe.localizedCaseInsensitiveContains("Multica"))
        #expect(!safe.contains("BIN-"))
        #expect(!safe.contains("HAB-"))
    }
}
