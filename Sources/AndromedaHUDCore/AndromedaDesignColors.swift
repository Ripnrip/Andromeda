import AndromedaBrand
import SwiftUI

// MARK: - HUD colour names → design tokens
//
// The HUD's long-standing `Color.andromeda*` names, kept so call sites read
// naturally, each now an alias for a token from `AndromedaBrand` (DESIGN.md).
// No colour is spelled out here: change a value in DESIGN.md / globals.css /
// AndromedaPalette and the HUD follows. The parity tests cover the tokens.

extension Color {
    /// `primary` — electric cyan, the one accent that leads.
    static let andromedaTeal = AndromedaTheme.primary
    /// `signal` — live / healthy / passed.
    static let andromedaLive = AndromedaTheme.signal
    /// `partial` — needs attention, degraded, in progress.
    static let andromedaPartial = AndromedaTheme.partial
    /// `alert` — failed, blocked, critical.
    static let andromedaAlert = AndromedaTheme.alert
    /// `spec` — offline / not listening: not running, as opposed to failed.
    static let andromedaOffline = AndromedaTheme.spec
    /// `muted-foreground` — secondary text, unknown / not recorded.
    static let andromedaMuted = AndromedaTheme.mutedForeground

    /// Cyan-tinted hairline for borders — 13% `primary`.
    static let andromedaLine = AndromedaTheme.primary.opacity(0.13)
    /// Cyan-tinted selection highlight for rows/cells — 12% `primary`.
    static let andromedaSelection = AndromedaTheme.primary.opacity(0.12)
    /// Cyan-tinted hover state — 6% `primary`.
    static let andromedaHover = AndromedaTheme.primary.opacity(0.06)
}
