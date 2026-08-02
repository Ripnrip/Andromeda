import Testing
@testable import AndromedaHUDCore
import MemoryKit

@Suite("HUDSelectionNavigation")
struct HUDSelectionNavigationTests {
    @Test("move wraps at both ends")
    func moveWraps() {
        #expect(HUDSelectionNavigation.move(selectedIndex: 0, total: 3, up: true) == 2)
        #expect(HUDSelectionNavigation.move(selectedIndex: 2, total: 3, up: false) == 0)
        #expect(HUDSelectionNavigation.move(selectedIndex: 1, total: 3, up: true) == 0)
        #expect(HUDSelectionNavigation.move(selectedIndex: 1, total: 3, up: false) == 2)
    }

    @Test("move is a no-op when total is zero")
    func moveEmpty() {
        #expect(HUDSelectionNavigation.move(selectedIndex: 0, total: 0, up: true) == 0)
        #expect(HUDSelectionNavigation.move(selectedIndex: 4, total: 0, up: false) == 4)
    }

    @Test("selectableCount includes recent queries when shown")
    func recentQueriesCount() {
        let count = HUDSelectionNavigation.selectableCount(
            outcome: .idle,
            showRecentQueries: true,
            recentQueryCount: 10
        )
        #expect(count == HUDSelectionNavigation.recentQueriesVisibleLimit)

        let empty = HUDSelectionNavigation.selectableCount(
            outcome: .idle,
            showRecentQueries: true,
            recentQueryCount: 2
        )
        #expect(empty == 2)
    }

    @Test("selectableCount uses recalled / project rows when not showing recent")
    func outcomeCounts() {
        let hits = [
            MemoryHit(narrative: "a", source: .hotStore, score: 1),
            MemoryHit(narrative: "b", source: .vault, score: 1),
        ]
        #expect(
            HUDSelectionNavigation.selectableCount(
                outcome: .recalled(hits: hits),
                showRecentQueries: false,
                recentQueryCount: 5
            ) == 2
        )

        let states = [
            ProjectState(
                id: "p1",
                title: "Andromeda",
                status: .active,
                items: [
                    ProjectStateItem(id: "i1", title: "One", status: .active),
                    ProjectStateItem(id: "i2", title: "Two", status: .done),
                    ProjectStateItem(id: "i3", title: "Three", status: .backlog),
                ]
            )
        ]
        #expect(
            HUDSelectionNavigation.selectableCount(
                outcome: .projects(states: states),
                showRecentQueries: false,
                recentQueryCount: 0
            ) == 2
        )

        #expect(
            HUDSelectionNavigation.selectableCount(
                outcome: .empty(message: "none"),
                showRecentQueries: false,
                recentQueryCount: 3
            ) == 0
        )
    }
}
