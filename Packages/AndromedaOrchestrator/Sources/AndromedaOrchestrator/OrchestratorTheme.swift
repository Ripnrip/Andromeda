import SwiftUI

// MARK: - Palette

//
// Built from the design tokens (`DesignToken`, held to DESIGN.md), so the console
// matches the website's `globals.css` theme for theme: `obsidian` is the dark
// set, `observatory` the light one. Five structural roles
// (void / panel / hairline / accent / foreground) plus the status hues.

public struct OrchestratorPalette: Sendable {
    public var void: Color
    public var chrome: Color
    public var panel: Color
    public var panelHi: Color
    public var hairline: Color
    public var ink: Color
    public var muted: Color
    public var dim: Color
    public var cyan: Color
    public var green: Color
    public var amber: Color
    public var red: Color

    /// Dark theme — DESIGN.md's dark tokens.
    public static let obsidian = OrchestratorPalette(tokens: \.dark)

    /// Light theme — DESIGN.md's `light-*` tokens.
    public static let observatory = OrchestratorPalette(tokens: \.light)

    public static func forScheme(_ scheme: ColorScheme) -> OrchestratorPalette {
        scheme == .light ? .observatory : .obsidian
    }
}

/// Declared in an extension so the memberwise initializer stays available.
extension OrchestratorPalette {
    /// Fills every role from its design token, reading one theme's values.
    /// The memberwise call is exhaustive, so a new role can't be left unmapped.
    init(tokens value: (DesignToken) -> UInt32) {
        func color(_ token: DesignToken) -> Color {
            Color(token: value(token))
        }
        self.init(
            void: color(.background),
            chrome: color(.popover),
            panel: color(.card),
            panelHi: color(.secondary),
            hairline: color(.border),
            ink: color(.foreground),
            muted: color(.mutedForeground),
            dim: color(.spec),
            cyan: color(.primary),
            green: color(.signal),
            amber: color(.partial),
            red: color(.alert)
        )
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = OrchestratorPalette.obsidian
}

public extension EnvironmentValues {
    var palette: OrchestratorPalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Installs the palette that matches the effective color scheme.
public struct PaletteReader: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    public func body(content: Content) -> some View {
        content.environment(\.palette, .forScheme(scheme))
    }
}

public extension View {
    func orchestratorPalette() -> some View {
        modifier(PaletteReader())
    }
}

// MARK: - Type

//
// Space Grotesk (sans) · Instrument Serif (editorial) · JetBrains Mono
// (IDs, capabilities, logs). Bundle the faces in Resources/Fonts and register
// them in the host app; the fallbacks keep previews honest until then.

public enum OrchestratorFont {
    public static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("SpaceGrotesk-Regular", size: size).weight(weight)
    }

    public static func editorial(_ size: CGFloat) -> Font {
        .custom("InstrumentSerif-Regular", size: size)
    }

    public static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom("JetBrainsMono-Regular", size: size).weight(weight)
    }

    /// Uppercase tracked label used for every section kicker.
    public static func kicker(_ size: CGFloat = 9) -> Font {
        mono(size, .semibold)
    }
}

// MARK: - Motion

//
// One curve for entrances so the whole console settles the same way, plus the
// ambient loops. Every call site pairs these with `reduceMotion`.

public enum OrchestratorMotion {
    /// The single entrance curve: rise, settle, no snap.
    public static let entrance = Animation.spring(duration: 0.66, bounce: 0.18)
    public static let settle = Animation.spring(duration: 0.42, bounce: 0.12)
    public static let breathe = Animation.easeInOut(duration: 2.9).repeatForever(autoreverses: true)
    public static let orbit = Animation.linear(duration: 11).repeatForever(autoreverses: false)
    public static let orbitReverse = Animation.linear(duration: 17).repeatForever(autoreverses: false)
    public static let pulse = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)

    /// Stagger delay for the nth row in a cascading group.
    public static func stagger(_ index: Int, step: Double = 0.055, base: Double = 0.05) -> Double {
        base + Double(index) * step
    }
}

// MARK: - Surface

public struct OrchestratorSurface: View {
    @Environment(\.palette) private var palette
    public init() {}
    public var body: some View {
        palette.void.overlay(alignment: .top) {
            RadialGradient(
                colors: [palette.cyan.opacity(0.08), .clear],
                center: .top, startRadius: 0, endRadius: 520
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// Standard panel treatment: 1px hairline, 13pt radius, panel fill.
public struct PanelBackground: ViewModifier {
    @Environment(\.palette) private var palette
    var radius: CGFloat
    var fill: Color?
    var border: Color?

    public func body(content: Content) -> some View {
        content
            .background(fill ?? palette.panel, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(border ?? palette.hairline, lineWidth: 1)
            }
    }
}

public extension View {
    func panel(radius: CGFloat = 13, fill: Color? = nil, border: Color? = nil) -> some View {
        modifier(PanelBackground(radius: radius, fill: fill, border: border))
    }
}

#Preview("Palette") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
            VStack(alignment: .leading, spacing: 8) {
                Text("Andromeda").font(OrchestratorFont.mono(11, .semibold))
                Text("orchestrator").font(OrchestratorFont.editorial(22))
            }
            .padding(20)
            .frame(width: 200, height: 120, alignment: .leading)
            .background(OrchestratorPalette.forScheme(scheme).void)
            .foregroundStyle(OrchestratorPalette.forScheme(scheme).ink)
            .environment(\.colorScheme, scheme)
        }
    }
    .fixedSize()
}
