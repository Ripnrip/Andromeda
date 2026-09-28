import Foundation
import os

// MARK: - Cycle result

/// One watch cycle: what the tower saw and (if applying) what it did.
public struct MCPWatchCycle: Sendable, Equatable {
    /// 1-based cycle number within the bounded run.
    public let index: Int
    public let ranAt: Date
    public let classifications: [MCPOrphanClassification]
    public let reaped: [pid_t]
    public let failed: [pid_t]
    /// Orphans spared by the allowlist this cycle — classified orphaned but
    /// intentionally NOT signaled, visible in the same stream as the kills.
    public let spared: [pid_t]

    /// Orphans classified this cycle, regardless of action taken.
    public var orphanCount: Int {
        classifications.filter {
            if case .orphaned = $0.verdict {
                return true
            }
            return false
        }.count
    }

    /// RSS (MB) held by this cycle's orphans at snapshot time.
    public var orphanedMemoryMB: Double {
        classifications
            .filter {
                if case .orphaned = $0.verdict {
                    return true
                }
                return false
            }
            .reduce(0) { $0 + $1.process.memoryMB }
    }

    public init(
        index: Int,
        ranAt: Date = Date(),
        classifications: [MCPOrphanClassification],
        reaped: [pid_t],
        failed: [pid_t],
        spared: [pid_t] = []
    ) {
        self.index = index
        self.ranAt = ranAt
        self.classifications = classifications
        self.reaped = reaped
        self.failed = failed
        self.spared = spared
    }
}

// MARK: - Run summary

/// Accumulated outcome of one bounded watch run.
public struct MCPWatchSummary: Sendable, Equatable {
    public let startedAt: Date
    public let interval: Duration
    public let apply: Bool
    public let cycles: [MCPWatchCycle]

    /// Orphans seen across all cycles (an orphan persisting across N cycles
    /// counts N times — drift visibility, not unique-PID counting).
    public var totalOrphans: Int {
        cycles.reduce(0) { $0 + $1.orphanCount }
    }

    /// Reap actions that succeeded (apply mode only).
    public var totalReaped: Int {
        cycles.reduce(0) { $0 + $1.reaped.count }
    }

    /// Reap actions that failed (apply mode only).
    public var totalFailed: Int {
        cycles.reduce(0) { $0 + $1.failed.count }
    }

    /// Orphans spared by the allowlist across all cycles (never signaled,
    /// visible all the same — same contract as the one-shot reap path).
    public var totalSpared: Int {
        cycles.reduce(0) { $0 + $1.spared.count }
    }

    /// Peak single-cycle orphan RSS observed during the run.
    public var peakOrphanedMemoryMB: Double {
        cycles.map(\.orphanedMemoryMB).max() ?? 0
    }

    public init(
        startedAt: Date = Date(),
        interval: Duration,
        apply: Bool,
        cycles: [MCPWatchCycle]
    ) {
        self.startedAt = startedAt
        self.interval = interval
        self.apply = apply
        self.cycles = cycles
    }
}

// MARK: - Tower

/// The watch tower. Actor-isolated; each cycle delegates classification and
/// reap policy to `MCPOrphanReaper` so watch and one-shot reap can never
/// disagree about what counts as an orphan.
public actor MCPWatchTower {
    private let logger = Logger(subsystem: "dev.andromeda.fleet", category: "infra.mcp.watch")
    private let reaper: MCPOrphanReaper

    public init(reaper: MCPOrphanReaper = MCPOrphanReaper()) {
        self.reaper = reaper
    }

    /// Run ONE cycle against an explicit snapshot — the pure, clock-free
    /// core that tests drive and `watch(cycles:)` calls per tick.
    /// `sparePIDs` flows to the reaper: spared orphans stay visible but are
    /// never signaled (review blocker #1 — watch and reap share one safety
    /// posture, no drift between the two kill surfaces).
    public func runCycle(
        rows: [MCPProcessParentSnapshot],
        apply: Bool,
        index: Int,
        sparePIDs: Set<pid_t> = []
    ) async -> MCPWatchCycle {
        let report = await reaper.reap(rows: rows, apply: apply, sparePIDs: sparePIDs)
        if report.orphanCount > 0 {
            logger.notice(
                "cycle \(index, privacy: .public): \(report.orphanCount, privacy: .public) orphan(s), \(String(format: "%.1f", report.reclaimedMemoryMB), privacy: .public) MB drift"
            )
        } else {
            logger.info("cycle \(index, privacy: .public): no orphans")
        }
        return MCPWatchCycle(
            index: index,
            ranAt: Date(),
            classifications: report.classifications,
            reaped: report.reaped,
            failed: report.failed,
            spared: report.spared
        )
    }

    /// BOUNDED foreground watch: exactly `maxCycles` cycles (clamped to >= 1),
    /// sleeping `interval` between ticks, then returns. Never loops forever —
    /// restart policy belongs to launchd, not to this process.
    ///
    /// - Parameters:
    ///   - maxCycles: hard upper bound on iterations; the run always exits.
    ///   - interval: sleep between cycles (no sleep after the final cycle).
    ///   - apply: pass through to the reaper — `false` observes only.
    ///   - sparePIDs: operator allowlist threaded to every cycle's reap.
    ///   - snapshot: process-table provider; production uses one `ps` pass
    ///     per cycle, tests inject fixtures.
    public func watch(
        maxCycles: Int,
        interval: Duration,
        apply: Bool,
        sparePIDs: Set<pid_t> = [],
        snapshot: @escaping @Sendable () -> [MCPProcessParentSnapshot]? = {
            ShellMCPProcessTable.snapshotRows()
        }
    ) async -> MCPWatchSummary {
        let bound = max(1, maxCycles)
        let startedAt = Date() // captured at run start (review #7: end-of-run stamps lied)
        var cycles: [MCPWatchCycle] = []
        cycles.reserveCapacity(bound)

        for index in 1 ... bound {
            // LOUD ps failure (review #5): a nil snapshot is an environment
            // failure — record an empty failed-marker cycle and stop; never
            // report a dead ps as "zero orphans" clean sweep.
            guard let rows = snapshot() else {
                logger.error("cycle \(index, privacy: .public): ps snapshot FAILED — aborting watch (no false clean sweep)")
                break
            }
            let cycle = await runCycle(rows: rows, apply: apply, index: index, sparePIDs: sparePIDs)
            cycles.append(cycle)

            if let last = cycles.last, last.orphanCount > 0, last.reaped.isEmpty, apply {
                logger.error(
                    "cycle \(index, privacy: .public): \(last.orphanCount, privacy: .public) orphan(s) but 0 reaped — signals failing?"
                )
            }

            guard index < bound, !Task.isCancelled else { break }
            // Cancellation-aware tick: cooperative cancel ends the run early
            // (still bounded, never a hang).
            try? await Task.sleep(for: interval)
            if Task.isCancelled {
                break
            }
        }

        return MCPWatchSummary(
            startedAt: startedAt,
            interval: interval,
            apply: apply,
            cycles: cycles
        )
    }
}
