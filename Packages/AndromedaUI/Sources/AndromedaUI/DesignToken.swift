import SwiftUI

/// The Andromeda design tokens — the `colors:` set from `DESIGN.md` at the repo root.
///
/// The full dark-theme set, plus the light-theme tokens this package uses. `rawValue` is
/// the token's name in DESIGN.md and `hex` is its exact sRGB value, so the package
/// speaks the same palette as the website (`web/app/globals.css`) and the
/// macOS/terminal surfaces (`AndromedaBrand`). The only colours outside the system are
/// the illustration palette in `Pillars/Dreaming/PillarKit.swift`, each an annotated
/// exception to the `raw-color-literal` lint (an error everywhere else).
///
/// This package can't import `AndromedaBrand` (the root package depends on it, so the
/// import would be a cycle), so the values live here. `DesignTokenParityTests` fails
/// if any case drifts from DESIGN.md, and the root package's parity tests hold
/// DESIGN.md to the web tokens — one chain, no unchecked copy.
public enum DesignToken: String, CaseIterable, Sendable {
    // MARK: Ground and text
    case background
    case foreground
    case card
    case cardForeground = "card-foreground"
    case popover
    case popoverForeground = "popover-foreground"
    case secondary
    case secondaryForeground = "secondary-foreground"
    case muted
    case mutedForeground = "muted-foreground"
    case border
    case input

    // MARK: Brand light
    case primary
    case primaryForeground = "primary-foreground"
    case accent
    case accentForeground = "accent-foreground"
    case ring
    case glow

    // MARK: Status
    case shipped
    case signal
    case partial
    case spec
    case alert

    // MARK: Light theme
    /// Light-theme ground, used by `AndromedaSurface` in light previews.
    case lightBackground = "light-background"

    /// The token's sRGB value as `0xRRGGBB`.
    public var hex: UInt32 {
        switch self {
        case .background: 0x040F12
        case .foreground: 0xE6F1F2
        case .card: 0x081619
        case .cardForeground: 0xE6F1F2
        case .popover: 0x071416
        case .popoverForeground: 0xE6F1F2
        case .secondary: 0x122225
        case .secondaryForeground: 0xDCE7E8
        case .muted: 0x142224
        case .mutedForeground: 0x8B9C9E
        case .border: 0x203839
        case .input: 0x1A2D2F
        case .primary: 0x1DE4DB
        case .primaryForeground: 0x001114
        case .accent: 0x00A8AA
        case .accentForeground: 0xF1FBFB
        case .ring: 0x1DE4DB
        case .glow: 0x90FAF3
        case .shipped: 0x1DE4DB
        case .signal: 0x49DE78
        case .partial: 0xE5C057
        case .spec: 0x7A898F
        case .alert: 0xFB817A
        case .lightBackground: 0xF7FBFC
        }
    }

    /// The token as an opaque sRGB SwiftUI colour.
    public var color: Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
