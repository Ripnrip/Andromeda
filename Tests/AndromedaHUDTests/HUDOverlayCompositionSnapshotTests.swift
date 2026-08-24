import XCTest
import SwiftUI
@testable import AndromedaHUDCore
@testable import MemoryKit
import SnapshotTesting

@MainActor
final class HUDOverlayCompositionSnapshotTests: XCTestCase {

    /// Simulates the FULL HUD composition on a 16" MacBook screen canvas:
    /// Full-screen translucent dimming + Andromeda Mountain overlay + search pill + results panel.
    func testHUDOverlayFullComposition() async {
        // Fake "desktop" wallpaper behind the HUD (simulated with a muted grid)
        let fakeDesktop = ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.08, blue: 0.2),
                    Color(red: 0.05, green: 0.1, blue: 0.25),
                    Color(red: 0.08, green: 0.15, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Simulated window blobs
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.35))
                .frame(width: 520, height: 360)
                .offset(x: -220, y: -140)
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.25))
                .frame(width: 420, height: 280)
                .offset(x: 200, y: 80)
        }
        .frame(width: 1440, height: 900)

        // The composed HUD scene: overlay + search + results
        let composed = fakeDesktop
            .overlay(alignment: .center) {
                HUDOverlayScene(
                    searchQuery: "memory",
                    mockOutcome: .recalled(hits: [
                        MemoryHit(
                            id: UUID(uuidString: "5F05DD60-1618-4263-9FD0-59F23DFF0E41")!,
                            memoryID: nil,
                            contentHash: nil,
                            narrative: "Hot-store result: Andromeda mountain shape design",
                            project: nil,
                            visibility: nil,
                            tags: [],
                            createdAt: nil,
                            path: nil,
                            source: .hotStore,
                            score: 10.0
                        ),
                        MemoryHit(
                            id: UUID(uuidString: "16CF62F7-869C-4FDA-8713-0539DA55B14D")!,
                            memoryID: nil,
                            contentHash: nil,
                            narrative: "Selected vault result: Perplexity onboarding reference",
                            project: "andromeda",
                            visibility: nil,
                            tags: [],
                            createdAt: nil,
                            path: nil,
                            source: .vault,
                            score: 8.0
                        )
                    ])
                )
            }
            .frame(width: 1440, height: 900)

        let vc = NSHostingController(rootView: composed)
        vc.view.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        SnapshotTesting.isRecording = true
        assertSnapshot(of: vc, as: .image(size: CGSize(width: 1440, height: 900)))
        SnapshotTesting.isRecording = false
    }

    /// Same composition but LIGHT MODE to show the overlay dimming effect.
    func testHUDOverlayFullCompositionLight() async {
        let fakeDesktop = ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.88, blue: 0.95),
                    Color(red: 0.85, green: 0.92, blue: 0.98),
                    Color(red: 0.9, green: 0.95, blue: 0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.7))
                .frame(width: 520, height: 360)
                .offset(x: -220, y: -140)
                .shadow(color: .black.opacity(0.08), radius: 20)
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.7))
                .frame(width: 420, height: 280)
                .offset(x: 200, y: 80)
                .shadow(color: .black.opacity(0.08), radius: 20)
        }
        .frame(width: 1440, height: 900)

        let composed = fakeDesktop
            .overlay(alignment: .center) {
                HUDOverlayScene(
                    searchQuery: "project.state",
                    mockOutcome: .projects(states: [
                        ProjectState(
                            id: ProjectStateID(rawValue: "andromeda"),
                            title: "Andromeda Control Plane",
                            status: .active,
                            items: [
                                ProjectStateItem(id: ProjectStateItemID(rawValue: "ship-hud"), title: "Ship magical HUD overlay", status: .active),
                                ProjectStateItem(id: ProjectStateItemID(rawValue: "await-pixels"), title: "Await macOS pixel review", status: .blocked),
                                ProjectStateItem(id: ProjectStateItemID(rawValue: "review"), title: "Review visual diff", status: .backlog)
                            ],
                            provenance: nil
                        )
                    ])
                )
                .environment(\.colorScheme, .light)
            }
            .frame(width: 1440, height: 900)

        let vc = NSHostingController(rootView: composed)
        vc.view.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        SnapshotTesting.isRecording = true
        assertSnapshot(of: vc, as: .image(size: CGSize(width: 1440, height: 900)))
        SnapshotTesting.isRecording = false
    }
}

/// A self-contained composite SwiftUI view that simulates what AppKit's HUDOverlayWindow
/// + HUDWindow would look like layered together on screen.  Built as pure SwiftUI so
/// SnapshotTesting can capture it in one go.
private struct HUDOverlayScene: View {
    let searchQuery: String
    let mockOutcome: HUDOutcome

    var body: some View {
        ZStack(alignment: .top) {
            // 1) Full-screen translucent dimming
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            // 2) THE ANDROMEDA MOUNTAIN - huge, glowing, blurred.
            //    Silhouette rises from BOTTOM of screen so its WIDE shoulders frame
            //    the floating HUD without any peak clipping the panels.
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
                .frame(width: 1500, height: 1000)
                .blur(radius: 85)
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
                        .frame(width: 1500, height: 1000)
                )
                .offset(y: 290)

            // Ambient glow orb for Perplexity-like beam effect (HUD sits on top of this)
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
                .frame(width: 960, height: 600)
                .offset(y: 120)
                .zIndex(5)

            // 3) The HUD stack: search pill + results panel (TOPMOST LAYER now)
            VStack(spacing: 12) {
                // Search pill mock (HUDView-like)
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.cyan)
                        .font(.system(size: 16, weight: .semibold))
                    Text(searchQuery)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("⌘⇧Space")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(.quaternary.opacity(0.6))
                        )
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                        )
                        .background(
                            SurrealBackgroundView().clipShape(Capsule())
                        )
                }
                .frame(width: 620)

                // HUDOutcomeView (actual component)
                HUDOutcomeView(
                    outcome: mockOutcome,
                    selectedIndex: 1
                )
                .frame(width: 620)
                .compositingGroup()
                .zIndex(10) // Guarantee results are above mountain
            }
            .padding(.top, 120)
            .zIndex(20) // Guarantee HUD is above mountain + orb
        }
    }
}
