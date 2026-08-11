import Foundation

/// Supervisor-owned, reference-counted power lease manager.
///
/// Agents and jobs should request logical leases from this actor rather than
/// talking to ProcessInfo, caffeinate, or IOKit directly.
public actor PowerAssertionManager {
    private let backend: any PowerAssertionBackend
    private let eventSink: any PowerEventSink
    private var leases: [UUID: PowerLease] = [:]
    private var aggregateState = AggregateState()

    public init(
        backend: any PowerAssertionBackend = ProcessInfoPowerAssertionBackend(),
        eventSink: any PowerEventSink = NoopPowerEventSink()
    ) {
        self.backend = backend
        self.eventSink = eventSink
    }

    @discardableResult
    public func acquire(
        owner: String,
        reason: String,
        requirements: PowerRequirement
    ) async -> PowerLease {
        let lease = PowerLease(
            owner: owner,
            reason: reason,
            requirements: requirements
        )

        leases[lease.id] = lease
        await reconcile()

        await eventSink.emit(
            .acquired(lease, activeLeaseCount: leases.count)
        )

        return lease
    }

    public func release(_ lease: PowerLease) async {
        guard let removed = leases.removeValue(forKey: lease.id) else {
            return
        }

        await reconcile()

        await eventSink.emit(
            .released(removed, activeLeaseCount: leases.count)
        )
    }

    public func release(id: UUID) async {
        guard let lease = leases[id] else { return }
        await release(lease)
    }

    public func releaseAll() async {
        let current = Array(leases.values)
        leases.removeAll()
        await reconcile()

        for lease in current {
            await eventSink.emit(
                .released(lease, activeLeaseCount: leases.count)
            )
        }
    }

    public func activeLeases() -> [PowerLease] {
        leases.values.sorted { $0.acquiredAt < $1.acquiredAt }
    }

    public func status() -> PowerAssertionStatus {
        PowerAssertionStatus(
            activeLeases: activeLeases(),
            preventSystemSleep: aggregateState.preventSystemSleep,
            preventDisplaySleep: aggregateState.preventDisplaySleep
        )
    }

    private func reconcile() async {
        let next = AggregateState(
            preventSystemSleep: leases.values.contains {
                $0.requirements.contains(.preventSystemSleep)
            },
            preventDisplaySleep: leases.values.contains {
                $0.requirements.contains(.preventDisplaySleep)
            }
        )

        guard next != aggregateState else { return }
        aggregateState = next

        if next.preventSystemSleep || next.preventDisplaySleep {
            let owners = Set(leases.values.map(\.owner)).sorted().joined(separator: ", ")
            let reason = owners.isEmpty
                ? "Andromeda background work"
                : "Andromeda active jobs: \(owners)"

            await backend.apply(
                preventSystemSleep: next.preventSystemSleep,
                preventDisplaySleep: next.preventDisplaySleep,
                reason: reason
            )
        } else {
            await backend.clear()
        }

        await eventSink.emit(
            .assertionChanged(
                systemSleepPrevented: next.preventSystemSleep,
                displaySleepPrevented: next.preventDisplaySleep,
                activeLeaseCount: leases.count
            )
        )
    }
}

public struct PowerAssertionStatus: Sendable {
    public let activeLeases: [PowerLease]
    public let preventSystemSleep: Bool
    public let preventDisplaySleep: Bool
}

private struct AggregateState: Equatable {
    var preventSystemSleep = false
    var preventDisplaySleep = false
}
