import AppKit
import SwiftUI
import AndromedaHUDCore

/// Full-screen translucent overlay layer that sits behind the floating HUD panels.
///
/// Inspired by Perplexity's onboarding backdrop: dims the workspace, reveals a
/// massive glowing Andromeda Mountain silhouette rising from below, and blooms
/// a soft cyan→purple ambient beam from behind the search pill area.
class HUDOverlayWindow: NSWindow {
    init() {
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        super.init(
            contentRect: screenRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.level = .statusBar - 1 // Just below the HUD capsule window
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let overlayView = NSHostingView(rootView: HUDOverlayBackdropScene())
        self.contentView = overlayView
    }
}

/// Rendered contents of the full-screen HUD backdrop overlay.
///
/// Z-order from back to front:
///   1. 55% black dimming wash (dim user's real desktop)
///   2. 1500×1000 heavily-blurred Andromeda Mountain silhouette
///      with a cyan→purple→deep-indigo gradient fill and soft stroke outline
///   3. Radial cyan→purple glow orb (centered ~1/3 from top) that
///      creates the Perplexity-style "beam bloom" behind the search pill
///
/// Layering is intentionally atmospheric-only: no mountain peak rises
/// above the floating HUD panels, so result-list text is never clipped.
private struct HUDOverlayBackdropScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // 1) Full-screen dimming wash so your workspace recedes
                Color.black.opacity(reduceMotion ? 0.35 : 0.55)
                    .ignoresSafeArea()

                // 2) ANDROMEDA MOUNTAIN — the alien peak seen from space.
                //    Sits low enough that the mountain's "shoulders" frame the
                //    HUD from below without any silhouette clipping the panels.
                AndromedaMountainShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.8, blue: 0.9).opacity(0.5),
                                Color(red: 0.4, green: 0.2, blue: 0.9).opacity(0.32),
                                Color(red: 0.1, green: 0.3, blue: 0.6).opacity(0.15),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: geo.size.width * 1.05, height: geo.size.height * 1.1)
                    .blur(radius: reduceMotion ? 55 : 85)
                    .overlay(
                        AndromedaMountainShape()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.cyan.opacity(0.38),
                                        Color.purple.opacity(0.22),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.3
                            )
                            .blur(radius: 6)
                            .frame(width: geo.size.width * 1.05, height: geo.size.height * 1.1)
                    )
                    .offset(y: geo.size.height * 0.32) // rise from the lower portion
                    .offset(y: drift ? -12 : 0) // slow, almost imperceptible breathing
                    .animation(
                        .easeInOut(duration: 9.0).repeatForever(autoreverses: true),
                        value: drift
                    )

                // 3) Ambient glow orb — the Perplexity-style beam bloom
                //    that sits directly behind the HUD's search capsule.
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.cyan.opacity(0.5),
                                Color.purple.opacity(0.2),
                                .clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 460
                        )
                    )
                    .frame(width: min(960, geo.size.width * 0.67), height: 600)
                    .offset(y: geo.size.height * 0.13) // yoke to HUD area
                    .blur(radius: 10)
                    .opacity(drift ? 1.0 : 0.72) // slow, subtle pulsing
                    .animation(
                        .easeInOut(duration: 6.0).repeatForever(autoreverses: true),
                        value: drift
                    )
                    .zIndex(5)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            drift = true
        }
    }
}
