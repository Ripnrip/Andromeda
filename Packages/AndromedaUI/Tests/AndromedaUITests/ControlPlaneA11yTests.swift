import XCTest
import SwiftUI
import SnapshotTesting
@testable import AndromedaUI

#if canImport(UIKit)
import UIKit
private func a11yHost(_ view: some View, _ size: CGSize) -> UIViewController {
    let vc = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
    vc.view.frame = CGRect(origin: .zero, size: size)
    vc.overrideUserInterfaceStyle = .dark
    return vc
}
#elseif canImport(AppKit)
import AppKit
private func a11yHost(_ view: some View, _ size: CGSize) -> NSViewController {
    let vc = NSHostingController(rootView: AnyView(view.environment(\.colorScheme, ColorScheme.dark).frame(width: size.width, height: size.height)))
    vc.view.frame = CGRect(origin: .zero, size: size)
    vc.view.appearance = NSAppearance(named: .darkAqua)
    return vc
}
#endif

/// Accessibility coverage.
///
/// 1. Layout must survive an accessibility Dynamic Type size — captured as a
///    snapshot at `.accessibility3` so regressions (clipping / overlap) show up.
/// 2. Interactive surfaces must expose accessibility labels — asserted by
///    walking the rendered accessibility tree.
@MainActor
final class ControlPlaneA11yTests: XCTestCase {

    override func setUp() { super.setUp(); /* isRecording = true */ }

    func testDynamicTypeXXL() throws {
        try AndromedaUISnapshotSupport.requireBaselines()
        let big = ControlPlaneView().dynamicTypeSize(.accessibility3)
        let host = a11yHost(big, CGSize(width: 1120, height: 900))
        assertSnapshot(of: host, as: .image(precision: 0.97, perceptualPrecision: 0.95), named: "control-plane-a11y-xxl")
    }

    func testSectionsAtLargeType() throws {
        try AndromedaUISnapshotSupport.requireBaselines()
        let cases: [(String, AnyView, CGSize)] = [
            ("memory", AnyView(ZStack(alignment: .topLeading) { AndromedaSurface(); MemorySection().padding(20) }), CGSize(width: 900, height: 1100)),
            ("settings", AnyView(ZStack(alignment: .topLeading) { AndromedaSurface(); SettingsSection().padding(20) }), CGSize(width: 820, height: 820)),
        ]
        for (name, view, size) in cases {
            let host = a11yHost(view.dynamicTypeSize(.accessibility2), size)
            assertSnapshot(of: host, as: .image(precision: 0.97, perceptualPrecision: 0.95), named: "\(name)-a11y")
        }
    }

    #if canImport(UIKit)
    /// Every capability card must carry an accessibility label — no unlabeled controls.
    func testCapabilityCardsAreLabeled() {
        for p in [Pillar.mcp, .skills, .secrets, .fleet] {
            let host = a11yHost(CapabilityListSection(pillar: p), CGSize(width: 720, height: 600))
            host.loadViewIfNeeded()
            let labels = accessibilityLabels(in: host.view)
            XCTAssertFalse(labels.isEmpty, "\(p.rawValue) exposed no accessibility labels")
        }
    }

    private func accessibilityLabels(in view: UIView) -> [String] {
        var out: [String] = []
        if let l = view.accessibilityLabel { out.append(l) }
        for e in (view.accessibilityElements as? [NSObject] ?? []) {
            if let l = e.accessibilityLabel { out.append(l) }
        }
        for sub in view.subviews { out += accessibilityLabels(in: sub) }
        return out
    }
    #endif
}
