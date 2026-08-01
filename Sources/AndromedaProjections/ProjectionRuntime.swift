import AndromedaDomain
import AndromedaJournal
import Foundation

/// Minimal projection receipt placeholder for later milestone fan-out work.
public struct ProjectionReceipt: Sendable, Equatable {
    public let sinkID: String
    public let accepted: Bool

    public init(sinkID: String, accepted: Bool) {
        self.sinkID = sinkID
        self.accepted = accepted
    }
}

/// Stub projection runtime kept intentionally small until Milestone 4.
public actor ProjectionRuntime {
    public init() {}

    public func planReplay(for events: [PersistedEvent]) -> [ProjectionReceipt] {
        events.map { _ in ProjectionReceipt(sinkID: "projection.stub", accepted: true) }
    }
}
