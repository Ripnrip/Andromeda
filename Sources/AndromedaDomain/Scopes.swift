import Foundation

/// Scope metadata used to constrain event interpretation and later projection fan-out.
public struct EventScope: Codable, Sendable, Equatable {
    public let projectID: ProjectID?
    public let memoryID: MemoryID?
    public let sessionID: SessionID?
    public let checkpointID: CheckpointID?
    public let leaseID: LeaseID?
    public let environmentID: EnvironmentID?

    public init(
        projectID: ProjectID? = nil,
        memoryID: MemoryID? = nil,
        sessionID: SessionID? = nil,
        checkpointID: CheckpointID? = nil,
        leaseID: LeaseID? = nil,
        environmentID: EnvironmentID? = nil
    ) {
        self.projectID = projectID
        self.memoryID = memoryID
        self.sessionID = sessionID
        self.checkpointID = checkpointID
        self.leaseID = leaseID
        self.environmentID = environmentID
    }
}

/// Provenance describing which subsystem emitted a canonical event.
public struct EventSource: Codable, Sendable, Equatable {
    public let subsystem: String
    public let actor: String
    public let scope: EventScope

    public init(subsystem: String, actor: String, scope: EventScope = .init()) {
        self.subsystem = subsystem
        self.actor = actor
        self.scope = scope
    }
}
