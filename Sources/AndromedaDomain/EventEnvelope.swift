import Foundation

/// Declares the minimum contract for payloads stored in the canonical event journal.
public protocol EventPayload: Codable, Sendable, Equatable {
    static var eventType: String { get }
}

/// The persisted schema version for a canonical event.
public struct EventSchemaVersion: Codable, Hashable, Sendable, ExpressibleByIntegerLiteral {
    public static let current: Self = 1

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(integerLiteral value: Int) {
        self.init(rawValue: value)
    }
}

/// A concrete event envelope carrying provenance and schema metadata for replay.
public struct EventEnvelope<Payload: EventPayload>: Codable, Sendable, Equatable {
    public let id: EventID
    public let causationID: EventID?
    public let correlationID: UUID
    public let occurredAt: Date
    public let source: EventSource
    public let payload: Payload
    public let schemaVersion: EventSchemaVersion

    public init(
        id: EventID,
        causationID: EventID? = nil,
        correlationID: UUID,
        occurredAt: Date,
        source: EventSource,
        payload: Payload,
        schemaVersion: EventSchemaVersion = .current
    ) {
        self.id = id
        self.causationID = causationID
        self.correlationID = correlationID
        self.occurredAt = occurredAt
        self.source = source
        self.payload = payload
        self.schemaVersion = schemaVersion
    }
}

/// Minimal canonical payload set for the first runtime milestones.
public enum CanonicalEventPayload: Codable, Sendable, Equatable, EventPayload {
    case sessionStarted(SessionStartedPayload)
    case memoryNoted(MemoryNotedPayload)
    case checkpointCaptured(CheckpointCapturedPayload)
    case runtimeHeartbeat(RuntimeHeartbeatPayload)

    public static let eventType = "andromeda.canonical"
}

public struct SessionStartedPayload: Codable, Sendable, Equatable {
    public let sessionID: SessionID
    public let projectID: ProjectID
    public let summary: String

    public init(sessionID: SessionID, projectID: ProjectID, summary: String) {
        self.sessionID = sessionID
        self.projectID = projectID
        self.summary = summary
    }
}

public struct MemoryNotedPayload: Codable, Sendable, Equatable {
    public let memoryID: MemoryID
    public let summary: String

    public init(memoryID: MemoryID, summary: String) {
        self.memoryID = memoryID
        self.summary = summary
    }
}

public struct CheckpointCapturedPayload: Codable, Sendable, Equatable {
    public let checkpointID: CheckpointID
    public let summary: String

    public init(checkpointID: CheckpointID, summary: String) {
        self.checkpointID = checkpointID
        self.summary = summary
    }
}

public struct RuntimeHeartbeatPayload: Codable, Sendable, Equatable {
    public let environmentID: EnvironmentID?
    public let detail: String

    public init(environmentID: EnvironmentID? = nil, detail: String) {
        self.environmentID = environmentID
        self.detail = detail
    }
}
