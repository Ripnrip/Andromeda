/* 
 * MCP Watch Tower — bounded, foreground orphan-drift surveillance.
 *
 * Backs `infra.mcp watch`: repeatedly snapshots the process table,
 * classifies MCP-looking processes with the reaper, and (optionally) reaps
 * orphans each cycle — for a FIXED number of cycles, then exits.
 *
 * AGENTS.md canon: NO invisible daemons. A watch that never exits is a
 * daemon wearing a command's clothes. Every run is bounded by `maxCycles`;
 * launchd/KeepAlive owns restart policy, not this process. Each cycle is
 * logged to OSLog (`infra.mcp.watch`) so fleet telemetry sees the drift
 * curve, not just the terminal output.
 */

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
        failed: [pid_t]
    ) {
        self.index = index
        self.ranAt = ranAt
        self.classifications = classifications
        self.reaped = reaped
        self.failed = failed
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
    public func runCycle(
        rows: [MCPProcessParentSnapshot],
        apply: Bool,
        index: Int
    ) async -> MCPWatchCycle {
        let report = await reaper.reap(rows: rows, apply: apply)
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
            failed: report.failed
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
    ///   - snapshot: process-table provider; production uses one `ps` pass
    ///     per cycle, tests inject fixtures.
    public func watch(
        maxCycles: Int,
        interval: Duration,
        apply: Bool,
        snapshot: @escaping @Sendable () -> [MCPProcessParentSnapshot] = {
            ShellMCPProcessTable.snapshotRows()
        }
    ) async -> MCPWatchSummary {
        let bound = max(1, maxCycles)
        var cycles: [MCPWatchCycle] = []
        cycles.reserveCapacity(bound)

        for index in 1 ... bound {
            let cycle = await runCycle(rows: snapshot(), apply: apply, index: index)
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
            startedAt: Date(),
            interval: interval,
            apply: apply,
            cycles: cycles
        )
    }
}
