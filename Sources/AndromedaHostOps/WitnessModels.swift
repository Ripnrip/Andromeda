import AndromedaSecrets
import Foundation

// MARK: - Health status

/// Observable health status for a single probe target.
///
/// `unknown` is the initial state before any successful probe has established
/// a baseline. Transitions to `healthy` or `failed` are the only events that
/// produce notifications (plus the threshold-gated `unknown → failed` path).
public enum WitnessHealthStatus: String, Sendable, Codable, Equatable {
    case unknown
    case healthy
    case failed
}

// MARK: - Probe target configuration

/// One HTTP endpoint to probe. The URL must be absolute; timeout and expected
/// status range keep probes honest without overfitting response payloads.
public struct WitnessTarget: Sendable, Codable, Equatable {
    /// Human-readable label shown in status/log output (e.g. "studio-runtime").
    public let label: String
    /// Absolute URL to probe via GET (e.g. "http://studio:8788/health").
    public let url: String
    /// Per-request timeout in seconds.
    public let timeoutSeconds: Double
    /// Inclusive lower bound for a successful response (default 200).
    public let successStatusMin: Int
    /// Inclusive upper bound for a successful response (default 299).
    public let successStatusMax: Int

    public init(
        label: String,
        url: String,
        timeoutSeconds: Double = 5,
        successStatusMin: Int = 200,
        successStatusMax: Int = 299
    ) {
        self.label = label
        self.url = url
        self.timeoutSeconds = timeoutSeconds
        self.successStatusMin = successStatusMin
        self.successStatusMax = successStatusMax
    }

    /// Returns true when `statusCode` falls within the configured success window.
    public func isSuccessStatus(_ statusCode: Int) -> Bool {
        (successStatusMin...successStatusMax).contains(statusCode)
    }
}

// MARK: - Witness configuration

/// Top-level configuration for the external fleet witness.
///
/// Config is pure data — no secrets. The Telegram bot token is a
/// `SecretReference` resolved at call time via `SecretProviding`; it must
/// never be persisted or logged.
public struct WitnessConfiguration: Sendable, Codable, Equatable {
    /// Identifier shown in status output so operators know whose witness this is.
    public let owner: String
    /// Hostname or machine label shown in status output.
    public let host: String
    /// Targets to probe in order.
    public let targets: [WitnessTarget]
    /// Consecutive failures required before alerting on `unknown → failed`
    /// or `healthy → failed`. Default 3.
    public let failureThreshold: Int
    /// Maximum number of transition events retained in the JSONL history.
    /// Older entries are not removed from the file (append-only), but the
    /// in-memory and `status` views cap at this count.
    public let maxEventHistory: Int
    /// Directory for durable state files. Defaults to `~/.andromeda/witness`.
    public let stateDirectory: String
    /// Telegram notification configuration. Optional — when nil, no Telegram
    /// notifications are sent.
    public let telegram: TelegramConfig?

    public init(
        owner: String,
        host: String,
        targets: [WitnessTarget],
        failureThreshold: Int = 3,
        maxEventHistory: Int = 200,
        stateDirectory: String = "~/.andromeda/witness",
        telegram: TelegramConfig? = nil
    ) {
        self.owner = owner
        self.host = host
        self.targets = targets
        self.failureThreshold = max(1, failureThreshold)
        self.maxEventHistory = max(10, maxEventHistory)
        self.stateDirectory = stateDirectory
        self.telegram = telegram
    }

    /// Per-target state file path (atomic JSON).
    public func stateFilePath(for target: WitnessTarget) -> String {
        "\(expandedStateDirectory)/\(target.label).state.json"
    }

    /// Per-target transition log path (append-only JSONL).
    public func logFilePath(for target: WitnessTarget) -> String {
        "\(expandedStateDirectory)/\(target.label).transitions.jsonl"
    }

    /// State directory with `~` expanded to the home directory.
    public var expandedStateDirectory: String {
        guard stateDirectory.hasPrefix("~") else { return stateDirectory }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + String(stateDirectory.dropFirst())
    }
}

// MARK: - Telegram configuration

/// Telegram notification configuration. The bot token is a `SecretReference`
/// (Keychain in production) — never a raw string. The chat ID is non-secret
/// and may be passed via config or CLI.
public struct TelegramConfig: Sendable, Codable, Equatable {
    /// Keychain reference for the bot token. Never stored or logged.
    public let botTokenReference: SecretReference
    /// Telegram chat ID to send alerts to (non-secret).
    public let chatID: String
    /// Base URL for the Telegram Bot API. Injectable for testing.
    public let apiBaseURL: String

    public init(
        botTokenReference: SecretReference,
        chatID: String,
        apiBaseURL: String = "https://api.telegram.org"
    ) {
        self.botTokenReference = botTokenReference
        self.chatID = chatID
        self.apiBaseURL = apiBaseURL
    }
}

// MARK: - Per-target durable state

/// Durable per-target state persisted as atomic JSON.
public struct WitnessTargetState: Sendable, Codable, Equatable {
    public let targetLabel: String
    public var status: WitnessHealthStatus
    public var consecutiveFailures: Int
    public var lastCheckedAt: Date?
    public var lastTransitionAt: Date?
    public var lastReason: String?
    public var totalChecks: Int
    public var totalFailures: Int
    public var totalRecoveries: Int
    /// Transition records waiting to be appended to the JSONL journal. The
    /// queue is persisted with state before file I/O, closing the crash window
    /// between deciding a transition and recording it.
    public var pendingTransitions: [WitnessTransitionEvent]
    /// Notifications durably queued before delivery. A failed Telegram call
    /// leaves the event here so the next check retries it instead of silently
    /// losing the only alert for an outage.
    public var pendingNotifications: [WitnessTransitionEvent]

    /// Fresh state for a target that has never been probed.
    public static func initial(targetLabel: String) -> WitnessTargetState {
        WitnessTargetState(
            targetLabel: targetLabel,
            status: .unknown,
            consecutiveFailures: 0,
            lastCheckedAt: nil,
            lastTransitionAt: nil,
            lastReason: nil,
            totalChecks: 0,
            totalFailures: 0,
            totalRecoveries: 0,
            pendingTransitions: [],
            pendingNotifications: []
        )
    }
}

// MARK: - Transition event

/// A state transition recorded in the append-only JSONL log.
///
/// Only transitions are logged — steady-state probes produce no events.
public struct WitnessTransitionEvent: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable, Equatable {
        case established    // unknown → healthy (initial baseline, no alert)
        case alert          // healthy → failed or unknown → failed (after threshold)
        case recovery       // failed → healthy
    }

    public let id: UUID
    public let kind: Kind
    public let targetLabel: String
    public let owner: String
    public let host: String
    public let fromStatus: WitnessHealthStatus
    public let toStatus: WitnessHealthStatus
    public let reason: String
    public let timestamp: Date
    public let consecutiveFailures: Int

    public init(
        id: UUID = UUID(),
        kind: Kind,
        targetLabel: String,
        owner: String,
        host: String,
        fromStatus: WitnessHealthStatus,
        toStatus: WitnessHealthStatus,
        reason: String,
        timestamp: Date = Date(),
        consecutiveFailures: Int
    ) {
        self.id = id
        self.kind = kind
        self.targetLabel = targetLabel
        self.owner = owner
        self.host = host
        self.fromStatus = fromStatus
        self.toStatus = toStatus
        self.reason = reason
        self.timestamp = timestamp
        self.consecutiveFailures = consecutiveFailures
    }
}

// MARK: - Probe result

/// The outcome of a single probe attempt, with typed failure classification.
public struct WitnessProbeResult: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case success(statusCode: Int)
        case httpError(statusCode: Int)
        case timeout
        case connectionFailure(String)
    }

    public let targetLabel: String
    public let outcome: Outcome
    public let checkedAt: Date

    public init(targetLabel: String, outcome: Outcome, checkedAt: Date = Date()) {
        self.targetLabel = targetLabel
        self.outcome = outcome
        self.checkedAt = checkedAt
    }

    public var isSuccessful: Bool {
        if case .success = outcome { return true }
        return false
    }

    /// Human-readable reason for logs and notifications.
    public var reason: String {
        switch outcome {
        case let .success(code):
            return "HTTP \(code)"
        case let .httpError(code):
            return "HTTP \(code) (non-success status)"
        case .timeout:
            return "timeout"
        case let .connectionFailure(detail):
            return "connection failure: \(detail)"
        }
    }
}
