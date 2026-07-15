/**
 * 🎭 SnapshotCatalogSupport - The Pixel-Perfect Stage Manager
 *
 * "We freeze light and dark, medium and thunderously large type,
 * then ask SnapshotTesting to paint stills of the utility panel
 * and the pocket familiar — no improvisation, no floating dates.
 * On macOS the stills travel through NSHostingView (SwiftUI .image
 * is an iOS/tvOS-only velvet rope)."
 *
 * - The Theatrical QA Virtuoso of MemoryKit Visual Regression
 */

import AppKit
import SwiftUI
@preconcurrency import SnapshotTesting
import XCTest
@testable import MemoryKit

/// 🌟 Shared matrix axes + hosting helpers for UI snapshot catalogs
enum SnapshotCatalogSupport {

    /// 🎨 Color schemes under the footlights
    static let colorSchemes: [(name: String, value: ColorScheme)] = [
        ("light", .light),
        ("dark", .dark),
    ]

    /// 🔤 Dynamic Type sizes — readable + accessibility stress
    static let dynamicTypeSizes: [(name: String, value: DynamicTypeSize)] = [
        ("medium", .medium),
        ("a11y2", .accessibility2),
    ]

    /// 📐 Fixed canvas for CommandCenter popover chrome
    static let commandCenterSize = CGSize(width: 380, height: 360)

    /// 📐 Fixed canvas for FloatingPet ambient chrome
    static let petSize = CGSize(width: 160, height: 180)

    /// 🎬 Record mode: `.missing` writes PNGs on first run, compares thereafter.
    /// Override with `SNAPSHOT_TESTING_RECORD=all` (or `failed`) in the environment.
    static var recordMode: SnapshotTestingConfiguration.Record {
        if let raw = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
            switch raw {
            case "all", "true", "1", "yes":
                return .all
            case "failed":
                return .failed
            case "never", "false", "0", "no":
                return .never
            case "missing":
                return .missing
            default:
                break
            }
        }
        return .missing
    }

    // MARK: - CommandCenter fixtures

    @MainActor
    static func commandCenterModel(state: CommandCenterSnapshotState) -> CommandCenterModel {
        switch state {
        case .healthy:
            return CommandCenterModel(
                healthStatus: .healthy,
                syncStatus: .idle,
                activeVisibility: .private
            )
        case .degraded:
            return CommandCenterModel(
                healthStatus: .unhealthy("Qdrant"),
                syncStatus: .failed(.cloudKitError("offline constellation")),
                activeVisibility: .friends
            )
        case .syncing:
            return CommandCenterModel(
                healthStatus: .healthy,
                syncStatus: .syncing,
                activeVisibility: .internal
            )
        case .emptyIntents:
            return CommandCenterModel(
                healthStatus: .unknown,
                syncStatus: .idle,
                activeVisibility: .private,
                recordedIntents: []
            )
        }
    }

    // MARK: - Pet fixtures

    @MainActor
    static func petModel(
        state: FloatingPetAmbientState,
        reduceMotion: Bool
    ) -> FloatingPetModel {
        let detail: String?
        switch state {
        case .idle: detail = nil
        case .syncing: detail = "cloud sync"
        case .dreaming: detail = "materializing"
        case .degraded: detail = "letta_api"
        }
        return FloatingPetModel(
            ambientState: state,
            reduceMotion: reduceMotion,
            statusDetail: detail
        )
    }

    // MARK: - Hosting (macOS)

    /// 🎨 Wrap a view with scheme + Dynamic Type and kill ambient animation jitter
    @MainActor
    static func staged<V: View>(
        _ view: V,
        colorScheme: ColorScheme,
        dynamicType: DynamicTypeSize,
        size: CGSize
    ) -> some View {
        view
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, dynamicType)
            .transaction { $0.animation = nil }
            .padding(12)
            .frame(width: size.width, height: size.height)
            .background(colorScheme == .dark ? Color.black : Color.white)
    }

    /// 🖼️ Host SwiftUI in AppKit so SnapshotTesting can shoot `.image` on macOS
    @MainActor
    static func hostingView<V: View>(
        _ view: V,
        colorScheme: ColorScheme,
        dynamicType: DynamicTypeSize,
        size: CGSize
    ) -> NSView {
        let root = staged(
            view,
            colorScheme: colorScheme,
            dynamicType: dynamicType,
            size: size
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }
}

/// 🌟 CommandCenter named states for the snapshot matrix
enum CommandCenterSnapshotState: String, CaseIterable {
    case healthy
    case degraded
    case syncing
    case emptyIntents
}

/// 🌟 XCTestCase base that applies SnapshotTesting record configuration
class MemoryKitSnapshotTestCase: XCTestCase {
    override func invokeTest() {
        withSnapshotTesting(record: SnapshotCatalogSupport.recordMode) {
            super.invokeTest()
        }
    }
}
