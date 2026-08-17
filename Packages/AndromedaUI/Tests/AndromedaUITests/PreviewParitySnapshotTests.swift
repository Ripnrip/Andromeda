import XCTest
import SwiftUI
import SnapshotTesting
@testable import AndromedaUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Xcode-preview parity: every `#Preview` state in the package has a
/// snapshot twin here, so the canvas grid and the recorded baseline matrix
/// can never drift apart. A new preview state without a baseline fails the
/// catalogue review, not a user's screen.
///
/// Surfaces covered here that no other suite touches: the floating control
/// bar, pillar cards, the memory-recall family, kit primitives, brand marks,
/// and the full `StatusBadge` state matrix.
///
/// Record: `SNAPSHOT_TESTING_RECORD=1 swift test --filter PreviewParitySnapshotTests`
/// (CI: tip the PR head with `[record-snapshots]`; baselines are runner-image-bound.)
@MainActor
final class PreviewParitySnapshotTests: XCTestCase {

    override func invokeTest() {
        withSnapshotTesting(record: AndromedaUISnapshotSupport.recordMode) {
            super.invokeTest()
        }
    }

    private func verify(
        _ view: some View,
        _ size: CGSize,
        name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) throws {
        try AndromedaUISnapshotSupport.requireBaselines(file: file)
        for dark in [true, false] {
            let host = SnapshotHosting.makeHost(view, size, dark: dark)
            assertSnapshot(
                of: host,
                as: .image(precision: 0.98, perceptualPrecision: 0.96),
                named: "\(name)-\(dark ? "dark" : "light")",
                file: file,
                testName: testName,
                line: line
            )
        }
    }

    private func shell<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        ZStack { AndromedaSurface(); content() }
    }

    // MARK: - Floating bar (menu-bar accessory content)

    // `AndromedaBarContent` is declared inside `#if os(macOS)` (the whole
    // FloatingBarPanel file is AppKit-bound) while the package advertises
    // iOS/tvOS/watchOS — an unguarded reference breaks every non-macOS build.
    #if os(macOS)
    func testFloatingBarContent() throws {
        try verify(shell { AndromedaBarContent() }, CGSize(width: 640, height: 64), name: "floating-bar")
    }
    #endif

    func testHUDCoreGlyph() throws {
        try verify(shell { HUDCoreGlyph(size: 40) }, CGSize(width: 120, height: 120), name: "hud-core-glyph")
    }

    func testBorderBeam() throws {
        let beamed = RoundedRectangle(cornerRadius: 20)
            .fill(Color.andromedaPanel)
            .frame(width: 180, height: 90)
            .modifier(BorderBeam())
        try verify(shell { beamed }, CGSize(width: 220, height: 130), name: "border-beam")
    }

    // MARK: - Pillar cards (six-pillar control plane)

    func testPillarCards() throws {
        let grid = VStack(spacing: 12) {
            HStack(spacing: 12) {
                PillarCard(
                    title: "MCP host",
                    subtitle: "One roster behind capability IDs",
                    badge: "advancing",
                    badgeTone: .partial,
                    note: "PR #46 · AndromedaMCP"
                ) {
                    Text("code.search · code.replace")
                        .font(AndromedaFont.mono(11))
                        .foregroundStyle(Color.andromedaMuted)
                }
                PillarCard(
                    title: "Memory · Anima",
                    subtitle: "Graph + vector fabric",
                    badge: "live",
                    badgeTone: .live,
                    note: "MemoryKit curtain"
                ) {
                    Text("recall · vault-sync")
                        .font(AndromedaFont.mono(11))
                        .foregroundStyle(Color.andromedaMuted)
                }
            }
            HStack(spacing: 12) {
                PillarCard(
                    title: "Skills registry",
                    subtitle: "Centralized discovery",
                    badge: "specified",
                    badgeTone: .specified,
                    note: "HAB-39"
                ) {
                    Text("mirror-across-hosts ends")
                        .font(AndromedaFont.mono(11))
                        .foregroundStyle(Color.andromedaMuted)
                }
                PillarCard(
                    title: "Secrets broker",
                    subtitle: "Keychain-backed brokerage",
                    badge: "unshipped",
                    badgeTone: .dim,
                    note: "no secrets in config"
                ) {
                    Text("Keychain curtain")
                        .font(AndromedaFont.mono(11))
                        .foregroundStyle(Color.andromedaMuted)
                }
            }
        }
        .padding(20)
        try verify(ZStack { AndromedaSurface(); grid }, CGSize(width: 640, height: 320), name: "pillar-cards")
    }

    // MARK: - Pillar previews (parity twins for AndromedaPillars.swift previews)

    /// Twin of `#Preview("Pillars showcase · dark/light")` — the actual
    /// preview root, not generic cards, so specialized pillar cards cannot
    /// drift without failing the parity guarantee.
    func testPillarsShowcasePreviewRoot() throws {
        try verify(
            AndromedaPillarsShowcase().frame(width: 1160, height: 980),
            CGSize(width: 1160, height: 980),
            name: "pillars-showcase"
        )
    }

    /// Twin of `#Preview("Pillar cards")` — the two specialized cards the
    /// preview actually renders.
    func testSpecializedPillarCardsPreviewRoot() throws {
        let stack = VStack(spacing: 12) {
            LLMProxyPillarCard()
            RetrievalBenchPillarCard()
        }
        .frame(width: 420)
        try verify(shell { stack }, CGSize(width: 460, height: 640), name: "specialized-pillar-cards")
    }

    func testStatusBadgeMatrix() throws {
        // Every honesty state, one canvas — a palette drift in any tone
        // shows up next to its siblings.
        let row = HStack(spacing: 10) {
            ForEach(PillarStatus.allCases, id: \.rawValue) { status in
                StatusBadge(status)
            }
        }
        .padding(16)
        try verify(shell { row }.frame(width: 420, height: 70), CGSize(width: 420, height: 70), name: "status-badge-matrix")
    }

    // MARK: - Kit primitives

    /// Twin of `#Preview("Gallery · Dark/Light")` — the gallery root itself,
    /// so grid layout, labels, and specimen ordering cannot drift without
    /// failing the parity guarantee. The catalogue test checks membership;
    /// this checks the rendered whole.
    func testGalleryPreviewRoot() throws {
        try verify(
            AndromedaGallery().frame(width: 1000, height: 2400),
            CGSize(width: 1000, height: 2400),
            name: "gallery-root"
        )
    }

    func testKitPrimitives() throws {
        let kit = VStack(alignment: .leading, spacing: 14) {
            Eyebrow("control plane")
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Glass surface").font(AndromedaFont.ui(14, .semibold))
                    Text("Content on the glass card reads ink on void.")
                        .font(AndromedaFont.ui(12))
                        .foregroundStyle(Color.andromedaMuted)
                }
            }
            .frame(width: 260)
            HStack(spacing: 10) {
                SegTab(label: "Memory", active: true) {}
                SegTab(label: "Models", active: false) {}
                SegTab(label: "Health", active: false) {}
            }
            AddButton(label: "Add MCP server") {}
        }
        .padding(20)
        try verify(shell { kit }, CGSize(width: 340, height: 300), name: "kit-primitives")
    }

    // MARK: - Brand marks

    func testBrandMarks() throws {
        let marks = HStack(spacing: 24) {
            AndromedaLogo(size: 40)
            AndromedaCore(size: 40)
            HUDCoreGlyph(size: 40)
        }
        .padding(20)
        try verify(shell { marks }, CGSize(width: 200, height: 100), name: "brand-marks")
    }

    // MARK: - Memory recall family

    func testMemoryRecallControl() throws {
        try verify(
            shell { MemoryRecallControl() }.padding(16),
            CGSize(width: 320, height: 260),
            name: "memory-recall"
        )
    }

    func testRecallSkeletonRow() throws {
        try verify(
            shell { RecallSkeletonRow(width: 150) }.padding(12),
            CGSize(width: 190, height: 60),
            name: "recall-skeleton"
        )
    }

    func testMemoryPulse() throws {
        try verify(
            shell {
                ZStack { MemoryPulse(trigger: true); Circle().fill(Color.andromedaTeal).frame(width: 12, height: 12) }
            }.padding(12),
            CGSize(width: 120, height: 120),
            name: "memory-pulse"
        )
    }
}
