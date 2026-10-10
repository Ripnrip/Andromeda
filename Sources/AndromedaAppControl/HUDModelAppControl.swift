import AndromedaHUDCore
import AppKit
import Foundation
import SwiftUI

/**
 * 🎭 The HUD Model Bridges - One Funnel, Many Footlights
 *
 * "The dispatcher borrows the very hands the buttons use —
 *  no twin logic, no shadow paths, nothing to drift."
 *
 * - The Spellbinding Museum Director of App Control
 */

// MARK: - State Source

/// Snapshot sourcing from the live `HUDModel` — the curated `GET /state`
/// read model behind the capability curtain (HAB-838).
///
/// Reads hop to the main actor (the model is `@MainActor @Observable`), name
/// only contract fields, and never serialize a provider object wholesale.
public struct HUDModelAppControlSource: AppControlStateSourcing {
    private let model: HUDModel

    public init(model: HUDModel) {
        self.model = model
    }

    public func snapshot() async throws -> AppControlSnapshot {
        try await MainActor.run {
            AppControlSnapshot(
                service: "AndromedaHUD",
                version: AppControlSnapshot.contractVersion,
                isReady: model.isReady,
                query: model.fieldQuery,
                outcome: Self.summarize(model.lastOutcome),
                recentQueries: model.recentQueries,
                fleetPulse: AppControlSnapshot.FleetPulseSummary(
                    status: model.fleetPulse.status.rawValue,
                    attentionCount: model.fleetPulse.attentionCount,
                    detail: model.fleetPulse.detail
                ),
                showsResultsPanel: model.lastOutcome.showsResultsPanel,
                capturedAt: Date().timeIntervalSince1970
            )
        }
    }

    /// 🌟 Single switch over `HUDOutcome` — kind + one-line story, counts
    /// where they exist, never a raw payload dump.
    public static func summarize(_ outcome: HUDOutcome) -> AppControlSnapshot.OutcomeSummary {
        switch outcome {
        case .idle:
            AppControlSnapshot.OutcomeSummary(kind: "idle", summary: "HUD idle")
        case .syncing:
            AppControlSnapshot.OutcomeSummary(kind: "syncing", summary: "Query in flight")
        case let .recalled(hits):
            AppControlSnapshot.OutcomeSummary(
                kind: "recalled",
                summary: "Recalled \(hits.count) memory hit\(hits.count == 1 ? "" : "s")",
                hits: hits.count
            )
        case let .stored(idSummary):
            AppControlSnapshot.OutcomeSummary(kind: "stored", summary: "Stored \(idSummary)")
        case let .journaled(idSummary):
            AppControlSnapshot.OutcomeSummary(kind: "journaled", summary: "Journaled \(idSummary)")
        case let .projects(states):
            AppControlSnapshot.OutcomeSummary(
                kind: "projects",
                summary: "\(states.count) project\(states.count == 1 ? "" : "s") on the surface",
                projects: states.count
            )
        case let .created(title):
            AppControlSnapshot.OutcomeSummary(kind: "created", summary: "Created \(title)")
        case let .updated(title):
            AppControlSnapshot.OutcomeSummary(kind: "updated", summary: "Updated \(title)")
        case let .chainHealth(report):
            AppControlSnapshot.OutcomeSummary(kind: "chainHealth", summary: "Chain \(report.overall.rawValue)")
        case let .empty(message):
            AppControlSnapshot.OutcomeSummary(kind: "empty", summary: message)
        case let .failed(message):
            AppControlSnapshot.OutcomeSummary(kind: "failed", summary: message)
        }
    }
}

// MARK: - Dispatcher

/// Typed action dispatch onto the live `HUDModel` — the exact code paths the
/// on-glass controls run, nothing more. There is deliberately no logic here
/// to test in isolation; the ≡ tests prove the equivalence.
public struct HUDModelAppControlDispatcher: AppControlDispatching {
    private let model: HUDModel

    public init(model: HUDModel) {
        self.model = model
    }

    public func dispatch(_ action: AppControlAction) async -> AppControlOutcome {
        switch action {
        case let .submitQuery(query):
            // 🌟 The exact Enter path: field first, then submit — so the glass
            // and the outcome panel tell the same story.
            await MainActor.run { model.fieldQuery = query }
            await model.submitQuery(query)
            return AppControlOutcome(action: action.name, status: .ok, detail: "submitted ‘\(query)’")

        case .focusSearch:
            // 🌟 The exact status-item path: the same notification the menu
            // posts, observed by the same delegates.
            await MainActor.run {
                NotificationCenter.default.post(name: .andromedaHUDFocusSearch, object: nil)
            }
            return AppControlOutcome(action: action.name, status: .ok, detail: "focus requested")

        case .dismissResults:
            // 🌟 The exact Escape path: cancel in-flight work, then clear.
            await MainActor.run {
                model.cancelInFlightWork()
                model.dismissResults()
            }
            return AppControlOutcome(action: action.name, status: .ok, detail: "results dismissed")

        case .refreshFleetPulse:
            // 🌟 The same refresh `start()` performs on boot.
            await MainActor.run { model.refreshFleetPulse() }
            return AppControlOutcome(action: action.name, status: .ok, detail: "fleet pulse refreshed")
        }
    }
}

// MARK: - Screenshotter

/// Renders the HUD glass to PNG via `ImageRenderer` — the app's own view
/// tree, the app's own privileges. Never `screencapture`: that path demands
/// Screen-Recording TCC and frames strangers' windows alongside ours.
public struct HUDViewAppControlScreenshotter: AppControlScreenshotting {
    /// Fixed render width — the HUD is a width-constrained pill; the renderer
    /// sizes height to fit.
    private static let renderWidth: CGFloat = 420

    private let model: HUDModel

    public init(model: HUDModel) {
        self.model = model
    }

    public enum ScreenshotError: Error, CustomStringConvertible, Sendable {
        case rendererProducedNoImage

        public var description: String {
            "ImageRenderer produced no CGImage (view not yet renderable?)"
        }
    }

    public func pngData() async throws -> Data {
        let png: Data? = await MainActor.run {
            // 🔮 Fresh tree from the live model — captures current state
            // without disturbing the real window.
            let renderer = ImageRenderer(content: HUDView(model: model).frame(width: Self.renderWidth))
            renderer.scale = 2
            guard let cgImage = renderer.cgImage else { return nil }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            return rep.representation(using: .png, properties: [:])
        }
        guard let png else {
            throw ScreenshotError.rendererProducedNoImage
        }
        return png
    }
}
