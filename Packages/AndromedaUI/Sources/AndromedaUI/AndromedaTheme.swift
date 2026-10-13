import SwiftUI

// MARK: - Palette

/// The package's historical colour names, each now a `DesignToken` — call sites keep
/// their names, every value comes from DESIGN.md. New code may use `DesignToken`
/// directly.
public extension Color {
    /// Deep-space backdrop → `background`.
    static let andromedaVoid  = DesignToken.background.color
    /// Panel / raised surface → `card`.
    static let andromedaPanel = DesignToken.card.color
    /// Primary accent → `primary`.
    static let andromedaTeal  = DesignToken.primary.color
    /// Bright highlight / glow → `glow`.
    static let andromedaGlow  = DesignToken.glow.color
    /// Success / live green → `signal`.
    static let andromedaLive  = DesignToken.signal.color
    /// Muted label → `muted-foreground`.
    static let andromedaMuted = DesignToken.mutedForeground.color
    /// Partial / warning amber → `partial`.
    static let andromedaAmber = DesignToken.partial.color
    /// Spec / inert / idle → `spec`.
    static let andromedaDim   = DesignToken.spec.color
    /// Primary readable ink on dark surfaces → `foreground`.
    static let andromedaInk   = DesignToken.foreground.color
}

// MARK: - Timing tokens

/// The five canonical timing curves. Every specimen composes from these so
/// captures loop cleanly and the whole system shares one motion language.
public enum Motion {
    public static let pulse   = Animation.easeInOut(duration: 1.2).repeatForever()
    public static let breathe = Animation.easeInOut(duration: 1.6).repeatForever()
    public static let orbit   = Animation.linear(duration: 7).repeatForever(autoreverses: false)
    public static let sweep   = Animation.linear(duration: 2).repeatForever(autoreverses: false)
    public static let wave    = Animation.easeInOut(duration: 0.5).repeatForever()

    /// Convenience spring in the Andromeda idiom.
    public static func spring(_ bounce: Double = 0.5, _ duration: Double = 0.5) -> Animation {
        .spring(duration: duration, bounce: bounce)
    }
}

// MARK: - Surface

/// Theme-aware backdrop: the deep-space void in dark mode, a pale
/// observatory slate in light mode, both washed with a faint teal glow.
public struct AndromedaSurface: View {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        let base = scheme == .dark
            ? Color.andromedaVoid
            : DesignToken.lightBackground.color
        base.overlay(
            RadialGradient(
                colors: [Color.andromedaTeal.opacity(scheme == .dark ? 0.10 : 0.16), .clear],
                center: .center, startRadius: 4, endRadius: 160
            )
        )
    }
}

// MARK: - Preview / snapshot helpers

/// A single specimen framed on the Andromeda surface — the standard
/// preview and snapshot canvas (220×170).
public struct AndromedaStage<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    public var body: some View {
        ZStack { AndromedaSurface(); content }
            .frame(width: 220, height: 170)
    }
}

/// Renders a specimen twice, side by side, in dark and light — used by
/// every `#Preview` so both variants are visible in the Xcode canvas.
public struct SchemePair<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    public var body: some View {
        HStack(spacing: 0) {
            AndromedaStage { content }.environment(\.colorScheme, .dark)
            AndromedaStage { content }.environment(\.colorScheme, .light)
        }
        .fixedSize()
    }
}
