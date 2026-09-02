import SwiftUI

// MARK: - The mark

//
// Andromeda's mark is an angular trefoil — a triangle with softened vertices
// reading as an obscured diamond. It is never a circle. Every orbital, loader,
// HUD core, and status bloom in the product uses this silhouette.
//
// Path ported verbatim from the console's 100×100 viewBox.

public struct AndromedaTrefoil: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 100
        let ox = rect.minX + (rect.width - 100 * scale) / 2
        let oy = rect.minY + (rect.height - 100 * scale) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * scale, y: oy + y * scale)
        }

        var path = Path()
        path.move(to: p(56.86, 17.88))
        path.addLine(to: p(81.24, 60.12))
        path.addQuadCurve(to: p(74.38, 72), control: p(88.10, 72))
        path.addLine(to: p(25.62, 72))
        path.addQuadCurve(to: p(18.76, 60.12), control: p(11.90, 72))
        path.addLine(to: p(43.14, 17.88))
        path.addQuadCurve(to: p(56.86, 17.88), control: p(50, 6))
        path.closeSubpath()
        return path
    }
}

/// The living mark: a bloom, two counter-rotating trefoil rings, and the
/// bundled glyph breathing at the centre. Honors Reduce Motion by holding
/// a still, fully-formed frame.
public struct AndromedaMarkView: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var size: CGFloat
    public var tint: Color?

    @State private var spin = false
    @State private var breathing = false

    public init(size: CGFloat = 96, tint: Color? = nil) {
        self.size = size
        self.tint = tint
    }

    private var accent: Color {
        tint ?? palette.cyan
    }

    public var body: some View {
        ZStack {
            AndromedaTrefoil()
                .fill(accent.opacity(0.16))
                .scaleEffect(breathing ? 1.22 : 0.9)
                .opacity(breathing ? 0.06 : 0.34)

            AndromedaTrefoil()
                .stroke(accent.opacity(0.5), style: .init(lineWidth: 2.4, lineJoin: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))

            AndromedaTrefoil()
                .stroke(accent.opacity(0.24), style: .init(lineWidth: 1.4, lineJoin: .round, dash: [7, 9]))
                .padding(size * 0.08)
                .rotationEffect(.degrees(spin ? -360 : 0))

            glyph
                .frame(width: size * 0.62, height: size * 0.62)
                .scaleEffect(breathing ? 1.04 : 0.97)
                .shadow(color: accent.opacity(0.55), radius: size * 0.05)
        }
        .frame(width: size, height: size)
        .task {
            guard !reduceMotion else { return }
            withAnimation(OrchestratorMotion.orbit) { spin = true }
            withAnimation(OrchestratorMotion.breathe) { breathing = true }
        }
        .accessibilityLabel("Andromeda")
    }

    @ViewBuilder private var glyph: some View {
        if let image = Self.bundledMark {
            image.resizable().scaledToFit()
        } else {
            AndromedaTrefoil()
                .fill(accent)
                .overlay {
                    AndromedaTrefoil()
                        .scale(0.5)
                        .fill(palette.void.opacity(0.55))
                }
        }
    }

    /// `Resources/andromeda-mark.png` — the pixel-accurate trefoil.
    static let bundledMark: Image? = {
        #if canImport(UIKit)
            if let img = UIImage(named: "andromeda-mark", in: .module, with: nil) {
                return Image(uiImage: img)
            }
        #elseif canImport(AppKit)
            if let img = Bundle.module.image(forResource: "andromeda-mark") {
                return Image(nsImage: img)
            }
        #endif
        return nil
    }()
}

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#Preview("Mark") {
    HStack(spacing: 24) {
        AndromedaMarkView(size: 120)
        AndromedaMarkView(size: 56)
        AndromedaMarkView(size: 28)
    }
    .padding(40)
    .background(OrchestratorPalette.obsidian.void)
    .orchestratorPalette()
}
