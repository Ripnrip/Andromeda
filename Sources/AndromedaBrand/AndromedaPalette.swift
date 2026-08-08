/**
 * 🎨 AndromedaPalette — the single source of colour truth for every Andromeda surface.
 *
 * These values are transcribed from the production web design system
 * (`web/app/globals.css`, oklch tokens) into sRGB so that terminals, SwiftUI and
 * the website all speak the same palette. Deep-space obsidian teal, one electric
 * cyan accent, and the amber/green/slate status trio. Nothing else.
 *
 * Discipline: never introduce a colour here that does not exist in the web tokens.
 */

import Foundation

/// A single brand colour, expressed in sRGB so it can be rendered as ANSI,
/// hex, or a platform `Color` without re-deriving the value per surface.
public struct BrandColor: Sendable, Equatable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Uppercase `#RRGGBB`, the form used by the SwiftUI/native theme and docs.
    public var hex: String {
        String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue))
    }

    /// Nearest colour in the xterm-256 cube, for terminals without truecolor.
    public var ansi256: Int {
        func level(_ value: UInt8) -> Int {
            Int((Double(value) / 255.0 * 5.0).rounded())
        }
        return 16 + 36 * level(red) + 6 * level(green) + level(blue)
    }

    /// Normalised components, convenient for SwiftUI / CoreGraphics.
    public var components: (red: Double, green: Double, blue: Double) {
        (Double(red) / 255.0, Double(green) / 255.0, Double(blue) / 255.0)
    }
}

/// The Andromeda palette. Names match the web CSS custom properties one-for-one.
public enum AndromedaPalette {
    // MARK: Ground and text

    /// `--background` · obsidian ground.
    public static let background = BrandColor(red: 0x04, green: 0x0F, blue: 0x12)
    /// `--foreground` · primary text.
    public static let foreground = BrandColor(red: 0xE6, green: 0xF1, blue: 0xF2)
    /// `--card` · panel ground, one step above background.
    public static let card = BrandColor(red: 0x08, green: 0x16, blue: 0x19)
    /// `--popover` · floating surface ground.
    public static let popover = BrandColor(red: 0x07, green: 0x14, blue: 0x16)
    /// `--muted` · inert fill.
    public static let muted = BrandColor(red: 0x14, green: 0x22, blue: 0x24)
    /// `--muted-foreground` · secondary text.
    public static let mutedForeground = BrandColor(red: 0x8B, green: 0x9C, blue: 0x9E)
    /// `--secondary-foreground` · slightly dimmed primary text.
    public static let secondaryForeground = BrandColor(red: 0xDC, green: 0xE8, blue: 0xE9)
    /// `--border` · hairline.
    public static let border = BrandColor(red: 0x20, green: 0x38, blue: 0x39)
    /// `--input` · field stroke.
    public static let input = BrandColor(red: 0x1A, green: 0x2D, blue: 0x2F)

    // MARK: Brand

    /// `--primary` / `--ring` · electric cyan. The only accent that leads.
    public static let primary = BrandColor(red: 0x1D, green: 0xE4, blue: 0xDB)
    /// `--primary-foreground` · text on cyan.
    public static let primaryForeground = BrandColor(red: 0x00, green: 0x11, blue: 0x14)
    /// `--accent` · deeper teal for supporting emphasis.
    public static let accent = BrandColor(red: 0x00, green: 0xA8, blue: 0xAA)
    /// `--accent-foreground` · text on accent.
    public static let accentForeground = BrandColor(red: 0xF7, green: 0xFC, blue: 0xFC)

    // MARK: Status trio (+ cyan for shipped/healthy)

    /// `--shipped` · shipped / healthy / green path.
    public static let shipped = BrandColor(red: 0x1D, green: 0xE4, blue: 0xDB)
    /// `--signal` · live signal, success, positive delta.
    public static let signal = BrandColor(red: 0x49, green: 0xDE, blue: 0x78)
    /// `--partial` · partial / in progress / warning.
    public static let partial = BrandColor(red: 0xE5, green: 0xC0, blue: 0x57)
    /// `--spec` · specified only / inert / not started.
    public static let spec = BrandColor(red: 0x79, green: 0x89, blue: 0x8F)

    /// Every token, for docs, tests and palette dumps.
    public static let all: [(name: String, color: BrandColor)] = [
        ("background", background),
        ("foreground", foreground),
        ("card", card),
        ("popover", popover),
        ("muted", muted),
        ("muted-foreground", mutedForeground),
        ("secondary-foreground", secondaryForeground),
        ("border", border),
        ("input", input),
        ("primary", primary),
        ("primary-foreground", primaryForeground),
        ("accent", accent),
        ("accent-foreground", accentForeground),
        ("shipped", shipped),
        ("signal", signal),
        ("partial", partial),
        ("spec", spec),
    ]

    /// `--radius`, in points. 14 pt / 0.875rem.
    public static let radius: Double = 14
}
