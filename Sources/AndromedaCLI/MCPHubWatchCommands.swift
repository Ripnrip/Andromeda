import ArgumentParser
import Foundation
import MemoryKit

// Why this file exists: `andromeda mcp-hub watch` is the bounded foreground
// surveillance loop for orphan drift — the anti-daemon counterpart to the
// one-shot `reap`. It ALWAYS exits after `--cycles` iterations; restart
// policy belongs to launchd/KeepAlive, never to this process (AGENTS.md:
// no invisible daemons). Presentation goes to stdout for the terminal user;
// every classification decision is mirrored to OSLog `infra.mcp.watch` by
// MCPWatchTower for fleet telemetry.

extension MCPHubCommand {
    /// `andromeda mcp-hub watch` — cycle orphan classification for a bounded
    /// number of iterations, then exit. Dry-run unless `--apply`.
    struct Watch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Watch for orphaned MCP servers on a fixed cycle (bounded foreground run — never a daemon). Dry-run unless --apply."
        )

        @Option(help: "Seconds between cycles (default 60).")
        var interval: Double = 60

        @Option(help: "Hard bound on cycles before exit (default 10; the watch NEVER loops forever).")
        var cycles: Int = 10

        @Flag(help: "Reap orphans each cycle. Without this, observe and report only.")
        var apply: Bool = false

        @Option(
            parsing: .upToNextOption,
            help: "PIDs to spare even if classified orphaned (intentional PPID-1 daemons, e.g. the claude-mem worker). Repeatable. Applies to every cycle."
        )
        var spare: [Int32] = []

        func run() async throws {
            guard cycles >= 1 else {
                throw ValidationError("--cycles must be >= 1 (bounded run, not zero)")
            }
            guard interval > 0 else {
                throw ValidationError("--interval must be > 0 seconds")
            }

            MCPHubCommand.diagnostics.notice(
                "watch start: cycles=\(cycles, privacy: .public) interval=\(interval, privacy: .public)s apply=\(apply, privacy: .public) spared=\(spare.count, privacy: .public)"
            )

            let tower = MCPWatchTower()
            let summary = await tower.watch(
                maxCycles: cycles,
                interval: .seconds(interval),
                apply: apply,
                sparePIDs: Set(spare)
            )

            // Human-facing report — presentation, not logging.
            print("mcp-hub watch — \(summary.apply ? "APPLIED" : "DRY RUN"), \(summary.cycles.count) cycle(s) at \(String(format: "%.0f", interval))s")
            for cycle in summary.cycles {
                for entry in cycle.classifications {
                    let pid = entry.process.pid
                    let rss = String(format: "%.1f", entry.process.memoryMB)
                    switch entry.verdict {
                    case let .orphaned(reason):
                        if cycle.spared.contains(pid) {
                            print("  🛡️ [cycle \(cycle.index)] spared pid \(pid) (\(rss) MB) — orphaned but allowlisted — \(reason)")
                        } else {
                            print("  🧟 [cycle \(cycle.index)] orphaned pid \(pid) (\(rss) MB) — \(reason)")
                        }
                    case let .owned(brokerPID, brokerCommand):
                        print("  🔒 [cycle \(cycle.index)] owned pid \(pid) (\(rss) MB) — broker \(brokerPID): \(brokerCommand.prefix(60))")
                    case let .unknown(reason):
                        print("  ❓ [cycle \(cycle.index)] unknown pid \(pid) (\(rss) MB) — \(reason)")
                    }
                }
            }
            print(
                "total orphans: \(summary.totalOrphans) | reaped: \(summary.totalReaped) | failed: \(summary.totalFailed) | spared: \(summary.totalSpared) | peak drift: \(String(format: "%.1f", summary.peakOrphanedMemoryMB)) MB"
            )
            if summary.apply {
                MCPHubCommand.diagnostics.notice(
                    "watch done: reaped=\(summary.totalReaped, privacy: .public) failed=\(summary.totalFailed, privacy: .public)"
                )
            } else if summary.totalOrphans > 0 {
                print("⚠️ dry-run: re-run with --apply to reap the orphans above.")
            }
            if summary.apply, summary.totalFailed > 0 {
                print("❌ \(summary.totalFailed) signal(s) failed during apply — see infra.mcp.watch logs.")
            }
        }
    }
}
