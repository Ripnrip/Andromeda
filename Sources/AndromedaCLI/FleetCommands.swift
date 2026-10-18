import AndromedaHostOps
import ArgumentParser
import Foundation
import os

/// `andromeda fleet` — install and supervise the external daemons the
/// Andromeda control plane depends on. First lane: the Letta Slack
/// channels daemon (`com.binarybros.letta-channels`), which silently
/// stayed unloaded for 10 days because nothing owned its install or
/// health. Fleet pillar (AGENTS.md): observe + mutate via typed Swift
/// (`LaunchAgentInstaller`, BIN-101), never bash.
struct FleetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fleet",
        abstract: "Install and health-check supervised fleet daemons (Letta channels).",
        subcommands: [Install.self, Status.self]
    )

    /// One logger for the fleet lane — os.Logger so probe results land
    /// in the unified log (queryable, leveled) like `mcp-hub` CLI
    /// telemetry. print() stays only for the human-facing table the
    /// terminal user reads — presentation, not logging.
    static let diagnostics = os.Logger(subsystem: "ai.andromeda.fleet", category: "cli")

    /// `andromeda fleet install` — render + bootstrap the Letta
    /// channels LaunchAgent through `LaunchAgentInstaller`.
    ///
    /// Destination is REQUIRED: per the installer contract (HAB-622)
    /// this command never defaults to `~/Library/LaunchAgents` — an
    /// explicit destination keeps the install auditable and repeatable.
    /// bootstrap: true (install means "make it live"); kickstart: false
    /// — same rule as heartbeat cron (AGENTS.md: no kickstarting jobs
    /// launchd already owns; RunAtLoad + KeepAlive start it on their
    /// own schedule).
    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install the Letta channels LaunchAgent plist (HOME rewrite + bootstrap)."
        )

        @Option(help: "Destination plist path (no default; e.g. ~/Library/LaunchAgents/com.binarybros.letta-channels.plist).")
        var destination: String

        @Option(help: "Source plist (default ops/com.binarybros.letta-channels.plist relative to the repo).")
        var source: String = "ops/com.binarybros.letta-channels.plist"

        @Option(help: "Model tier list for agent fallback (primary,secondary,...). Default: xai/grok-4.6,openai-compatible/glm/glm-5.3")
        var tiers: String = "xai/grok-4.6,openai-compatible/glm/glm-5.3"

        @Option(help: "Absolute HOME to rewrite the Studio template to. Defaults to the process home.")
        var home: String?

        @Option(help: "uid for the gui/<uid> domain. Defaults to the process uid.")
        var uid: UInt32?

        func run() async throws {
            let sourceURL = URL(fileURLWithPath: (source as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw ValidationError("source plist not found: \(source) — run from the Andromeda repo root")
            }
            let spec = LaunchAgentInstaller.Spec(
                label: LettaChannelsHealthProbe.label,
                home: home ?? NSHomeDirectory(),
                uid: uid ?? UInt32(getuid()),
                bootstrap: true,
                kickstart: false
            )
            let installer = LaunchAgentInstaller()
            let report = try await installer.install(
                source: sourceURL,
                destination: URL(
                    fileURLWithPath: (destination as NSString).expandingTildeInPath
                ),
                spec: spec
            )
            print(report)
            FleetCommand.diagnostics.notice("🚀 fleet install: \(report.label) bootstrapped=\(report.bootstrapped)")
            print("model_tiers: \(tiers)")
            print("health: `andromeda fleet status`")
        }
    }

    /// `andromeda fleet status` — compact health table for the Letta
    /// channels daemon: loaded / running / log freshness. Exit code is
    /// the machine contract: 0 healthy, non-zero when the agent is not
    /// loaded or the process is absent (cron/CI can alarm on it).
    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Health-check the Letta channels daemon: loaded, running, log freshness."
        )

        @Option(help: "uid for the gui/<uid> domain. Defaults to the process uid.")
        var uid: UInt32?

        func run() async throws {
            // Probe under the CURRENT home (not the Studio template the
            // plist bakes in) so status works on any clone after the
            // installer's HOME rewrite.
            let home = NSHomeDirectory()
            let probe = LettaChannelsHealthProbe(
                uid: uid ?? UInt32(getuid()),
                daemonPath: home + "/.local/bin/LettaChannels",
                logPath: home + "/.letta/logs/letta-channels.out.log"
            )
            let report = await probe.probe()

            print("fleet — \(LettaChannelsHealthProbe.label)")
            print("  \(report.loaded ? "🟢" : "🔴") loaded    launchctl print gui/\(probe.uid)/\(LettaChannelsHealthProbe.label)")
            print("  \(report.running ? "🟢" : "🔴") running   pgrep -f LettaChannels")
            let freshness: String
            if let age = report.logAge {
                freshness = age > 7200
                    ? "\(Int(age / 3600))h old"
                    : "\(Int(age / 60))m old"
            } else {
                freshness = "no log yet"
            }
            print(
                "  \(report.logStale ? "🟡" : "🟢") log       \(freshness) — \(probe.logPath)"
                    + (report.logStale ? " (stale > 1h)" : "")
            )

            // Why the log too: the unified log is where a scheduled
            // probe's history lives; stdout tables are ephemeral.
            FleetCommand.diagnostics.notice(
                "🩺 fleet status: loaded=\(report.loaded) running=\(report.running) logStale=\(report.logStale)"
            )

            guard report.healthy else {
                throw ValidationError(
                    report.loaded
                        ? "daemon loaded but process absent — check ~/.letta/logs/letta-channels.err.log"
                        : "LaunchAgent not loaded — run `andromeda fleet install --destination ~/Library/LaunchAgents/com.binarybros.letta-channels.plist`"
                )
            }
        }
    }
}
