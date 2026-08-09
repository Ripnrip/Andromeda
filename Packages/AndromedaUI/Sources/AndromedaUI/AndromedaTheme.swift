import SwiftUI

// MARK: - Palette

public extension Color {
    /// Deep-space backdrop.
    static let andromedaVoid  = Color(red: 0.012, green: 0.043, blue: 0.047)
    /// Panel / raised surface.
    static let andromedaPanel = Color(red: 0.016, green: 0.051, blue: 0.055)
    /// Primary accent.
    static let andromedaTeal  = Color(red: 0.204, green: 0.910, blue: 0.863)
    /// Bright highlight / glow.
    static let andromedaGlow  = Color(red: 0.561, green: 0.984, blue: 0.937)
    /// Success / live green.
    static let andromedaLive  = Color(red: 0.243, green: 0.878, blue: 0.549)
    /// Muted label.
    static let andromedaMuted = Color(red: 0.498, green: 0.639, blue: 0.620)
    /// Partial / warning amber — single declaration (was duplicated in ControlBar + MemoryKinds).
    static let andromedaAmber = Color(red: 0.910, green: 0.784, blue: 0.290)
    /// Spec / inert dim teal-gray.
    static let andromedaDim   = Color(red: 0.290, green: 0.427, blue: 0.408)
    /// Primary readable ink on dark surfaces (near-white cyan).
    static let andromedaInk   = Color(red: 0.918, green: 1.0, blue: 0.984)
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
            : Color(red: 0.925, green: 0.957, blue: 0.953)
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
