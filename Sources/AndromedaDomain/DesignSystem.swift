// Andromeda Design System — canonical tokens
// Source: Andromeda Design System v1 (brand system spec)
// "Control the chaos, conceal the complexity."

import Foundation

// MARK: - Color palette

/// Near-black cool neutrals carry the system; a single teal glow does the accenting.
/// Green is reserved for live/healthy status only.
public enum AndromedaColor: String, Sendable, CaseIterable {
    /// #030B0C — primary background (void)
    case void = "#030B0C"
    /// #040D0E — deep panel surface
    case panel = "#040D0E"
    /// #0D1A1B — elevated surface / app icon bg
    case surface = "#0D1A1B"
    /// #34E8DC — primary accent (teal)
    case teal = "#34E8DC"
    /// #8FFBEF — hover / glow
    case glow = "#8FFBEF"
    /// #3EE08C — healthy / live status only
    case live = "#3EE08C"
    /// #E9FBF8 — primary text (ink)
    case ink = "#E9FBF8"
    /// #7FA39E — muted / secondary text
    case muted = "#7FA39E"
    /// #5F8D88 — dimmer muted (labels, eyebrows)
    case mutedDim = "#5F8D88"
    /// #FF9D94 — degraded / alert
    case alert = "#FF9D94"

    /// RGBA line color used for borders — 13% opacity teal.
    public static let line = "rgba(94,234,222,.13)"

    /// CSS hex string (uppercase to match the design system spec).
    public var cssHex: String { rawValue.uppercased() }
}

// MARK: - Typography

/// Three typefaces, each with a dedicated role. Never mix them.
public enum AndromedaFont: String, Sendable {
    /// Display / headlines only.
    case instrumentSerif = "Instrument Serif"
    /// Body / UI text.
    case spaceGrotesk = "Space Grotesk"
    /// Capability IDs, code, status — never rendered in serif or grotesk.
    case jetbrainsMono = "JetBrains Mono"
}

// MARK: - Motion

/// Motion language for a living station — subtle, rhythmic, never flashy.
public enum AndromedaMotion: Sendable {
    /// Health/live dots — 2.4s ease-in-out pulse.
    public static let pulseDuration: Double = 2.4
    /// Core breathing rings — 3.2s ease-in-out.
    public static let breatheDuration: Double = 3.2
    /// Orbiting satellites — 7s linear drift.
    public static let orbitDuration: Double = 7.0
}

// MARK: - Spacing & radii

/// 16px base border radius for cards; 11px for buttons; 999px for pills/capsules.
public enum AndromedaRadius: Sendable {
    public static let card: Double = 16
    public static let button: Double = 11
    public static let pill: Double = 999
}

// MARK: - Iconography

/// Six pillar glyphs — 1.4px strokes, 20px grid, rounded joins.
public enum AndromedaPillar: String, Sendable, CaseIterable {
    case memory
    case mcp
    case skills
    case llm
    case secrets
    case fleet
}

// MARK: - Voice

/// Brand voice guidelines — honest, calm, precise.
public enum AndromedaVoice: Sendable {
    /// DO: Honest, calm, precise. Name what's shipped vs specified.
    /// "No hidden workers. No silent sprawl."
    public static let doExample = "No hidden workers. No silent sprawl."

    /// DON'T: No greenwashing, no provider brand names in client copy, no hype adjectives.
    public static let dontExample = "No greenwashing, no provider brand names, no hype adjectives."
}

// MARK: - Tagline

public enum AndromedaBrand: Sendable {
    /// Primary tagline — used in headers and footers.
    public static let tagline = "Control the chaos, conceal the complexity."

    /// Secondary descriptor.
    public static let descriptor = "A calm, glassy, space-station language for a local-first Swift control plane."

    /// System version label.
    public static let versionLabel = "Andromeda · brand system v1"
}

// MARK: - CSS root variables (for embedded HTML dashboard)

/// Generates the `:root{}` CSS variable block matching the design system spec.
/// Used by `DashboardRoute` to produce on-brand inline styles.
public enum AndromedaDesignTokens {
    public static let cssRootVariables: String = """
    :root{--bg:#030b0c;--panel:#040d0e;--surface:#0d1a1b;--ink:#e9fbf8;--mut:#7fa39e;--mut2:#5f8d88;--teal:#34e8dc;--glow:#8ffbef;--green:#3ee08c;--line:rgba(94,234,222,.13)}
    """

    /// Google Fonts import URL for the three typefaces.
    public static let fontsImportURL = "https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300..700&family=JetBrains+Mono:ital,wght@0,400..600;1,400&family=Instrument+Serif:ital@0;1&display=swap"

    /// Full `<link>` + `<style>` block for HTML head injection.
    public static func htmlHeadLinks(preconnect: Bool = true) -> String {
        var parts: [String] = []
        if preconnect {
            parts.append(#"<link rel="preconnect" href="https://fonts.googleapis.com">"#)
        }
        parts.append(#"<link href="\#(fontsImportURL)" rel="stylesheet">"#)
        return parts.joined(separator: "\n")
    }

    /// Keyframe animations as CSS — pulse, breathe, orbit.
    public static let keyframeAnimations: String = """
    @keyframes dsPulse{0%,100%{opacity:1;box-shadow:0 0 6px 1px rgba(62,224,140,.85)}50%{opacity:.5;box-shadow:0 0 13px 4px rgba(62,224,140,.35)}}
    @keyframes dsBreathe{0%,100%{opacity:.4;transform:scale(1)}50%{opacity:.9;transform:scale(1.22)}}
    @keyframes dsOrbit{from{transform:rotate(0)}to{transform:rotate(360deg)}}
    """
}

// MARK: - ASCII logo (for TUI / CLI)

/// ASCII art rendering of the Andromeda mark for terminal output.
/// Three-fold luminous form — a curtain of light over a dark horizon.
public enum AndromedaASCIILogo {
    /// Multi-line ASCII art banner for CLI startup.
    /// Uses ANSI teal coloring when `colored` is true.
    public static func banner(colored: Bool = true) -> String {
        let art = Self.asciiArt

        if !colored {
            return art
        }

        // ANSI escape codes for Andromeda palette
        let teal = "\u{001B}[38;5;80m"       // #34e8dc approximation
        let glow = "\u{001B}[38;5;123m"      // #8ffbef approximation
        let dim = "\u{001B}[38;5;243m"       // #5f8d88 approximation
        let reset = "\u{001B}[0m"
        let bold = "\u{001B}[1m"

        // Color the art lines: glow for the top folds, teal for structure, dim for ground
        let lines = art.components(separatedBy: "\n")
        let coloredLines = lines.enumerated().map { (index, line) -> String in
            let isTopHalf = index < lines.count / 2
            let color = isTopHalf ? glow : teal
            return "\(color)\(line)\(reset)"
        }

        let coloredArt = coloredLines.joined(separator: "\n")
        let wordmark = "\(bold)\(glow)Andromeda\(reset)\(dim) — Control the chaos, conceal the complexity.\(reset)"

        return "\(coloredArt)\n\n\(wordmark)"
    }

    /// Raw ASCII art without color codes.
    static let asciiArt = #"""
    ╭──────────────────────────────────────────────────╮
    │                                                  │
    │      ╱╲    ╱╲    ╱╲                              │
    │     ╱  ╲  ╱  ╲  ╱  ╲       ◆ Andromeda          │
    │    ╱    ╲╱    ╲╱    ╲       Runtime v2           │
    │   ─────────────────────                          │
    │    ◢◣  ◢◣  ◢◣  ◢◣  ◢◣                          │
    │                                                  │
    ╰──────────────────────────────────────────────────╯
    """#
}
