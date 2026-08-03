import SwiftUI

// MARK: - Andromeda Design System — SwiftUI Color tokens
// Source: Andromeda Design System v1
// BIN-232: Shared UI color pattern for HUD and Home surfaces.

extension Color {
    /// #34E8DC — primary accent (teal)
    static let andromedaTeal = Color(red: 0.204, green: 0.910, blue: 0.863)
    /// #8FFBEF — hover / glow
    static let andromedaGlow = Color(red: 0.561, green: 0.984, blue: 0.937)
    /// #3EE08C — healthy / live status only
    static let andromedaLive = Color(red: 0.243, green: 0.878, blue: 0.549)
    /// #FF9D94 — degraded / alert
    static let andromedaAlert = Color(red: 1.0, green: 0.616, blue: 0.580)
    /// #E9FBF8 — primary text (ink)
    static let andromedaInk = Color(red: 0.914, green: 0.984, blue: 0.973)
    /// #7FA39E — muted / secondary
    static let andromedaMuted = Color(red: 0.498, green: 0.639, blue: 0.620)
    /// #030B0C — void background
    static let andromedaVoid = Color(red: 0.012, green: 0.043, blue: 0.047)
    /// #0D1A1B — panel surface
    static let andromedaPanel = Color(red: 0.051, green: 0.102, blue: 0.106)

    /// Teal-tinted line color for borders — 13% opacity.
    static let andromedaLine = Color.andromedaTeal.opacity(0.13)
    /// Teal-tinted selection highlight for rows/cells.
    static let andromedaSelection = Color.andromedaTeal.opacity(0.12)
    /// Teal-tinted hover state.
    static let andromedaHover = Color.andromedaTeal.opacity(0.06)
}
