import Foundation
import MemoryKit

/// Pure keyboard selection math for HUD result lists (wrap-around).
/// Explicitly nonisolated so unit tests and AppKit key monitors can call it off the main actor.
enum HUDSelectionNavigation: Sendable {
    /// Matches `HUDRecentQueriesView` visible row budget.
    nonisolated static let recentQueriesVisibleLimit = 6

    /// Next selected index after ↑/↓, wrapping within `0..<total`.
    nonisolated static func move(selectedIndex: Int, total: Int, up: Bool) -> Int {
        guard total > 0 else { return selectedIndex }
        if up {
            return (selectedIndex - 1 + total) % total
        }
        return (selectedIndex + 1) % total
    }

    /// Count of rows arrow keys can walk when results are showing.
    nonisolated static func selectableCount(
        outcome: HUDOutcome,
        showRecentQueries: Bool,
        recentQueryCount: Int
    ) -> Int {
        if showRecentQueries {
            return min(recentQueryCount, recentQueriesVisibleLimit)
        }
        switch outcome {
        case .recalled(let hits):
            return hits.count
        case .projects(let states):
            // Inline flatten (same budget as HUDProjectResultsView) so this stays
            // nonisolated — calling into a SwiftUI View type re-infects MainActor.
            return Array(states.prefix(4)).flatMap { project in
                Array(project.items.filter { $0.status != .done }.prefix(4))
            }.count
        default:
            return 0
        }
    }
}
