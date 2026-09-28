import AndromedaMCPHub
import ArgumentParser
import Foundation
import Logging
import MemoryKit

#if canImport(OSLog)
    import os
#endif
struct MCPHubCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp-hub",
        abstract: "Shared MCP hub: validate, status, and orphan lifecycle.",
        subcommands: [Run.self, Validate.self, Status.self, Reap.self, Watch.self],
        defaultSubcommand: Status.self
    )

    // MARK: - Common

    /// One logger for every subcommand's diagnostics — os.Logger, not
    /// print(), so hub CLI lines land in the unified log (queryable,
    /// leveled, privacy-aware) exactly like the library's own telemetry.
    /// print() stays ONLY for the human-facing table output a terminal
    /// user reads (status lines, validation report) — presentation, not
    /// logging.
    static let diagnostics = os.Logger(subsystem: "ai.andromeda.mcp-hub", category: "cli")

    static func loadConfiguration(path: String?) throws -> MCPHubConfiguration {
        let resolved = path ?? MCPHubConfiguration.defaultPath
        guard FileManager.default.fileExists(
            atPath: (resolved as NSString).expandingTildeInPath
        ) else {
            throw ValidationError(
                "no hub config at \(resolved) — see docs/adr/ADR-0019-mcp-hub-config-schema.md"
            )
        }
        do {
            return try MCPHubConfiguration.load(from: resolved)
        } catch let error as MCPHubConfiguration.ConfigurationError {
            diagnostics.error("💥 invalid hub config: \(String(describing: error), privacy: .public)")
            throw ValidationError("invalid hub config: \(error)")
        }
    }

    // MARK: - Subcommands

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run the hub daemon (launchd entry — KeepAlive owns restarts)."
        )

        @Option(help: "Path to servers.json (default ~/.andromeda/mcp-hub/servers.json).")
        var config: String?

        func run() async throws {
            let configuration = try MCPHubCommand.loadConfiguration(path: config)
            let hub = MCPHub(configuration: configuration)
            do {
                try hub.start()
            } catch let error as MCPHub.MCPHubError {
                throw ValidationError("hub failed to start: \(error)")
            }
            // Keep alive; readability handlers do the work.
            print("mcp-hub: hosting \(configuration.servers.count) server(s) — sockets in \(configuration.socketDirectory)")
            // Cancellation-aware forever-sleep (Codex round 3): sleeping on
            // .seconds(Double.greatestFiniteMagnitude) traps converting to
            // Duration (_Int128 out of range) — a nan-value loop suspends
            // without any conversion and still never spins.
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: UInt64.max)
            }
        }
    }

    struct Validate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Validate servers.json against the ADR-0019 invariants."
        )

        @Option(help: "Path to servers.json.")
        var config: String?

        func run() async throws {
            let configuration = try MCPHubCommand.loadConfiguration(path: config)
            var allHealthy = true
            for server in configuration.servers {
                let executableExists = FileManager.default.isExecutableFile(
                    atPath: (server.command as NSString).expandingTildeInPath
                )
                let marker = executableExists ? "✅" : "❌"
                let renderedArguments = server.arguments.joined(separator: " ")
                print(
                    "\(marker) \(server.id) — \(server.packageName) [\(server.placement.rawValue)]"
                        + " → \(server.command) \(renderedArguments)"
                )
                if !executableExists {
                    allHealthy = false
                    print("     ⚠️ executable not found/resolvable — hub spawn would fail")
                }
            }
            if !allHealthy {
                throw ValidationError("one or more executables unresolved — fix before install (Codex P2)")
            }
        }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show hub socket census (up + accepting, or down)."
        )

        @Option(help: "Path to servers.json.")
        var config: String?

        func run() async throws {
            let configuration = try MCPHubCommand.loadConfiguration(path: config)
            for server in configuration.servers {
                let socketPath = configuration.socketPath(for: server.id)
                let probe = HubSocketProbe.probeListening(path: socketPath)
                let marker = probe.isListening ? "🟢" : "⚪️"
                print("\(marker) \(server.id) — \(socketPath)\(probe.isListening ? " (listening)" : " (no hub)")")
                if let refusal = probe.refusalReason {
                    // ⚪️ the census says down — WHY it says down is a
                    // decision point that belongs in the unified log.
                    MCPHubCommand.diagnostics.notice(
                        "⚪️ socket probe not listening: \(refusal, privacy: .public)"
                    )
                }
            }
            let telemetryPath = configuration.telemetryLogPath
            print("📊 telemetry: \(telemetryPath)")
        }
    }
}

// MARK: - Orphan reap

extension MCPHubCommand {
    /// `andromeda mcp-hub reap` — classify orphaned MCP servers and reap them.
    /// Dry-run by default; `--apply` sends signals. Every decision is logged
    /// to the unified log (`infra.mcp.reap`) per fleet visibility rules.
    struct Reap: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Find orphaned MCP servers (dead-broker zombies) and reap them. Dry-run unless --apply."
        )

        @Flag(help: "Actually send SIGTERM/SIGKILL. Without this, classify and report only.")
        var apply: Bool = false

        @Option(
            parsing: .upToNextOption,
            help: "PIDs to spare even if classified orphaned (intentional PPID-1 daemons, e.g. the claude-mem worker). Repeatable."
        )
        var spare: [Int32] = []

        func run() async throws {
            let reaper = MCPOrphanReaper()
            let rows = ShellMCPProcessTable.snapshotRows()
            let report = await reaper.reap(rows: rows, apply: apply, sparePIDs: Set(spare))

            print("mcp-hub reap — \(report.dryRun ? "DRY RUN" : "APPLIED") at \(report.ranAt.formatted(.iso8601))")
            print("scanned MCP-looking processes: \(report.classifications.count)")
            for entry in report.classifications {
                let pid = entry.process.pid
                let rss = String(format: "%.1f", entry.process.memoryMB)
                switch entry.verdict {
                case let .orphaned(reason):
                    if report.spared.contains(pid) {
                        print("  🛡️ spared pid \(pid) (\(rss) MB) — orphaned but allowlisted — \(reason)")
                    } else {
                        print("  🧟 orphaned pid \(pid) (\(rss) MB) — \(reason)")
                    }
                case let .owned(brokerPID, brokerCommand):
                    print("  🔒 owned pid \(pid) (\(rss) MB) — broker \(brokerPID): \(brokerCommand.prefix(60))")
                case let .unknown(reason):
                    print("  ❓ unknown pid \(pid) (\(rss) MB) — \(reason)")
                }
            }
            print("orphans: \(report.orphanCount) | reaped: \(report.reaped.count) | failed: \(report.failed.count) | spared: \(report.spared.count)")
            if report.orphanCount > 0, report.reaped.isEmpty, report.spared.isEmpty {
                print("⚠️ dry-run: re-run with --apply to reap the orphans above.")
            }
        }
    }
}
