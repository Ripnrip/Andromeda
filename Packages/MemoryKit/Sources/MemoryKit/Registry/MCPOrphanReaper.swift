/**
 * MCP Orphan Reaper types — classification and report models.
 *
 * Backs `infra.mcp.reap`: identifies MCP server processes whose broker
 * (Claude/Cursor/Codex/Hermes session) is dead and reports/reaps them.
 * The observe-only `MCPServerRegistry` stays observe-only; the reaper actor
 * owns the lifecycle side.
 */

import Foundation

// MARK: - Process snapshot with parentage

/// One live process row relevant to orphan classification.
public struct MCPProcessParentSnapshot: Sendable, Equatable {
    public let pid: pid_t
    public let parentPID: pid_t
    public let command: String
    public let memoryMB: Double

    public init(pid: pid_t, parentPID: pid_t, command: String, memoryMB: Double) {
        self.pid = pid
        self.parentPID = parentPID
        self.command = command
        self.memoryMB = memoryMB
    }
}

// MARK: - Classification

/// Verdict for one MCP-looking process.
public enum MCPOrphanVerdict: Sendable, Equatable {
    /// Parent chain is dead (ppid 1 / parent gone) — safe to reap.
    case orphaned(reason: String)
    /// A live broker owns this process — never touch.
    case owned(brokerPID: pid_t, brokerCommand: String)
    /// Looks like an MCP server but not confidently classified — leave alone.
    case unknown(reason: String)
}

/// Full classification result for one candidate.
public struct MCPOrphanClassification: Sendable, Equatable {
    public let process: MCPProcessParentSnapshot
    public let verdict: MCPOrphanVerdict

    public init(process: MCPProcessParentSnapshot, verdict: MCPOrphanVerdict) {
        self.process = process
        self.verdict = verdict
    }
}

// MARK: - Reap report

/// One reaper run: what it saw, what it classified, what it did.
public struct MCPReapReport: Sendable, Equatable {
    public let ranAt: Date
    public let dryRun: Bool
    public let classifications: [MCPOrphanClassification]
    public let reaped: [pid_t]
    public let failed: [pid_t]

    /// Orphans found regardless of whether we acted.
    public var orphanCount: Int {
        classifications.filter {
            if case .orphaned = $0.verdict { return true }
            return false
        }.count
    }

    /// Estimated memory (MB) held by classified orphans, from RSS at reap time.
    public var reclaimedMemoryMB: Double {
        classifications
            .filter {
                if case .orphaned = $0.verdict { return true }
                return false
            }
            .reduce(0) { $0 + $1.process.memoryMB }
    }

    public init(
        ranAt: Date = Date(),
        dryRun: Bool,
        classifications: [MCPOrphanClassification],
        reaped: [pid_t],
        failed: [pid_t]
    ) {
        self.ranAt = ranAt
        self.dryRun = dryRun
        self.classifications = classifications
        self.reaped = reaped
        self.failed = failed
    }
}
