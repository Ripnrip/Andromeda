import Foundation

/**
 * 🎭 The App Control Contract - The Stage Manager's Clipboard
 *
 * "What the glass knows, the loopback may ask —
 *  curated, typed, and sworn to no secrets."
 *
 * - The Spellbinding Museum Director of App Control
 */

/// Curated App Control snapshot — the `GET /state` contract for the HUD
/// process (HAB-838, pillar 3 of programmatic app control).
///
/// State is what the plane *names*, never a raw object dump: field query,
/// outcome summary, recents, fleet pulse, readiness — and never a secret.
/// Fields are additive; renames or removals are breaking and need a version
/// bump.
public struct AppControlSnapshot: Codable, Sendable, Equatable {
    /// Shape version of the snapshot contract — additive-only until bumped.
    public static let contractVersion = "1"

    /// Outcome behind the capability curtain — kind + one-line story.
    public struct OutcomeSummary: Codable, Sendable, Equatable {
        public let kind: String
        public let summary: String
        /// Hit count when `kind == "recalled"`; `nil` otherwise.
        public let hits: Int?
        /// Project count when `kind == "projects"`; `nil` otherwise.
        public let projects: Int?

        public init(kind: String, summary: String, hits: Int? = nil, projects: Int? = nil) {
            self.kind = kind
            self.summary = summary
            self.hits = hits
            self.projects = projects
        }
    }

    /// Fleet pulse for the HUD chip — headline only, no roster.
    public struct FleetPulseSummary: Codable, Sendable, Equatable {
        public let status: String
        public let attentionCount: Int
        public let detail: String

        public init(status: String, attentionCount: Int, detail: String) {
            self.status = status
            self.attentionCount = attentionCount
            self.detail = detail
        }
    }

    /// HUD process identity — `AndromedaHUD`.
    public let service: String
    /// Contract version of the snapshot shape (additive-only until bumped).
    public let version: String
    /// Whether the memory session behind the glass is ready.
    public let isReady: Bool
    /// Mirror of the search-field text at capture time.
    public let query: String
    public let outcome: OutcomeSummary
    public let recentQueries: [String]
    public let fleetPulse: FleetPulseSummary
    /// Whether the frosted results panel is showing.
    public let showsResultsPanel: Bool
    /// Epoch seconds of capture; lets callers detect staleness.
    public let capturedAt: Double

    public init(
        service: String,
        version: String,
        isReady: Bool,
        query: String,
        outcome: OutcomeSummary,
        recentQueries: [String],
        fleetPulse: FleetPulseSummary,
        showsResultsPanel: Bool,
        capturedAt: Double
    ) {
        self.service = service
        self.version = version
        self.isReady = isReady
        self.query = query
        self.outcome = outcome
        self.recentQueries = recentQueries
        self.fleetPulse = fleetPulse
        self.showsResultsPanel = showsResultsPanel
        self.capturedAt = capturedAt
    }
}

/// Typed App Control verbs — the wire names `POST /action` accepts (canon:
/// rich enums over stringly-typed dispatch).
///
/// `AppControlVerb.allCases` is the single list every surface (HTTP
/// `GET /actions`, future MCP tools) generates from, so no two callers drift.
public enum AppControlVerb: String, Sendable, CaseIterable, Codable {
    /// Type + submit a query — exactly the Enter path (`HUDModel.submitQuery`).
    case submitQuery = "hud.submit-query"
    /// Expand the pill and focus the field — the status-item / hotkey show path.
    case focusSearch = "hud.focus-search"
    /// Escape path — cancel in-flight work and clear results.
    case dismissResults = "hud.dismiss-results"
    /// Re-read the fleet-observe pulse behind the chip.
    case refreshFleetPulse = "hud.refresh-fleet-pulse"
}

/// Typed App Control action — verb plus payload. The dispatcher funnels every
/// surface through the same `HUDModel` methods the on-glass controls already
/// call; it holds no logic of its own.
public enum AppControlAction: Equatable, Sendable {
    case submitQuery(query: String)
    case focusSearch
    case dismissResults
    case refreshFleetPulse

    public var verb: AppControlVerb {
        switch self {
        case .submitQuery: .submitQuery
        case .focusSearch: .focusSearch
        case .dismissResults: .dismissResults
        case .refreshFleetPulse: .refreshFleetPulse
        }
    }

    /// Wire name — the verb's `rawValue`.
    public var name: String { verb.rawValue }
}

/// Outcome envelope for `POST /action`.
public struct AppControlOutcome: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case ok
        case error
    }

    public let action: String
    public let status: Status
    /// Human-readable result detail; safe to print (no secrets).
    public let detail: String

    public init(action: String, status: Status, detail: String) {
        self.action = action
        self.status = status
        self.detail = detail
    }
}

/// Wire format for `POST /action` — `{"action": "hud.submit-query", "query": "…"}`.
public struct AppControlActionRequest: Codable, Sendable, Equatable {
    public let action: String
    public let query: String?

    public init(action: String, query: String? = nil) {
        self.action = action
        self.query = query
    }
}

/// Anything that can produce the curated snapshot. Production wires the live
/// `HUDModel`; tests inject fixtures — keeps `AppControlRoute` free of HUD
/// internals (this module's route must stay testable without a window server).
public protocol AppControlStateSourcing: Sendable {
    func snapshot() async throws -> AppControlSnapshot
}

/// Anything that can execute typed App Control actions — the single funnel.
/// Every access surface routes through `dispatch`; none may hold logic of
/// its own.
public protocol AppControlDispatching: Sendable {
    func dispatch(_ action: AppControlAction) async -> AppControlOutcome
}

/// Anything that can render the HUD glass to PNG bytes — `ImageRenderer` in
/// production, fixture bytes in tests. Never `screencapture`: that path trips
/// Screen-Recording TCC and catches strangers in the frame; this renders the
/// app's own view tree with the app's own privileges.
public protocol AppControlScreenshotting: Sendable {
    func pngData() async throws -> Data
}
