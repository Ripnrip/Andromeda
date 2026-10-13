// AndromedaCompanionTheme.swift
//
// The companion HUD's `AndromedaTheme.*` namespace. The companion scenes were
// authored against the web theme's token names (primary / accent / signal / …), so
// this enum mirrors those names one-for-one and resolves each to the `DesignToken`
// of the same name — a name here means exactly what it means in DESIGN.md, on the
// website, and in `AndromedaBrand`.
//
// Design decision: a thin enum with static Color properties, NOT a protocol or
// environment key. The companion scenes use these as concrete values in
// Canvas-drawn glyph art, where theme-swapping isn't a runtime concern.

import SwiftUI

public enum AndromedaTheme {

    // MARK: - Core palette (each resolves to the DesignToken of the same name)

    /// Scene ground — also the fill that "bites" the crescent moon, so it must
    /// match the surface behind it.
    public static let background = DesignToken.background.color

    /// Primary teal — the dominant colour across all specimens and scenes.
    public static let primary = DesignToken.primary.color

    /// Deep teal for supporting emphasis. Not for halos — that's `glow`.
    public static let accent = DesignToken.accent.color

    /// Brightest cyan — halos, breathing glows, the moon, the eye.
    public static let glow = DesignToken.glow.color

    /// Signal — live green for active nodes, answer retrieval.
    public static let signal = DesignToken.signal.color

    /// Partial / warning amber for secondary accent nodes.
    public static let partial = DesignToken.partial.color

    /// Spec / inert — grid lines, idle tracks, not-yet-active structure.
    public static let spec = DesignToken.spec.color

    /// Foreground — readable ink on dark surfaces.
    public static let foreground = DesignToken.foreground.color

    /// Muted foreground — dimmed labels, inactive graph nodes.
    public static let mutedForeground = DesignToken.mutedForeground.color

    /// Border — the 1px hairline. Too dark for lines drawn at low opacity; use `spec`.
    public static let border = DesignToken.border.color

    /// Card — raised surface behind specimens.
    public static let card = DesignToken.card.color

    /// Popover — floating surface ground.
    public static let popover = DesignToken.popover.color

    // MARK: - Typography

    /// Font tokens matching the web HUD's type scale.
    public enum Font {
        /// Serif italic — for dream/thought text streams.
        public static func serifItalic(size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .medium, design: .serif).italic()
        }

        /// Monospace — for counts, data readouts, technical labels.
        public static func mono(size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }
    }
}
