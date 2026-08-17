import XCTest
import SwiftUI
import SnapshotTesting
@testable import AndromedaUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Companion HUD Motion + Dream/Memory scene snapshots from the
/// andromida-companion repo (Ripnrip/andromida-companion).
///
/// All companion animations are driven by `TimelineView(.animation)` with
/// real-time math, making them fundamentally non-deterministic across runs.
/// These tests record baselines for visual reference in PR reviews but
/// skip verification to avoid flaky CI failures.
///
/// When these animations are later gated behind `andromedaLoop` (frozen
/// mode), they can be promoted to deterministic regression tests.
///
/// Record: `SNAPSHOT_TESTING_RECORD=1 swift test --filter CompanionSnapshotTests`
@MainActor
final class CompanionSnapshotTests: XCTestCase {

    override func invokeTest() {
        withSnapshotTesting(record: AndromedaUISnapshotSupport.recordMode) {
            super.invokeTest()
        }
    }

    // MARK: - Snapshot helper (record-only)

    private func capture(
        _ view: some View,
        _ size: CGSize,
        name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) throws {
        // Only run in explicit record mode — skip during normal test runs.
        // These baselines are visual references for PR reviews, not regression
        // gates, because TimelineView(.animation) is non-deterministic.
        let recordEnv = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let isRecord = recordEnv == "all" || recordEnv == "1" || recordEnv == "true" || recordEnv == "yes"
        guard isRecord else {
            throw XCTSkip("Record-only baseline — visual reference, not a regression gate")
        }
        for dark in [true, false] {
            let host = makeHost(view, size, dark: dark)
            assertSnapshot(
                of: host,
                as: .image(precision: 0.80, perceptualPrecision: 0.75),
                named: "\(name)-\(dark ? "dark" : "light")",
                file: file,
                testName: testName,
                line: line
            )
        }
    }

    // MARK: - HUD Motion primitives (11)

    func testWaveform() throws {
        try capture(AndromedaWaveform(bars: 4, height: 14), CGSize(width: 100, height: 40), name: "waveform")
    }

    func testShimmerSweep() throws {
        try capture(AndromedaShimmerSweep().frame(width: 160, height: 40), CGSize(width: 160, height: 40), name: "shimmer-sweep")
    }

    func testOrbitDots() throws {
        try capture(AndromedaOrbitDots(size: 36, dots: 3), CGSize(width: 60, height: 60), name: "orbit-dots")
    }

    func testParticleDrift() throws {
        try capture(AndromedaParticleDrift(count: 7).frame(width: 160, height: 80), CGSize(width: 160, height: 80), name: "particle-drift")
    }

    func testBreathingGlow() throws {
        try capture(AndromedaBreathingGlow().frame(width: 60, height: 60), CGSize(width: 60, height: 60), name: "breathing-glow")
    }

    func testRippleRings() throws {
        try capture(AndromedaRippleRings(rings: 2).frame(width: 60, height: 60), CGSize(width: 60, height: 60), name: "ripple-rings")
    }

    func testMarchingSignal() throws {
        try capture(AndromedaMarchingSignal(count: 3), CGSize(width: 100, height: 30), name: "marching-signal")
    }

    func testRotatingRing() throws {
        try capture(AndromedaRotatingRing().frame(width: 44, height: 44), CGSize(width: 44, height: 44), name: "rotating-ring")
    }

    func testVectorGrid() throws {
        try capture(AndromedaVectorGrid(cols: 5, rows: 3), CGSize(width: 140, height: 80), name: "vector-grid")
    }

    func testTokenStream() throws {
        try capture(AndromedaTokenStream(count: 5), CGSize(width: 120, height: 30), name: "token-stream")
    }

    func testProgressFill() throws {
        try capture(AndromedaProgressFill().frame(width: 140, height: 12), CGSize(width: 140, height: 12), name: "progress-fill")
    }

    // MARK: - Dream / Memory Canvas scenes (7)

    func testDreamField() throws {
        try capture(AndromedaDreamField().frame(width: 280, height: 168), CGSize(width: 280, height: 168), name: "dream-field")
    }

    func testRemWave() throws {
        try capture(AndromedaRemWave().frame(width: 280, height: 168), CGSize(width: 280, height: 168), name: "rem-wave")
    }

    func testBraidMerge() throws {
        try capture(AndromedaBraidMerge().frame(width: 280, height: 168), CGSize(width: 280, height: 168), name: "braid-merge")
    }

    func testEngramTimeline() throws {
        try capture(AndromedaEngramTimeline().frame(width: 280, height: 168), CGSize(width: 280, height: 168), name: "engram-timeline")
    }

    func testConstellationGraph() throws {
        try capture(AndromedaConstellationGraph().frame(width: 280, height: 168), CGSize(width: 280, height: 168), name: "constellation-graph")
    }

    func testCrystalForm() throws {
        try capture(AndromedaCrystalForm().frame(width: 280, height: 168), CGSize(width: 280, height: 168), name: "crystal-form")
    }

    func testRecallPulse() throws {
        try capture(AndromedaRecallPulse().frame(width: 280, height: 168), CGSize(width: 280, height: 168), name: "recall-pulse")
    }

    // MARK: - Host helpers

    #if canImport(UIKit)
    private func makeHost(_ view: some View, _ size: CGSize, dark: Bool) -> UIViewController {
        let vc = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
        vc.view.frame = CGRect(origin: .zero, size: size)
        vc.overrideUserInterfaceStyle = dark ? .dark : .light
        return vc
    }
    #elseif canImport(AppKit)
    private func makeHost(_ view: some View, _ size: CGSize, dark: Bool) -> NSViewController {
        let themed = view
            .environment(\.colorScheme, dark ? ColorScheme.dark : ColorScheme.light)
            .frame(width: size.width, height: size.height)
        let vc = NSHostingController(rootView: AnyView(themed))
        vc.view.frame = CGRect(origin: .zero, size: size)
        vc.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        return vc
    }
    #endif
}
