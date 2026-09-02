import SwiftUI

// MARK: - Palette
//
// Derived 1:1 from the console's CSS custom properties, which in turn come
// from `web/app/globals.css`. Both schemes are first-class: light is a real
// counterpart, not a washed-out dark. Five structural tokens
// (void / panel / hairline / accent / foreground) plus three status hues.

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

    public static let obsidian = OrchestratorPalette(
        void:     Color(red: 0.035, green: 0.067, blue: 0.078),
        chrome:   Color(red: 0.047, green: 0.082, blue: 0.094),
        panel:    Color(red: 0.059, green: 0.098, blue: 0.114),
        panelHi:  Color(red: 0.102, green: 0.149, blue: 0.169),
        hairline: Color(red: 0.165, green: 0.227, blue: 0.247),
        ink:      Color(red: 0.914, green: 0.957, blue: 0.957),
        muted:    Color(red: 0.588, green: 0.651, blue: 0.663),
        dim:      Color(red: 0.522, green: 0.588, blue: 0.620),
        cyan:     Color(red: 0.204, green: 0.910, blue: 0.863),
        green:    Color(red: 0.243, green: 0.878, blue: 0.549),
        amber:    Color(red: 0.910, green: 0.784, blue: 0.290),
        red:      Color(red: 0.930, green: 0.380, blue: 0.350)
    )

    public static let observatory = OrchestratorPalette(
        void:     Color(red: 0.933, green: 0.953, blue: 0.949),
        chrome:   Color(red: 0.973, green: 0.984, blue: 0.980),
        panel:    Color(red: 0.988, green: 0.996, blue: 0.992),
        panelHi:  Color(red: 0.886, green: 0.910, blue: 0.906),
        hairline: Color(red: 0.804, green: 0.835, blue: 0.831),
        ink:      Color(red: 0.106, green: 0.169, blue: 0.188),
        muted:    Color(red: 0.325, green: 0.400, blue: 0.416),
        dim:      Color(red: 0.435, green: 0.510, blue: 0.525),
        cyan:     Color(red: 0.000, green: 0.518, blue: 0.502),
        green:    Color(red: 0.000, green: 0.502, blue: 0.290),
        amber:    Color(red: 0.545, green: 0.400, blue: 0.043),
        red:      Color(red: 0.694, green: 0.196, blue: 0.157)
    )

    public static func forScheme(_ scheme: ColorScheme) -> OrchestratorPalette {
        scheme == .light ? .observatory : .obsidian
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
    func orchestratorPalette() -> some View { modifier(PaletteReader()) }
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
    public static func kicker(_ size: CGFloat = 9) -> Font { mono(size, .semibold) }
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
