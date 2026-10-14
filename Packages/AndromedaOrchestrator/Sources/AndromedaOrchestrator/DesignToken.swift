import Foundation

/// The design tokens the orchestrator console uses — a subset of the `colors:` map in
/// `DESIGN.md` at the repo root, in both themes.
///
/// `rawValue` is the token's name in DESIGN.md; `dark` and `light` are its exact sRGB
/// values there (the light value is DESIGN.md's `light-<name>`). This package is
/// standalone, so it carries its own copy; `DesignTokenParityTests` fails if any case
/// drifts from DESIGN.md, and the root package's parity tests hold DESIGN.md to
/// `web/app/globals.css`. Nothing else in the package spells a colour out.
enum DesignToken: String, CaseIterable, Sendable {
    case background
    case popover
    case card
    case secondary
    case border
    case foreground
    case mutedForeground = "muted-foreground"
    case spec
    case primary
    case signal
    case partial
    case alert

    /// Dark-theme sRGB value as `0xRRGGBB`.
    var dark: UInt32 {
        switch self {
        case .background: 0x040F12
        case .popover: 0x071416
        case .card: 0x081619
        case .secondary: 0x122225
        case .border: 0x203839
        case .foreground: 0xE6F1F2
        case .mutedForeground: 0x8B9C9E
        case .spec: 0x7A898F
        case .primary: 0x1DE4DB
        case .signal: 0x49DE78
        case .partial: 0xE5C057
        case .alert: 0xFB817A
        }
    }

    /// Light-theme sRGB value as `0xRRGGBB` (DESIGN.md `light-<name>`).
    var light: UInt32 {
        switch self {
        case .background: 0xF7FBFC
        case .popover: 0xFFFFFF
        case .card: 0xFFFFFF
        case .secondary: 0xE5EDEE
        case .border: 0xCFDADC
        case .foreground: 0x0F1D20
        case .mutedForeground: 0x4C5B5E
        case .spec: 0x687478
        case .primary: 0x008B8C
        case .signal: 0x00792F
        case .partial: 0x996700
        case .alert: 0xBE2E31
        }
    }
}

#if canImport(SwiftUI)
import SwiftUI

extension Color {
    /// An opaque sRGB colour from a token's `0xRRGGBB` value.
    init(token hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
#endif
