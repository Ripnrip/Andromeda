import Foundation
import SnapshotTesting
import SwiftUI
import XCTest

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    @preconcurrency import AppKit
#endif

@testable import AndromedaOrchestrator

// MARK: - Hosting

//
// Shared hosting for the snapshot suites: same framing + appearance control on
// every platform, so a UIKit-only habit cannot quietly dead-file the suite on
// the macOS CI lane. Reduce-motion is forced on so every entrance resolves to
// its still, complete frame (`EntranceModifier` gates on it) and ambient loops
// (mark orbit, badge pulse) freeze — the recorded baseline is deterministic.

@MainActor
enum OrchestratorSnapshotHosting {
    #if canImport(UIKit)
        static func makeHost(_ view: some View, _ size: CGSize, dark: Bool) -> UIViewController {
            let vc = UIHostingController(
                rootView: view
                    .environment(\._accessibilityReduceMotion, true)
                    .frame(width: size.width, height: size.height)
            )
            vc.view.frame = CGRect(origin: .zero, size: size)
            vc.overrideUserInterfaceStyle = dark ? .dark : .light
            return vc
        }
    #elseif canImport(AppKit)
        static func makeHost(_ view: some View, _ size: CGSize, dark: Bool) -> NSViewController {
            let themed = view
                .environment(\._accessibilityReduceMotion, true)
                .environment(\.colorScheme, dark ? ColorScheme.dark : ColorScheme.light)
                .frame(width: size.width, height: size.height)
            let vc = NSHostingController(rootView: AnyView(themed))
            vc.view.frame = CGRect(origin: .zero, size: size)

            // Pre-host the controller in an offscreen window and run the runloop
            // briefly so `.task` closures land before the snapshot capture:
            // `EntranceModifier` starts hidden and reveals from its `.task`, and a
            // purely synchronous draw would record the pre-task (hidden) frame.
            // The window is ordered front (from an offscreen origin) so ScrollView
            // + lazy containers actually materialize their items — an unordered
            // window never engages the layout/compositing path that lazily
            // instantiates children, and the capture records an empty void.
            let window = NSWindow(contentViewController: vc)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            window.setFrame(CGRect(origin: .zero, size: size), display: true)
            window.orderFrontRegardless()
            window.displayIfNeeded()
            window.display()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            // The view stays ATTACHED to this window (which outlives the capture
            // via the associated object below). Detaching before the snapshot
            // strategy's async hop — `window.contentViewController = nil` — let
            // SwiftUI tear the render tree down over the next runloop turns, and
            // `cacheDisplay` then recorded a void: heavier trees (the gallery
            // wall) lost everything, lighter ones (the console shell) lost only
            // their uncached interiors. Attached, the capture is deterministic.
            objc_setAssociatedObject(vc, &OrchestratorSnapshotHosting.hostWindowSlot, window, .OBJC_ASSOCIATION_RETAIN)
            return vc
        }
    #endif

    private nonisolated(unsafe) static var hostWindowSlot: UInt8 = 0
}

// MARK: - Record mode / baselines gate

enum OrchestratorSnapshotSupport {
    /// Record mode for Point-Free `withSnapshotTesting(record:)`.
    /// Override with `SNAPSHOT_TESTING_RECORD=1` (or `all` / `failed` / `never` / `missing`).
    static var recordMode: SnapshotTestingConfiguration.Record {
        if let raw = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !raw.isEmpty
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

    /// Skip when the test-specific `__Snapshots__/TestName/` subdirectory is
    /// missing/empty, so a suite without baselines yet cannot gate CI red.
    /// Record mode (`SNAPSHOT_TESTING_RECORD=1`) always proceeds.
    static func requireBaselines(
        file: StaticString = #filePath
    ) throws {
        // Equatable compare — `Record` is not a frozen switchable enum.
        if recordMode == .all || recordMode == .failed {
            return
        }

        let testDir = URL(fileURLWithPath: String(describing: file))
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
            .appendingPathComponent(
                URL(fileURLWithPath: String(describing: file))
                    .deletingPathExtension()
                    .lastPathComponent,
                isDirectory: true
            )
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: testDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        guard !contents.isEmpty else {
            throw XCTSkip(
                "AndromedaOrchestrator snapshot baselines not recorded yet — run once with SNAPSHOT_TESTING_RECORD=1 on macOS (or tip the PR head with [record-snapshots])"
            )
        }
    }
}

// MARK: - Deterministic fixtures

//
// The live model is a simulator: every tick randomizes requests and metrics.
// Snapshots pin the same view states the previews show, but with fixtures the
// baseline can be byte-stable across record and verify runs.

@MainActor
enum SnapshotFixtures {
    /// Steady-state console model: no onboarding, no launch reveal, ticker
    /// frozen, telemetry pinned. The view tree is identical to the
    /// `OrchestratorModel(firstRun: false)` the previews build.
    static func steadyModel() -> OrchestratorModel {
        let model = OrchestratorModel(firstRun: false)
        model.isStreaming = false
        model.requests = SampleData.deterministicRequests
        model.requestsPerMinute = 1240
        model.tokensPerSecond = 18.4
        model.cacheHitRate = 0.34
        return model
    }

    /// First-run model (onboarding step 0, no launch reveal) with the same
    /// frozen telemetry.
    static func onboardingModel(step: Int? = 0) -> OrchestratorModel {
        let model = OrchestratorModel(firstRun: true, launchReveal: false)
        model.isStreaming = false
        model.requests = SampleData.deterministicRequests
        model.requestsPerMinute = 1240
        model.tokensPerSecond = 18.4
        model.cacheHitRate = 0.34
        model.onboardingStep = step
        return model
    }
}

/// NSImage is `@_nonSendable(_assumed)` in AppKit SDKs; this box lets the
/// captured image change hands from the main-actor capture to the strategy's
/// pullback without an isolation-diagnosed transfer. Created and consumed on
/// the same thread by the assertion path.
private final class OrchestratorImageBox: @unchecked Sendable {
    var image: NSImage?
}

// MARK: - Synchronous image strategy

/// Snapshot-testing's stock `.image` for AppKit captures through an async hop
/// (`addImagesForRenderedViews(...).sequence().run { ... }`), by which time
/// SwiftUI has already had runloop turns to invalidate the hosted tree — for
/// heavier view trees (the gallery wall) `cacheDisplay` then records a void,
/// even with the view still attached to its host window. This strategy
/// captures SYNCHRONOUSLY in the same runloop turn as the assertion, via the
/// same `bitmapImageRepForCachingDisplay` + `cacheDisplay` primitives, which
/// draws the full materialized tree deterministically.
public extension Snapshotting where Value == NSViewController, Format == NSImage {
    static func orchestratorImage(
        precision: Float = 1,
        perceptualPrecision: Float = 1
    ) -> Snapshotting {
        SimplySnapshotting.image(
            precision: precision, perceptualPrecision: perceptualPrecision
        )
        .pullback { vc -> NSImage in
            // NSImage is `@_nonSendable(_assumed)` in the AppKit SDKs — it may
            // not cross an isolation boundary even as `assumeIsolated`'s return
            // value (and `@preconcurrency import` cannot override that). Capture
            // on the main actor, hand the image back through an unchecked box:
            // created and consumed on the same thread by the assertion path.
            let box = OrchestratorImageBox()
            MainActor.assumeIsolated {
                let view = vc.view
                precondition(
                    view.bounds.width > 0 && view.bounds.height > 0,
                    "Snapshot view has no renderable bounds: \(view.bounds)"
                )
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: rep)
                let image = NSImage(size: view.bounds.size)
                image.addRepresentation(rep)
                box.image = image
            }
            return box.image!
        }
    }
}
