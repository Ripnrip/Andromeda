import AndromedaPowerKit
import Foundation

/// Supervisor-owned power lease coordinator.
///
/// Wraps `PowerAssertionManager` and bridges its events into Andromeda's
/// diagnostic / event layer.  Exactly one instance should exist per host —
/// the supervisor, not individual agents, owns macOS power state.
public actor PowerLeaseCoordinator {
    private let manager: PowerAssertionManager
    private let recorder: PowerEventRecorder

    public init(backend: any PowerAssertionBackend = ProcessInfoPowerAssertionBackend()) {
        let recorder = PowerEventRecorder()
        self.recorder = recorder
        self.manager = PowerAssertionManager(
            backend: backend,
            eventSink: recorder
        )
    }

    // MARK: - Lease lifecycle

    @discardableResult
    public func acquire(
        owner: String,
        reason: String,
        requirements: PowerRequirement
    ) async -> PowerLease {
        await manager.acquire(owner: owner, reason: reason, requirements: requirements)
    }

    public func release(_ lease: PowerLease) async {
        await manager.release(lease)
    }

    public func releaseAll() async {
        await manager.releaseAll()
    }

    /// Scoped lease: acquires before the operation, releases on success or failure.
    public func withLease<T: Sendable>(
        owner: String,
        reason: String,
        requirements: PowerRequirement,
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        let lease = await manager.acquire(owner: owner, reason: reason, requirements: requirements)
        do {
            let value = try await operation()
            await manager.release(lease)
            return value
        } catch {
            await manager.release(lease)
            throw error
        }
    }

    // MARK: - Status / doctor

    public func status() async -> PowerAssertionStatus {
        await manager.status()
    }

    /// Captured power events for the HUD / doctor — newest last.
    public func eventLog() async -> [PowerEventRecord] {
        await recorder.records
    }

    /// Lightweight summary for doctor checklist.
    public func summary() async -> PowerLeaseSummary {
        PowerLeaseSummary(from: await manager.status())
    }

    /// Default path where a long-lived supervisor writes power status snapshots
    /// for one-shot CLI consumers like `andromeda doctor`.
    public static let statusFilePath = ".andromeda/power-status.json"

    /// Write a status snapshot to the default path for doctor / HUD consumption.
    /// The long-lived supervisor should call this after every lease change.
    public func writeStatusSnapshot(to path: String? = nil) async {
        let summary = await self.summary()
        let target = path ?? Self.statusFilePath
        let dir = (target as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let payload: [String: Any] = [
            "activeLeaseCount": summary.activeLeaseCount,
            "preventSystemSleep": summary.preventSystemSleep,
            "preventDisplaySleep": summary.preventDisplaySleep,
            "owners": summary.owners,
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        ) {
            try? data.write(to: URL(fileURLWithPath: (NSHomeDirectory() as NSString)
                .appendingPathComponent(target)))
        }
    }

    /// Human-readable doctor summary of current power state.
    public func doctorSection() async -> String {
        let s = await manager.status()
        var lines: [String] = [
            "Power Assertions",
            String(repeating: "-", count: 32),
        ]

        if s.activeLeases.isEmpty {
            lines.append("Andromeda leases:       0")
            lines.append("Prevent system sleep:   no")
            lines.append("Prevent display sleep:  no")
        } else {
            lines.append("Andromeda leases:       \(s.activeLeases.count)")
            lines.append("Prevent system sleep:   \(s.preventSystemSleep ? "yes" : "no")")
            lines.append("Prevent display sleep:  \(s.preventDisplaySleep ? "yes" : "no")")
            lines.append("")
            lines.append("Owners:")
            for lease in s.activeLeases {
                lines.append("  \(lease.owner.padded(to: 20)) \(lease.reason)")
            }
        }

        lines.append("")
        lines.append("macOS assertion backend: ProcessInfo")

        return lines.joined(separator: "\n")
    }

    /// Read a status snapshot written by a long-lived supervisor.
    /// Returns nil when no snapshot exists (e.g., supervisor not running).
    public static func readStatusSnapshot(from path: String? = nil) -> PowerLeaseSummary? {
        let target = path ?? statusFilePath
        let full = (NSHomeDirectory() as NSString).appendingPathComponent(target)
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: full)),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        guard let count = json["activeLeaseCount"] as? Int,
              let system = json["preventSystemSleep"] as? Bool,
              let display = json["preventDisplaySleep"] as? Bool
        else {
            return nil
        }
        let owners = (json["owners"] as? [String]) ?? []
        return PowerLeaseSummary(
            activeLeaseCount: count,
            preventSystemSleep: system,
            preventDisplaySleep: display,
            owners: owners
        )
    }
}

// MARK: - Summary for doctor / HUD

/// Lightweight summary of power lease state for doctor checklists.
public struct PowerLeaseSummary: Sendable, Equatable {
    public let activeLeaseCount: Int
    public let preventSystemSleep: Bool
    public let preventDisplaySleep: Bool
    public let owners: [String]

    public init(activeLeaseCount: Int, preventSystemSleep: Bool,
                preventDisplaySleep: Bool, owners: [String]) {
        self.activeLeaseCount = activeLeaseCount
        self.preventSystemSleep = preventSystemSleep
        self.preventDisplaySleep = preventDisplaySleep
        self.owners = owners
    }

    /// Construct from a `PowerAssertionStatus` (from the PowerKit package).
    public init(from status: PowerAssertionStatus) {
        self.activeLeaseCount = status.activeLeases.count
        self.preventSystemSleep = status.preventSystemSleep
        self.preventDisplaySleep = status.preventDisplaySleep
        self.owners = status.activeLeases.map(\.owner).sorted()
    }
}

// MARK: - Event recording

/// A single captured power event, useful for HUD display and test assertions.
public struct PowerEventRecord: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case acquired
        case released
        case assertionChanged
    }

    public let kind: Kind
    public let owner: String?
    public let reason: String?
    public let leaseID: UUID?
    public let systemSleepPrevented: Bool?
    public let displaySleepPrevented: Bool?
    public let activeLeaseCount: Int
    public let timestamp: Date

    public init(kind: Kind, owner: String? = nil, reason: String? = nil,
                leaseID: UUID? = nil, systemSleepPrevented: Bool? = nil,
                displaySleepPrevented: Bool? = nil, activeLeaseCount: Int,
                timestamp: Date = Date()) {
        self.kind = kind
        self.owner = owner
        self.reason = reason
        self.leaseID = leaseID
        self.systemSleepPrevented = systemSleepPrevented
        self.displaySleepPrevented = displaySleepPrevented
        self.activeLeaseCount = activeLeaseCount
        self.timestamp = timestamp
    }
}

/// Records all power events into an array for diagnostic / HUD consumption.
public actor PowerEventRecorder: PowerEventSink {
    public private(set) var records: [PowerEventRecord] = []

    public init() {}

    public func emit(_ event: PowerEvent) async {
        switch event {
        case let .acquired(lease, activeLeaseCount):
            records.append(.init(
                kind: .acquired,
                owner: lease.owner,
                reason: lease.reason,
                leaseID: lease.id,
                activeLeaseCount: activeLeaseCount
            ))

        case let .released(lease, activeLeaseCount):
            records.append(.init(
                kind: .released,
                owner: lease.owner,
                reason: lease.reason,
                leaseID: lease.id,
                activeLeaseCount: activeLeaseCount
            ))

        case let .assertionChanged(system, display, activeLeaseCount):
            records.append(.init(
                kind: .assertionChanged,
                systemSleepPrevented: system,
                displaySleepPrevented: display,
                activeLeaseCount: activeLeaseCount
            ))
        }
    }

    public func clear() {
        records.removeAll()
    }
}

// MARK: - Helpers

private extension String {
    func padded(to length: Int) -> String {
        if count >= length { return self }
        return self + String(repeating: " ", count: length - count)
    }
}
