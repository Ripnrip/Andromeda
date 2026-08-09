import XCTest
import SwiftUI
import SnapshotTesting
@testable import AndromedaUI

#if canImport(UIKit)
import UIKit
private func makeHost(_ view: some View, _ size: CGSize, dark: Bool) -> UIViewController {
    let vc = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
    vc.view.frame = CGRect(origin: .zero, size: size)
    vc.overrideUserInterfaceStyle = dark ? .dark : .light
    return vc
}
#elseif canImport(AppKit)
import AppKit
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

/// Per-component snapshot coverage: every control-plane surface is captured
/// in dark and light. Flip `isRecording = true` once to seed baselines.
@MainActor
final class ControlPlaneSnapshotTests: XCTestCase {

    override func setUp() { super.setUp(); /* isRecording = true */ }

    private func verify(_ view: some View, _ size: CGSize, name: String,
                        file: StaticString = #filePath, testName: String = #function, line: UInt = #line) throws {
        try AndromedaUISnapshotSupport.requireBaselines(file: file)
        for dark in [true, false] {
            let host = makeHost(view, size, dark: dark)
            assertSnapshot(of: host, as: .image(precision: 0.98, perceptualPrecision: 0.96),
                           named: "\(name)-\(dark ? "dark" : "light")",
                           file: file, testName: testName, line: line)
        }
    }

    func testControlPlaneWindow() throws {
        try verify(ControlPlaneView(), CGSize(width: 1120, height: 780), name: "control-plane")
    }
    func testMemorySection() throws {
        try verify(sectionShell { MemorySection() }, CGSize(width: 900, height: 900), name: "memory")
    }
    func testModelsSection() throws {
        try verify(sectionShell { ModelsSection() }, CGSize(width: 760, height: 560), name: "models")
    }
    func testSearchSection() throws {
        try verify(sectionShell { SearchSection() }, CGSize(width: 760, height: 460), name: "search")
    }
    func testSettingsSection() throws {
        try verify(sectionShell { SettingsSection() }, CGSize(width: 820, height: 640), name: "settings")
    }
    func testCapabilityLists() throws {
        for p in [Pillar.mcp, .skills, .secrets, .fleet] {
            try verify(sectionShell { CapabilityListSection(pillar: p) }, CGSize(width: 720, height: 420), name: "list-\(p.rawValue)")
        }
    }
    func testMemoryKinds() throws {
        try verify(MemoryKindsGrid(), CGSize(width: 700, height: 420), name: "memory-kinds")
    }
    func testPrimitives() throws {
        try verify(coreShell { AndromedaCore(size: 56) }, CGSize(width: 160, height: 160), name: "core")
        try verify(coreShell { LivePulse() }, CGSize(width: 120, height: 120), name: "live-pulse")
        try verify(coreShell { StatusBadge(.partial) }, CGSize(width: 140, height: 60), name: "status-badge")
    }

    // Helpers: put a section on the Andromeda surface with padding.
    private func sectionShell<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        ZStack(alignment: .topLeading) { AndromedaSurface(); content().padding(20) }
    }
    private func coreShell<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        ZStack { AndromedaSurface(); content() }
    }
}
