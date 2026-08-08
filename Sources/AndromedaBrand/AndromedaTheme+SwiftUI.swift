/**
 * 🪟 AndromedaTheme — SwiftUI bindings for the shared palette.
 *
 * The macOS surfaces (Home, HUD, menu bar item, floating command center) read
 * colour from here rather than from `Color.cyan` / `Color.green` so they match
 * the website and the TUI exactly. Dark-only by construction: the design system
 * has no light palette.
 */

#if canImport(SwiftUI)
import SwiftUI

public extension Color {
    /// Build a SwiftUI colour from a brand token.
    init(brand token: BrandColor) {
        let rgb = token.components
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

public enum AndromedaTheme {
    public static let background = Color(brand: AndromedaPalette.background)
    public static let foreground = Color(brand: AndromedaPalette.foreground)
    public static let card = Color(brand: AndromedaPalette.card)
    public static let popover = Color(brand: AndromedaPalette.popover)
    public static let muted = Color(brand: AndromedaPalette.muted)
    public static let mutedForeground = Color(brand: AndromedaPalette.mutedForeground)
    public static let secondaryForeground = Color(brand: AndromedaPalette.secondaryForeground)
    public static let border = Color(brand: AndromedaPalette.border)
    public static let input = Color(brand: AndromedaPalette.input)
    public static let primary = Color(brand: AndromedaPalette.primary)
    public static let primaryForeground = Color(brand: AndromedaPalette.primaryForeground)
    public static let accent = Color(brand: AndromedaPalette.accent)

    public static let shipped = Color(brand: AndromedaPalette.shipped)
    public static let signal = Color(brand: AndromedaPalette.signal)
    public static let partial = Color(brand: AndromedaPalette.partial)
    public static let spec = Color(brand: AndromedaPalette.spec)

    /// `--radius`, 14 pt.
    public static let cornerRadius: CGFloat = CGFloat(AndromedaPalette.radius)

    public static func color(for status: BrandStatus) -> Color {
        Color(brand: status.color)
    }

    /// Machine-truth type: capability IDs, paths, status words, IDs.
    public static func mono(_ style: Font.TextStyle = .callout, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }

    /// Editorial display type for headline emphasis.
    public static func display(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif)
    }
}

/// Status chip shared by every macOS surface: coloured dot plus its mono word,
/// so state is never communicated by colour alone.
public struct AndromedaStatusChip: View {
    public let status: BrandStatus

    public init(status: BrandStatus) {
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AndromedaTheme.color(for: status))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(status.word)
                .font(AndromedaTheme.mono(.caption2, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(AndromedaTheme.color(for: status))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(AndromedaTheme.color(for: status).opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status \(status.word)")
    }
}
#endif
