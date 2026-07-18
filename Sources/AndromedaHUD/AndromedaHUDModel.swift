import Foundation
import Observation

/// Ambient health pulse shown on the collapsed HUD pill.
public enum HUDHealthPulse: String, CaseIterable, Equatable, Sendable, Codable {
    case unknown
    case healthy
    case working
    case degraded

    /// SF Symbol for the status glyph.
    public var systemImage: String {
        switch self {
        case .unknown: return "circle.dotted"
        case .healthy: return "checkmark.circle.fill"
        case .working: return "arrow.triangle.2.circlepath"
        case .degraded: return "exclamationmark.triangle.fill"
        }
    }

    /// VoiceOver label for the status glyph.
    public var accessibilityLabel: String {
        switch self {
        case .unknown: return "Health unknown"
        case .healthy: return "Health healthy"
        case .working: return "Health working"
        case .degraded: return "Health degraded"
        }
    }
}

/// Presentation chrome for the floating HUD (collapsed pill vs expanded search).
public enum HUDExpansion: String, CaseIterable, Equatable, Sendable, Codable {
    case collapsed
    case expanded

    public var isExpanded: Bool { self == .expanded }
}

/// Recorded Ask AI / memory submissions (stub ledger — no network yet).
public struct HUDSearchSubmission: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var intent: HUDSearchIntent
    public var submittedAt: Date

    public init(id: UUID = UUID(), intent: HUDSearchIntent, submittedAt: Date = Date()) {
        self.id = id
        self.intent = intent
        self.submittedAt = submittedAt
    }
}

/**
 Main-actor `@Observable` state for the Andromeda floating HUD (BIN-55 / BIN-58).

 Holds expansion, snap posture, health pulse, Ask AI query text, and a stub
 submission ledger. Real `memory.*` / `infer.write` wiring lands in a later pass;
 this model proves modern Observation + capability-safe routing.
 */
@MainActor
@Observable
public final class AndromedaHUDModel {
    /// Collapsed pill vs expanded Ask AI panel.
    public var expansion: HUDExpansion
    /// Floating vs menu-bar dock.
    public var snapMode: HUDSnapMode
    /// Current origin in global screen coordinates.
    public var origin: HUDPoint
    /// Ambient health pulse mirrored from fleet / MemoryKit status.
    public var health: HUDHealthPulse
    /// Optional detail under the health glyph (failing check name, etc.).
    public var healthDetail: String?
    /// Text in the expandable Ask AI field.
    public var query: String
    /// Reduce-motion preference (injectable for tests).
    public var reduceMotion: Bool
    /// Footer whisper after the last action.
    public var lastMessage: String?
    /// Append-only stub ledger of routed intents.
    public private(set) var submissions: [HUDSearchSubmission]
    /// Last measured timing sample (BIN-59 proofs).
    public var lastTiming: HUDTimingSample?

    public init(
        expansion: HUDExpansion = .collapsed,
        snapMode: HUDSnapMode = .menuBar,
        origin: HUDPoint = HUDPoint(x: 0, y: 0),
        health: HUDHealthPulse = .unknown,
        healthDetail: String? = nil,
        query: String = "",
        reduceMotion: Bool = false,
        submissions: [HUDSearchSubmission] = []
    ) {
        self.expansion = expansion
        self.snapMode = snapMode
        self.origin = origin
        self.health = health
        self.healthDetail = healthDetail
        self.query = query
        self.reduceMotion = reduceMotion
        self.submissions = submissions
    }

    /// Current chrome size for snap / window layout.
    public var chromeSize: HUDPoint {
        expansion.isExpanded ? HUDSnapEngine.expandedSize : HUDSnapEngine.collapsedSize
    }

    /// Combined accessibility announcement for the root chrome.
    public var accessibilityLabel: String {
        var parts = ["Andromeda HUD", health.accessibilityLabel, snapMode.accessibilityLabel]
        if expansion.isExpanded {
            parts.append("Ask AI expanded")
        }
        if let healthDetail, !healthDetail.isEmpty {
            parts.append(healthDetail)
        }
        return parts.joined(separator: ". ")
    }

    /// Expand the Ask AI / memory search field (BIN-57).
    public func expandSearch() {
        let sample = HUDStopwatch.measure(
            operation: "hud.expand",
            budgetMilliseconds: HUDPerformanceBudget.expandInteractionMilliseconds
        ) {
            expansion = .expanded
            lastMessage = "Ask AI ready · memory.* / infer.write"
        }
        lastTiming = sample
    }

    /// Collapse back to the compact pill.
    public func collapse() {
        expansion = .collapsed
        lastMessage = nil
    }

    /// Toggle expansion.
    public func toggleExpansion() {
        if expansion.isExpanded {
            collapse()
        } else {
            expandSearch()
        }
    }

    /// Apply a drag end: Pop-style decay coast, then settle + snap (BIN-56 / BIN-60).
    ///
    /// - Parameter velocity: pts/s in AppKit global coordinates (y-up). Zero skips coast.
    public func endDrag(
        proposedOrigin: HUDPoint,
        screen: HUDScreenMetrics,
        velocity: HUDPoint = HUDPoint(x: 0, y: 0)
    ) {
        let sample = HUDStopwatch.measure(
            operation: "hud.snap",
            budgetMilliseconds: HUDPerformanceBudget.snapSettleMilliseconds
        ) {
            let settled = HUDSnapEngine.settleWithDecay(
                proposedOrigin: proposedOrigin,
                velocity: velocity,
                size: chromeSize,
                screen: screen
            )
            origin = settled.origin
            snapMode = settled.mode
            let coasted = abs(settled.coasted.x - proposedOrigin.x) > 0.5
                || abs(settled.coasted.y - proposedOrigin.y) > 0.5
            lastMessage = coasted
                ? "\(snapMode.accessibilityLabel) · decay coast"
                : snapMode.accessibilityLabel
        }
        lastTiming = sample
    }

    /// Place the HUD at the default menu-bar dock for a screen.
    public func dockToMenuBar(screen: HUDScreenMetrics) {
        origin = HUDSnapEngine.defaultMenuBarOrigin(size: chromeSize, screen: screen)
        snapMode = .menuBar
        lastMessage = HUDSnapMode.menuBar.accessibilityLabel
    }

    /// Update ambient health pulse.
    public func applyHealth(_ pulse: HUDHealthPulse, detail: String? = nil) {
        health = pulse
        healthDetail = detail
    }

    /// Route and record the current query (stub — no network).
    @discardableResult
    public func submitQuery() -> HUDSearchIntent {
        var intent: HUDSearchIntent = .empty
        let sample = HUDStopwatch.measure(
            operation: "hud.search.route",
            budgetMilliseconds: HUDPerformanceBudget.searchRouteMilliseconds
        ) {
            intent = HUDSearchRouter.route(query)
            guard intent != .empty else {
                lastMessage = HUDSearchIntent.empty.displaySummary
                return
            }
            submissions.append(HUDSearchSubmission(intent: intent))
            lastMessage = intent.displaySummary
            query = ""
        }
        lastTiming = sample
        return intent
    }

    /// Clear the stub submission ledger (tests / preview reset).
    public func clearSubmissions() {
        submissions.removeAll()
        lastMessage = nil
        lastTiming = nil
    }
}
