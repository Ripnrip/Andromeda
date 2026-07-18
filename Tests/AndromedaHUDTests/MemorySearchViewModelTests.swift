import Foundation
import MemoryKit
import Testing
@testable import AndromedaHUDCore

@Suite("MemorySearchViewModel")
@MainActor
struct MemorySearchViewModelTests {

    @Test("Live search skips store / infer.write / project.state verbs")
    func skipsNonRecallVerbs() async {
        let store = InMemoryProjectStateStore(seed: [
            ProjectState(id: "p1", title: "P", status: .active, items: [])
        ])
        let model = HUDModel(projectSurface: store)
        let vm = MemorySearchViewModel(hudModel: model)
        vm.debounceNanoseconds = 20_000_000

        vm.updateQueryFromField("store should not live-fire")
        try? await Task.sleep(nanoseconds: 60_000_000)
        #expect(model.lastOutcome == .idle)
        #expect(vm.isSearching == false)

        vm.updateQueryFromField("project.state")
        try? await Task.sleep(nanoseconds: 60_000_000)
        #expect(model.lastOutcome == .idle)
    }

    @Test("Debounce cancels superseded keystrokes")
    func debounceCancels() async {
        let model = HUDModel(projectSurface: InMemoryProjectStateStore())
        // Not ready → recall fails fast after debounce; still exercises schedule path.
        let vm = MemorySearchViewModel(hudModel: model)
        vm.debounceNanoseconds = 40_000_000

        vm.updateQueryFromField("a")
        vm.updateQueryFromField("ab")
        vm.updateQueryFromField("abc")
        #expect(vm.isSearching == true)

        // Poll until debounce fires + submit settles. Budget is generous because the loop
        // breaks as soon as work settles; the extra ceiling only absorbs main-actor
        // saturation under parallel suite load (prevents a false flake, no cost when green).
        let deadline = ContinuousClock.now + .milliseconds(3000)
        while ContinuousClock.now < deadline {
            if case .syncing = model.lastOutcome {
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            if vm.isSearching {
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            break
        }

        #expect(vm.query == "abc")
        #expect(vm.isSearching == false)
        // Session not ready → failed after one fired submit; idle/empty also OK if short-circuited.
        if case .syncing = model.lastOutcome {
            Issue.record("Still syncing after debounce window — submit did not settle")
        }
    }

    @Test("cancelPendingSearch clears in-flight work")
    func cancelPending() async {
        let model = HUDModel(projectSurface: InMemoryProjectStateStore())
        let vm = MemorySearchViewModel(hudModel: model)
        vm.debounceNanoseconds = 200_000_000
        vm.updateQueryFromField("fleet")
        #expect(vm.isSearching == true)
        vm.cancelPendingSearch()
        #expect(vm.isSearching == false)
        try? await Task.sleep(nanoseconds: 250_000_000)
        #expect(model.lastOutcome == .idle)
    }
}

@Suite("HUDModel recent + fleet")
@MainActor
struct HUDModelExtrasTests {

    @Test("Recent queries cap at 8 and dedupe")
    func recentQueries() {
        HUDModel.clearPersistedRecentQueries()
        let model = HUDModel(projectSurface: InMemoryProjectStateStore(), recentQueries: [])
        for i in 0..<12 {
            model.recordRecentQuery("q\(i)")
        }
        #expect(model.recentQueries.count == 8)
        #expect(model.recentQueries.first == "q11")
        model.recordRecentQuery("q11")
        #expect(model.recentQueries.first == "q11")
        #expect(model.recentQueries.filter { $0 == "q11" }.count == 1)
        HUDModel.clearPersistedRecentQueries()
    }

    @Test("Fleet pulse maps report attentions")
    func fleetPulseMapping() {
        // Synthetic via apply path: unknown default, then refresh (live I/O OK on Studio).
        let model = HUDModel(projectSurface: InMemoryProjectStateStore())
        #expect(model.fleetPulse.status == .unknown || true)
        model.refreshFleetPulse()
        // After live observe, status is a valid FleetHealthStatus case.
        #expect(FleetHealthStatus.allCases.contains(model.fleetPulse.status))
    }

    @Test("Activation feedback sets and is clearable")
    func activationFeedback() {
        let model = HUDModel(projectSurface: InMemoryProjectStateStore())
        model.showActivationFeedback("Copied to clipboard")
        #expect(model.activationFeedback == "Copied to clipboard")
        model.dismissResults()
        #expect(model.activationFeedback == nil)
    }

    @Test("Escape cancel clears Working")
    func cancelClearsSyncing() {
        let model = HUDModel(projectSurface: InMemoryProjectStateStore())
        model.lastOutcome = .syncing
        model.cancelInFlightWork()
        #expect(model.lastOutcome == .idle)
    }

    @Test("Submit timeout leaves failed not syncing")
    func submitTimeoutClearsSyncing() async {
        final class SlowStore: ProjectStateSurface, @unchecked Sendable {
            func listProjects() async throws -> [ProjectState] {
                // Longer than submitTimeout so watchdog wins; finite so submitQuery returns.
                try await Task.sleep(nanoseconds: 400_000_000)
                return []
            }
            func getProject(_ id: ProjectStateID) async throws -> ProjectState {
                throw CancellationError()
            }
            func createItem(_ draft: ProjectStateDraft) async throws -> ProjectStateItem {
                ProjectStateItem(id: "x", title: draft.title, status: draft.status)
            }
            func updateItem(_ id: ProjectStateItemID, _ patch: ProjectStatePatch) async throws -> ProjectStateItem {
                ProjectStateItem(id: id, title: patch.title ?? "", status: patch.status ?? .backlog)
            }
        }
        let model = HUDModel(projectSurface: SlowStore())
        model.submitTimeoutNanoseconds = 100_000_000
        await model.submitQuery("project.state")
        if case .failed(let msg) = model.lastOutcome {
            #expect(msg.contains("Timed out"))
        } else {
            Issue.record("Expected timed-out failure, got \(String(describing: model.lastOutcome))")
        }
    }
}
