import AndromedaPowerKit

// Example glue for the Background Process Runtime.

struct RuntimeEvent: Sendable {
    let name: String
    let metadata: [String: String]
}

protocol RuntimeEventBus: Sendable {
    func publish(_ event: RuntimeEvent) async
}

struct AndromedaPowerEventSink: PowerEventSink {
    let bus: any RuntimeEventBus

    func emit(_ event: PowerEvent) async {
        switch event {
        case let .acquired(lease, activeLeaseCount):
            await bus.publish(
                RuntimeEvent(
                    name: "power.lease.acquired",
                    metadata: [
                        "leaseID": lease.id.uuidString,
                        "owner": lease.owner,
                        "reason": lease.reason,
                        "requirements": requirementNames(lease.requirements),
                        "activeLeaseCount": String(activeLeaseCount)
                    ]
                )
            )

        case let .released(lease, activeLeaseCount):
            await bus.publish(
                RuntimeEvent(
                    name: "power.lease.released",
                    metadata: [
                        "leaseID": lease.id.uuidString,
                        "owner": lease.owner,
                        "reason": lease.reason,
                        "requirements": requirementNames(lease.requirements),
                        "activeLeaseCount": String(activeLeaseCount)
                    ]
                )
            )

        case let .assertionChanged(system, display, activeLeaseCount):
            await bus.publish(
                RuntimeEvent(
                    name: "power.assertion.changed",
                    metadata: [
                        "preventSystemSleep": String(system),
                        "preventDisplaySleep": String(display),
                        "activeLeaseCount": String(activeLeaseCount)
                    ]
                )
            )
        }
    }
}

actor ExampleJobSupervisor {
    private let power: PowerAssertionManager

    init(bus: any RuntimeEventBus) {
        self.power = PowerAssertionManager(
            eventSink: AndromedaPowerEventSink(bus: bus)
        )
    }

    func runTestFlightUpload(
        agentID: String,
        operation: @Sendable () async throws -> Void
    ) async throws {
        try await withPowerLease(
            manager: power,
            owner: agentID,
            reason: "Archive + upload TestFlight build",
            requirements: [.preventSystemSleep],
            operation: operation
        )
    }

    func runVideoRender(
        agentID: String,
        operation: @Sendable () async throws -> Void
    ) async throws {
        try await withPowerLease(
            manager: power,
            owner: agentID,
            reason: "Local video render",
            requirements: [.preventSystemSleep],
            operation: operation
        )
    }
}

/// Human-readable requirement list for lease event metadata, e.g.
/// `"preventSystemSleep,preventDisplaySleep"` — or `"none"` for an empty set.
private func requirementNames(_ requirements: PowerRequirement) -> String {
    guard !requirements.isEmpty else { return "none" }
    return [
        requirements.contains(.preventSystemSleep) ? "preventSystemSleep" : nil,
        requirements.contains(.preventDisplaySleep) ? "preventDisplaySleep" : nil,
    ]
    .compactMap { $0 }
    .joined(separator: ",")
}
