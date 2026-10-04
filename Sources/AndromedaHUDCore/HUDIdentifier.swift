import SwiftUI

/**
 * 🎭 The HUDIdentifier - The Stage-Door Ledger
 *
 * "Every pane and control wears its name at the door,
 * so the App Control ushers never guess where to go."
 *
 * - The Spellbinding Museum Director of Glass
 */

/// The `hud.<pane>.<control>` accessibility-identifier catalogue (HAB-838).
///
/// One enum, one spelling per surface: views stamp it, `HUDIdentifierTests`
/// prove each case materializes in the real AX tree, and the App Control
/// plane targets the raw values. The rawValues are the wire contract —
/// never rename one without migrating every client that addresses the HUD.
public enum HUDIdentifier: String, CaseIterable, Sendable {
    /// The pill's root container (`.contain` — level-1 keeps children visible).
    case root = "hud.root"
    /// The command TextField.
    case searchField = "hud.search.field"
    /// The fleet-pulse status dot.
    case fleetPulse = "hud.fleetPulse"
    /// The transient activation-feedback line.
    case feedback = "hud.feedback"
    /// The frosted results panel (`.contain` at level-1).
    case resultsContainer = "hud.results.container"
    /// The recent-queries pane — id rides the "Recent" header leaf; container
    /// identifiers nested deeper than level-1 collapse on macOS.
    case resultsRecent = "hud.results.recent"
    /// A recent-query row.
    case resultsRecentItem = "hud.results.recent.item"
    /// The shared empty / error / loading / success row.
    case resultsStatus = "hud.results.status"
    /// A recalled-memory row.
    case resultsHit = "hud.results.hit"
    /// The project.state pane — id rides a zero-size marker leaf for the
    /// same nesting reason as `resultsRecent`.
    case resultsProjects = "hud.results.projects"
    /// A project.state item row.
    case resultsProjectsItem = "hud.results.projects.item"
}

public extension View {
    /// 🌟 Stamps a catalogue spelling onto glass - the only sanctioned way to
    /// attach a `hud.*` identifier, so raw strings can never creep back in.
    func hudIdentifier(_ id: HUDIdentifier) -> some View {
        accessibilityIdentifier(id.rawValue)
    }
}
