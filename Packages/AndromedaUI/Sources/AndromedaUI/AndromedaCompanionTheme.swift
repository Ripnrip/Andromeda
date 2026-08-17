// AndromedaCompanionTheme.swift
//
// Bridge layer: maps the companion HUD's AndromedaTheme.* namespace to
// the canonical Color.andromeda* palette defined in AndromedaTheme.swift.
// The companion repo (Ripnrip/andromida-companion) was authored against a
// separate web-derived theme (primary/accent/signal/partial/foreground/
// mutedForeground/border/card/popover). This file keeps the companion
// files unmodified while routing every color through the canonical palette.
//
// Design decision: a thin enum with static Color properties, NOT a protocol
// or environment key. The companion scenes use `AndromedaTheme.primary`
// as concrete values, not injected dependencies — they're Canvas-drawn
// glyph art where theme-swapping isn't a runtime concern.

import SwiftUI

public enum AndromedaTheme {

    // MARK: - Core palette (maps to Color.andromeda*)

    /// Primary teal — the dominant color across all specimens and scenes.
    public static let primary = Color.andromedaTeal

    /// Accent glow — brighter highlight for halos, breathing glows, moon.
    public static let accent = Color.andromedaGlow

    /// Signal — success / live green for active nodes, answer retrieval.
    public static let signal = Color.andromedaLive

    /// Partial / warning amber for secondary accent nodes.
    public static let partial = Color.andromedaAmber

    /// Foreground — readable ink on dark surfaces.
    public static let foreground = Color.andromedaInk

    /// Muted foreground — dimmed labels, inactive graph nodes.
    public static let mutedForeground = Color.andromedaMuted

    /// Border — dividers, grid lines, track backgrounds.
    public static let border = Color.andromedaDim

    /// Card — raised surface behind specimens.
    public static let card = Color.andromedaPanel

    /// Popover — the dark fill used to "bite" the crescent moon.
    public static let popover = Color.andromedaVoid

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
