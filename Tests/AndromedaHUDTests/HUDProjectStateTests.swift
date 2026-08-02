/**
 * ✅ Andromeda HUD project.state — capability curtain (no tracker brands)
 */

import Foundation
import MemoryKit
import Testing
@testable import AndromedaHUDCore

@Suite("Andromeda HUD project.state")
@MainActor
struct HUDProjectStateTests {

    @Test("project / project.state query lists via project.state.list")
    func projectQueryLists() async {
        let seed = ProjectState(
            id: ProjectStateID(rawValue: "andromeda"),
            title: "Andromeda",
            status: .active,
            items: [
                ProjectStateItem(
                    id: ProjectStateItemID(rawValue: "item-1"),
                    title: "Wire HUD project.state",
                    status: .active
                ),
                ProjectStateItem(
                    id: ProjectStateItemID(rawValue: "item-2"),
                    title: "Done chore",
                    status: .done
                ),
            ]
        )
        let store = InMemoryProjectStateStore(seed: [seed])
        let model = HUDModel(projectSurface: store)

        await model.submitQuery("project")

        guard case .projects(let states) = model.lastOutcome else {
            Issue.record("Expected .projects, got \(model.lastOutcome)")
            return
        }
        #expect(states.count == 1)
        #expect(states[0].title == "Andromeda")
        #expect(states[0].items.contains(where: { $0.title == "Wire HUD project.state" }))
    }

    @Test("project.state prefix with filter matches project or item title")
    func projectStateFilter() async {
        let seed = [
            ProjectState(
                id: "alpha",
                title: "Alpha Fleet",
                status: .active,
                items: [
                    ProjectStateItem(id: "a1", title: "Observe pulse", status: .active),
                ]
            ),
            ProjectState(
                id: "beta",
                title: "Beta Lane",
                status: .active,
                items: [
                    ProjectStateItem(id: "b1", title: "Unrelated", status: .backlog),
                ]
            ),
        ]
        let store = InMemoryProjectStateStore(seed: seed)
        let model = HUDModel(projectSurface: store)

        await model.submitQuery("project.state pulse")

        guard case .projects(let states) = model.lastOutcome else {
            Issue.record("Expected .projects, got \(model.lastOutcome)")
            return
        }
        #expect(states.count == 1)
        #expect(states[0].id.rawValue == "alpha")
        #expect(states[0].items.map(\.title) == ["Observe pulse"])
    }

    @Test("empty project filter yields empty outcome")
    func emptyProjectFilter() async {
        let store = InMemoryProjectStateStore(seed: [
            ProjectState(id: "only", title: "Solo", status: .active, items: [])
        ])
        let model = HUDModel(projectSurface: store)

        await model.submitQuery("project nowhere-match")

        guard case .empty(let message) = model.lastOutcome else {
            Issue.record("Expected .empty, got \(model.lastOutcome)")
            return
        }
        #expect(message.lowercased().contains("project"))
        #expect(!message.localizedCaseInsensitiveContains("Linear"))
        #expect(!message.localizedCaseInsensitiveContains("Multica"))
    }

    @Test("client-safe failure redacts tracker brands")
    func clientSafeFailure() {
        let raw = ProjectStateError.providerFailure("Linear BIN-42 Multica HAB-9 failed")
        let safe = HUDModel.clientSafeProjectMessage(from: raw)
        #expect(!safe.localizedCaseInsensitiveContains("Linear"))
        #expect(!safe.localizedCaseInsensitiveContains("Multica"))
        #expect(!safe.contains("BIN-"))
        #expect(!safe.contains("HAB-"))
    }

    @Test("parse detects project verbs")
    func parseProjectVerbs() {
        #expect(HUDCommand.parse("project") == .project(query: ""))
        #expect(HUDCommand.parse("project.state") == .project(query: ""))
        #expect(HUDCommand.parse("project.state list") == .project(query: "list"))
        #expect(HUDCommand.parse("PROJECT Alpha") == .project(query: "Alpha"))
        #expect(HUDCommand.parse("project.state create Wire HUD chip") == .projectCreate(title: "Wire HUD chip"))
        #expect(HUDCommand.parse("project create Another item") == .projectCreate(title: "Another item"))
        #expect(HUDCommand.parse("project.state update item-1 Renamed title") == .projectUpdate(id: "item-1", title: "Renamed title"))
        #expect(HUDCommand.parse("project update item-2 New name") == .projectUpdate(id: "item-2", title: "New name"))
        #expect(HUDCommand.parse("project.state update") == .projectUpdate(id: "", title: ""))
        #expect(HUDCommand.parse("project update lone-id") == .projectUpdate(id: "lone-id", title: ""))
        #expect(HUDCommand.parse("recall foo") == .recall(query: "foo"))
        #expect(HUDCommand.parse("store bar") == .store(narrative: "bar"))
        #expect(HUDCommand.parse("infer.write thought") == .inferWrite(thought: "thought"))
        #expect(HUDCommand.parse("plain search") == .recall(query: "plain search"))
        #expect(HUDCommand.parse("project")?.capabilityID == .project)
        #expect(HUDCommand.parse("project.state create x")?.capabilityID == .project)
        #expect(HUDCommand.parse("project.state update a b")?.capabilityID == .project)
    }

    @Test("project.state create draft path is client-safe")
    func projectStateCreate() async {
        let seed = ProjectState(
            id: ProjectStateID(rawValue: "andromeda"),
            title: "Andromeda",
            status: .active,
            items: []
        )
        let store = InMemoryProjectStateStore(seed: [seed])
        let model = HUDModel(projectSurface: store)
        // Default submit watchdog (2.5s) can fire under AppKit snapshot main-actor load on
        // CI even for an in-memory create; widen for this unit path only.
        model.submitTimeoutNanoseconds = 15_000_000_000

        await model.submitQuery("project.state create Ship HUD create path")

        guard case .created(let title) = model.lastOutcome else {
            Issue.record("Expected .created, got \(model.lastOutcome)")
            return
        }
        #expect(title == "Ship HUD create path")

        let listed = try! await store.listProjects()
        #expect(listed[0].items.contains(where: { $0.title == "Ship HUD create path" }))
    }

    @Test("project.state update patches title via project.state.update")
    func projectStateUpdate() async {
        let seed = ProjectState(
            id: ProjectStateID(rawValue: "andromeda"),
            title: "Andromeda",
            status: .active,
            items: [
                ProjectStateItem(
                    id: ProjectStateItemID(rawValue: "item-1"),
                    title: "Old title",
                    status: .active
                ),
            ]
        )
        let store = InMemoryProjectStateStore(seed: [seed])
        let model = HUDModel(projectSurface: store)

        await model.submitQuery("project.state update item-1 Ship HUD update path")

        guard case .updated(let title) = model.lastOutcome else {
            Issue.record("Expected .updated, got \(model.lastOutcome)")
            return
        }
        #expect(title == "Ship HUD update path")

        let listed = try! await store.listProjects()
        #expect(listed[0].items.contains(where: { $0.id.rawValue == "item-1" && $0.title == "Ship HUD update path" }))
    }

    @Test("project.state update missing args yields client-safe empty hint")
    func projectStateUpdateNeedsArgs() async {
        let store = InMemoryProjectStateStore(seed: [
            ProjectState(id: "p", title: "P", status: .active, items: [])
        ])
        let model = HUDModel(projectSurface: store)

        await model.submitQuery("project update")

        guard case .empty(let message) = model.lastOutcome else {
            Issue.record("Expected .empty, got \(model.lastOutcome)")
            return
        }
        #expect(message.contains("project.state.update"))
        #expect(!message.localizedCaseInsensitiveContains("Linear"))
        #expect(!message.localizedCaseInsensitiveContains("Multica"))
    }

    @Test("project.state update failure redacts tracker brands")
    func projectStateUpdateFailureIsClientSafe() async {
        final class FailingUpdateStore: ProjectStateSurface, @unchecked Sendable {
            func listProjects() async throws -> [ProjectState] { [] }
            func getProject(_ id: ProjectStateID) async throws -> ProjectState {
                throw ProjectStateError.projectNotFound(id)
            }
            func createItem(_ draft: ProjectStateDraft) async throws -> ProjectStateItem {
                ProjectStateItem(id: "x", title: draft.title, status: draft.status)
            }
            func updateItem(_ id: ProjectStateItemID, _ patch: ProjectStatePatch) async throws -> ProjectStateItem {
                throw ProjectStateError.providerFailure("Linear BIN-99 Multica HAB-1 refused")
            }
        }
        let model = HUDModel(projectSurface: FailingUpdateStore())

        await model.submitQuery("project.state update item-x New title")

        guard case .failed(let message) = model.lastOutcome else {
            Issue.record("Expected .failed, got \(model.lastOutcome)")
            return
        }
        #expect(message.contains("project.state.update"))
        #expect(!message.localizedCaseInsensitiveContains("Linear"))
        #expect(!message.localizedCaseInsensitiveContains("Multica"))
        #expect(!message.contains("BIN-"))
        #expect(!message.contains("HAB-"))
    }
}
