import SwiftUI

// MARK: - Typography
// Andromeda uses three families: Instrument Serif (display), Space Grotesk
// (UI/body), JetBrains Mono (ids, metrics, code). Bundle the .ttf files as
// package resources to render exactly; otherwise these fall back gracefully.

public enum AndromedaFont {
    public static func serif(_ size: CGFloat) -> Font { .custom("Instrument Serif", size: size) }
    public static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Space Grotesk", size: size).weight(weight)
    }
    public static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
}

/// Named text roles so every surface shares one type scale.
public extension View {
    func cpDisplay(_ size: CGFloat = 27) -> some View { font(AndromedaFont.serif(size)) }
    func cpTitle() -> some View { font(AndromedaFont.ui(14, .medium)) }
    func cpBody() -> some View { font(AndromedaFont.ui(13)) }
    func cpMeta() -> some View { font(AndromedaFont.mono(11)) }
    func cpLabel() -> some View { font(AndromedaFont.mono(10)).textCase(.uppercase) }
}

/// Eyebrow label used above section titles / group headers.
public struct Eyebrow: View {
    public var text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased())
            .font(AndromedaFont.mono(10))
            .tracking(2)
            .foregroundStyle(Color.andromedaMuted)
    }
}
