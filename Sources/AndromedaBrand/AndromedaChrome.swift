/**
 * 🧿 AndromedaChrome — the terminal half of the Andromeda design system.
 *
 * Terminal equivalents of the web patterns: eyebrow + display pair, status chip,
 * field rows, CAVEAT callout, hairline rule, and the start-up banner. Every
 * Andromeda CLI prints through here so the TUI, the website and the macOS
 * surfaces stay one visual system.
 *
 * Honesty rule (inherited from the design system): status is never colour-only —
 * the dot always ships with its mono word.
 */

import Foundation

/// The shared status vocabulary. Roadmap words for docs surfaces, runtime words
/// for fleet surfaces — same colours, same chips, everywhere.
public enum BrandStatus: String, Sendable, CaseIterable {
    case shipped
    case partial
    case specified
    case healthy
    case degraded
    case offline

    public var color: BrandColor {
        switch self {
        case .shipped: return AndromedaPalette.shipped
        case .healthy: return AndromedaPalette.signal
        case .partial, .degraded: return AndromedaPalette.partial
        case .specified, .offline: return AndromedaPalette.spec
        }
    }

    public var word: String { rawValue.uppercased() }
}

public enum AndromedaChrome {
    // MARK: - Primitives

    /// Mono uppercase, letter-spaced eyebrow. The terminal echo of
    /// `text-xs uppercase tracking-widest text-primary`.
    public static func eyebrow(_ text: String, style: TerminalStyle, muted: Bool = false) -> String {
        let spaced = text.uppercased()
            .map(String.init)
            .joined(separator: " ")
        let color = muted ? AndromedaPalette.mutedForeground : AndromedaPalette.primary
        return style.paint(spaced, color, bold: !muted)
    }

    /// Full-bleed hairline, the `border-t border-border` band separator.
    public static func rule(_ width: Int? = nil, style: TerminalStyle) -> String {
        let glyph = style.glyph("─", ascii: "-")
        return style.paint(
            String(repeating: glyph, count: max(8, width ?? style.width)),
            AndromedaPalette.border
        )
    }

    /// Status chip: coloured dot + mono uppercase word. Never colour alone.
    public static func statusChip(_ status: BrandStatus, style: TerminalStyle) -> String {
        let dot = style.glyph("●", ascii: "*")
        return style.paint(dot, status.color) + " " + style.paint(status.word, status.color, bold: true)
    }

    /// `key: value` field row — mono key in muted, value in foreground.
    public static func field(_ key: String, _ value: String, style: TerminalStyle, keyWidth: Int = 12) -> String {
        let padded = key.count >= keyWidth
            ? key
            : key + String(repeating: " ", count: keyWidth - key.count)
        return style.paint(padded, AndromedaPalette.mutedForeground)
            + style.paint(value, AndromedaPalette.foreground)
    }

    /// A field row whose value carries a status chip instead of plain text.
    public static func field(
        _ key: String,
        status: BrandStatus,
        detail: String? = nil,
        style: TerminalStyle,
        keyWidth: Int = 12
    ) -> String {
        var line = field(key, "", style: style, keyWidth: keyWidth) + statusChip(status, style: style)
        if let detail, !detail.isEmpty {
            line += " " + style.paint(detail, AndromedaPalette.mutedForeground)
        }
        return line
    }

    /// Honest disclaimer callout: amber `CAVEAT` lead-in, foreground body.
    public static func caveat(_ text: String, style: TerminalStyle) -> String {
        style.paint("CAVEAT", AndromedaPalette.partial, bold: true)
            + style.paint("  " + text, AndromedaPalette.foreground)
    }

    /// Bordered status pill, the terminal form of the hero pill.
    public static func pill(_ text: String, style: TerminalStyle) -> String {
        let dot = style.glyph("●", ascii: "*")
        let open = style.glyph("(", ascii: "(")
        let close = style.glyph(")", ascii: ")")
        return style.paint(open, AndromedaPalette.border)
            + style.paint(dot, AndromedaPalette.primary)
            + " " + style.paint(text.uppercased(), AndromedaPalette.secondaryForeground)
            + style.paint(close, AndromedaPalette.border)
    }

    // MARK: - Mark painting

    /// Paints trefoil density as the logo's glow: halo → accent → cyan core.
    public static func paintedMark(
        _ size: AndromedaASCII.MarkSize = .full,
        style: TerminalStyle
    ) -> [String] {
        AndromedaASCII.mark(size).map { line in
            guard style.colorMode != .plain else { return line }
            var painted = ""
            var run = ""
            var runColor: BrandColor?
            var runBold = false

            func flush() {
                guard !run.isEmpty else { return }
                painted += runColor == nil ? run : style.paint(run, runColor, bold: runBold)
                run = ""
            }

            for character in line {
                let (color, bold): (BrandColor?, Bool)
                switch character {
                case ".", ":", "-":
                    (color, bold) = (AndromedaPalette.accent, false)
                case "=", "+", "*":
                    (color, bold) = (AndromedaPalette.shipped, false)
                case "#", "%", "@":
                    (color, bold) = (AndromedaPalette.primary, true)
                default:
                    (color, bold) = (nil, false)
                }
                if color != runColor || bold != runBold {
                    flush()
                    runColor = color
                    runBold = bold
                }
                run.append(character)
            }
            flush()
            return painted
        }
    }

    // MARK: - Banner

    /// Start-up banner: trefoil, wordmark, eyebrow, version, tagline, hairline.
    ///
    /// - Parameters:
    ///   - surface: the capability surface being started, e.g. `autocache gateway`.
    ///   - version: product version string, omitted when the surface has none to claim.
    ///   - tagline: one honest line about what this process does.
    ///   - compact: use the narrow trefoil and drop the wordmark (for tight logs).
    public static func banner(
        surface: String,
        version: String?,
        tagline: String,
        style: TerminalStyle,
        compact: Bool = false
    ) -> String {
        var lines: [String] = [""]
        lines += paintedMark(compact ? .compact : .full, style: style)
        lines.append("")

        if compact {
            lines.append("  " + style.paint(AndromedaASCII.spacedWordmark, AndromedaPalette.primary, bold: true))
        } else {
            lines += AndromedaASCII.wordmark.map { style.paint($0, AndromedaPalette.foreground, bold: true) }
            lines.append("")
        }

        lines.append("  " + eyebrow(surface, style: style))
        lines.append("  " + style.paint(tagline, AndromedaPalette.mutedForeground))
        if let version, !version.isEmpty {
            lines.append("  " + style.paint("v" + version, AndromedaPalette.accent))
        }
        lines.append("  " + rule(min(style.width, 62), style: style))
        return lines.joined(separator: "\n")
    }

    /// Marquee of principles, the terminal form of the web ticker band.
    public static func principles(_ items: [String], style: TerminalStyle) -> String {
        let separator = style.paint(" " + style.glyph("◈", ascii: "<>") + " ", AndromedaPalette.primary)
        return items
            .map { style.paint($0, AndromedaPalette.secondaryForeground, italic: true) }
            .joined(separator: separator)
    }
}
