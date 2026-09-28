/* 
 * MCP Orphan Reaper actor — classification engine + explicit, observable reap.
 *
 * Classification rules (per MCP-SPRAWL-OPS.md §3):
 *  - `parentPID == 1` or parent not in the live process map → orphaned.
 *  - Parent alive and itself MCP-looking → walk up one level (uvx wrapper
 *    pattern: uv tool → python child). If the grandparent chain ends at a
 *    dead broker, the whole chain is orphaned.
 *  - Parent alive and a session broker (claude/cursor/codex/hermes/node
 *    CLI hosts) → owned, never touched.
 *
 * Every run is dry-run by default; `apply: true` sends SIGTERM then SIGKILL
 * escalation for survivors, logging each PID to OSLog for fleet telemetry.
 */

import Foundation
import os

/// Injectable process-table view: all live PIDs → command, for parent checks.
public protocol MCPProcessTableProviding: Sendable {
    /// Map of live pid → command line (may be empty in hermetic tests).
    func liveProcessTable() -> [pid_t: String]
}

/// Hermetic default: empty table (tests inject fixtures).
public struct NullMCPProcessTable: MCPProcessTableProviding {
    public init() {}
    public func liveProcessTable() -> [pid_t: String] {
        [:]
    }
}

/// Production enumerator: one `ps -axo pid=,ppid=,rss=,command=` pass.
public struct ShellMCPProcessTable: MCPProcessTableProviding {
    public init() {}

    public func liveProcessTable() -> [pid_t: String] {
        let rows = Self.snapshotRows()
        var table: [pid_t: String] = [:]
        for row in rows {
            table[row.pid] = row.command
        }
        return table
    }

    /// All rows with parentage — shared with the reaper for candidate scans.
    public static func snapshotRows() -> [MCPProcessParentSnapshot] {
        guard let output = try? ConcurrentProcess.run(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,ppid=,rss=,command="]
        ), output.status == 0,
        let text = String(data: output.stdout, encoding: .utf8)
        else { return [] }
        return parse(text)
    }

    /// Parse `ps -axo pid=,ppid=,rss=,command=` rows.
    public static func parse(_ text: String) -> [MCPProcessParentSnapshot] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let parts = trimmed.split(maxSplits: 3, whereSeparator: { $0.isWhitespace })
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]),
                  let rssKB = Double(parts[2])
            else { return nil }
            return MCPProcessParentSnapshot(
                pid: pid,
                parentPID: ppid,
                command: String(parts[3]),
                memoryMB: rssKB / 1024.0
            )
        }
    }
}

/// The reaper. Actor-isolated; classification is pure and testable.
public actor MCPOrphanReaper {
    private let logger = Logger(subsystem: "dev.andromeda.fleet", category: "infra.mcp.reap")

    /// Commands that mark a live process as a session broker worth keeping.
    /// If an MCP server's parent matches one of these, it is owned.
    /// `claude.app/contents/helpers` makes the Claude desktop app's
    /// `.../Helpers/disclaimer --pgroup ...` intermediate an explicit broker
    /// stop — previously it only matched via the loose `claude` substring.
    private static let brokerNeedles = [
        "claude", "cursor", "codex", "hermes", "cmux", "node_modules/.bin",
        "electron", "claude.exe", "claude.app/contents/helpers",
    ]

    /// Commands that mark a process as an MCP transport wrapper (walk up past it).
    private static let wrapperNeedles = ["uv tool", "uvx", "npm exec", "npx"]

    // MARK: - Classification

    /// Classify one candidate against a live process table.
    public func classify(
        _ process: MCPProcessParentSnapshot,
        processTable: [pid_t: String]
    ) -> MCPOrphanClassification {
        // Parent is launchd → broker died, child got reparented. Classic orphan.
        if process.parentPID <= 1 {
            return MCPOrphanClassification(
                process: process,
                verdict: .orphaned(reason: "reparented to launchd (ppid \(process.parentPID)) — broker is gone")
            )
        }

        // Parent alive?
        guard let parentCommand = processTable[process.parentPID] else {
            return MCPOrphanClassification(
                process: process,
                verdict: .orphaned(reason: "parent \(process.parentPID) not in live table — broker is gone")
            )
        }

        // Parent alive and itself an MCP transport wrapper (uvx/npm-exec) →
        // the real broker is the grandparent; recurse one level.
        let loweredParent = parentCommand.lowercased()
        if Self.wrapperNeedles.contains(where: { loweredParent.contains($0) }) {
            // Find the wrapper's own row to inspect its parent.
            if let wrapperRow = processTable.first(where: { $0.key == process.parentPID }) {
                // We need the wrapper's ppid, which the table lacks — treat
                // candidates whose wrapper parent we cannot resolve as unknown.
                // The CLI path passes full rows; see classify(rows:).
                return MCPOrphanClassification(
                    process: process,
                    verdict: .unknown(reason: "parent is transport wrapper; use classify(rows:) for chain walks")
                )
            }
        }

        // Parent alive and a session broker → owned.
        if Self.brokerNeedles.contains(where: { loweredParent.contains($0) }) {
            return MCPOrphanClassification(
                process: process,
                verdict: .owned(brokerPID: process.parentPID, brokerCommand: parentCommand)
            )
        }

        // Parent alive but not a known broker and not a wrapper — unknown.
        return MCPOrphanClassification(
            process: process,
            verdict: .unknown(reason: "live parent \(process.parentPID) is neither broker nor wrapper: \(parentCommand.prefix(80))")
        )
    }

    /// Full-table classification: walks wrapper chains correctly using full rows.
    /// Returns classifications for every MCP-looking process.
    public func classifyRows(
        _ rows: [MCPProcessParentSnapshot]
    ) -> [MCPOrphanClassification] {
        let table = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0.command) })
        let parentOf: [pid_t: pid_t] = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0.parentPID) })

        return rows.filter { Self.looksLikeMCP($0.command) }.map { row in
            // Walk up at most 3 hops: server → wrapper (uvx/npm) → broker.
            var current = row
            var hops = 0
            while hops < 3 {
                if current.parentPID <= 1 {
                    return MCPOrphanClassification(
                        process: row,
                        verdict: .orphaned(reason: "chain reparented to launchd (ppid 1) — broker is gone")
                    )
                }
                guard let parentCommand = table[current.parentPID] else {
                    return MCPOrphanClassification(
                        process: row,
                        verdict: .orphaned(reason: "ancestor \(current.parentPID) not in live table — broker is gone")
                    )
                }
                let lowered = parentCommand.lowercased()
                if Self.brokerNeedles.contains(where: { lowered.contains($0) }) {
                    return MCPOrphanClassification(
                        process: row,
                        verdict: .owned(brokerPID: current.parentPID, brokerCommand: parentCommand)
                    )
                }
                if Self.wrapperNeedles.contains(where: { lowered.contains($0) }) {
                    // Walk up past the wrapper.
                    guard let grandparentPID = parentOf[current.parentPID] else {
                        return MCPOrphanClassification(
                            process: row,
                            verdict: .orphaned(reason: "wrapper \(current.parentPID) has no live parent — broker is gone")
                        )
                    }
                    current = MCPProcessParentSnapshot(
                        pid: current.parentPID,
                        parentPID: grandparentPID,
                        command: parentCommand,
                        memoryMB: 0
                    )
                    hops += 1
                    continue
                }
                return MCPOrphanClassification(
                    process: row,
                    verdict: .unknown(reason: "ancestor \(current.parentPID) unrecognized: \(parentCommand.prefix(80))")
                )
            }
            return MCPOrphanClassification(
                process: row,
                verdict: .unknown(reason: "wrapper chain deeper than 3 hops — refusing to guess")
            )
        }
    }

    /// Reuse the registry's MCP heuristic so both surfaces agree on "MCP-looking".
    public static func looksLikeMCP(_ command: String) -> Bool {
        ShellMCPProcessEnumerator.looksLikeMCP(command)
    }

    // MARK: - Reap

    /// Signal a process like `kill(2)`. Injectable so tests can simulate
    /// failure paths (dead pids, EPERM) without manufacturing real victims.
    public typealias SignalClosure = @Sendable (_ pid: pid_t, _ signal: Int32) -> Int32

    /// Production default: Darwin `kill(2)`.
    private let signal: SignalClosure

    public init(signal: @escaping SignalClosure = { pid, sig in kill(pid, sig) }) {
        self.signal = signal
    }

    /// Classify and (optionally) reap. Dry-run unless `apply` is true.
    /// `sparePIDs` is an operator allowlist: orphans whose pid is in the set
    /// are still classified `orphaned` (visible in `orphanCount`/telemetry)
    /// but are never signaled and land in `report.spared` instead.
    public func reap(
        rows: [MCPProcessParentSnapshot],
        apply: Bool,
        sparePIDs: Set<pid_t> = []
    ) async -> MCPReapReport {
        let classifications = classifyRows(rows)
        let orphanPIDs = classifications.compactMap { entry -> pid_t? in
            if case .orphaned = entry.verdict {
                return entry.process.pid
            }
            return nil
        }

        // Policy allowlist takes precedence: spared orphans are reported, never signaled.
        let spared = orphanPIDs.filter { sparePIDs.contains($0) }
        let signalable = orphanPIDs.filter { !sparePIDs.contains($0) }

        guard apply, !signalable.isEmpty else {
            return MCPReapReport(
                dryRun: !apply,
                classifications: classifications,
                reaped: [],
                failed: [],
                spared: spared
            )
        }

        var reaped: [pid_t] = []
        var failed: [pid_t] = []
        for pid in signalable {
            // SIGTERM first (graceful MCP shutdown), then verify and escalate —
            // the 2026-09-27 epidemic showed uvx wrappers surviving SIGTERM.
            guard signal(pid, SIGTERM) == 0 else {
                failed.append(pid)
                logger.error("failed to signal orphan MCP pid \(pid, privacy: .public): errno \(String(cString: strerror(errno)), privacy: .public)")
                continue
            }
            try? await Task.sleep(for: .milliseconds(300))
            if signal(pid, 0) == 0 {
                // Still alive — escalate.
                if signal(pid, SIGKILL) == 0 {
                    logger.notice("escalated orphan MCP pid \(pid, privacy: .public) to SIGKILL")
                } else if errno != ESRCH {
                    failed.append(pid)
                    logger.error("SIGKILL failed for pid \(pid, privacy: .public): errno \(String(cString: strerror(errno)), privacy: .public)")
                    continue
                }
            }
            reaped.append(pid)
            logger.notice("reaped orphan MCP pid \(pid, privacy: .public)")
        }

        return MCPReapReport(
            dryRun: false,
            classifications: classifications,
            reaped: reaped,
            failed: failed,
            spared: spared
        )
    }
}
