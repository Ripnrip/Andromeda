import SwiftUI

// MARK: - The real Andromeda logo (bundled raster)
// The organic tri-lobed aurora mark, shipped as a package resource so the
// glyph is pixel-accurate. Falls back to the geometric `AndromedaMark`.

public struct AndromedaLogo: View {
    public var size: CGFloat
    public init(size: CGFloat = 24) { self.size = size }
    public var body: some View {
        if let img = Self.image {
            img.resizable().scaledToFit().frame(width: size, height: size)
                .shadow(color: .andromedaTeal.opacity(0.6), radius: size * 0.14)
                .accessibilityLabel("Andromeda")
        } else {
            AndromedaMark().fill(Color.andromedaTeal)
                .overlay(AndromedaMark().scale(0.5).fill(Color.andromedaVoid.opacity(0.55)))
                .frame(width: size, height: size)
                .accessibilityLabel("Andromeda")
        }
    }

    static let image: Image? = {
        #if canImport(UIKit)
        if let ui = UIImage(named: "andromeda-logo", in: .module, with: nil) { return Image(uiImage: ui) }
        #elseif canImport(AppKit)
        if let ns = Bundle.module.image(forResource: "andromeda-logo") { return Image(nsImage: ns) }
        #endif
        return nil
    }()
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#Preview("Logo") { SchemePair { AndromedaLogo(size: 64) } }
