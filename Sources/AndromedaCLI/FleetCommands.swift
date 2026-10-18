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
            let parsedTiers = try FleetCommand.parseTiers(tiers)
            let homeDir = home ?? NSHomeDirectory()

            // LaunchAgentInstaller validates Program exists before
            // bootstrap. Copy the built supervisor first or a clean
            // host fails with a missing ~/.local/bin/LettaChannels.
            let supervisorSource = FleetCommand.builtSupervisorURL()
            guard FileManager.default.isExecutableFile(atPath: supervisorSource.path) else {
                throw ValidationError(
                    "LettaChannels binary not built at \(supervisorSource.path) — run `swift build -c release --product LettaChannels`"
                )
            }
            let supervisorDest = URL(fileURLWithPath: homeDir + "/.local/bin/LettaChannels")
            let binaryReport = try await BinaryInstaller().install(
                source: supervisorSource,
                destination: supervisorDest
            )
            try FleetCommand.persistTiers(parsedTiers, home: homeDir)

            let spec = LaunchAgentInstaller.Spec(
                label: LettaChannelsHealthProbe.label,
                home: homeDir,
                uid: uid ?? UInt32(getuid()),
                bootstrap: true,
                kickstart: false
            )
            let report = try await LaunchAgentInstaller().install(
                source: sourceURL,
                destination: URL(
                    fileURLWithPath: (destination as NSString).expandingTildeInPath
                ),
                spec: spec
            )
            print(binaryReport)
            print(report)
            FleetCommand.diagnostics.notice("fleet install: \(report.label) bootstrapped=\(report.bootstrapped)")
            print("model_tiers: \(parsedTiers.map(\.rawValue).joined(separator: ","))")
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
                logPath: home + "/.letta/logs/letta-channels.out.log",
                tiers: FleetCommand.loadPersistedTiers(home: home)
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
            for tier in report.tiers {
                let live = report.tierStatus[tier] ?? false
                print("  \(live ? "🟢" : "🔴") tier      \(tier.rawValue)")
            }

            FleetCommand.diagnostics.notice(
                "fleet status: loaded=\(report.loaded) running=\(report.running) logStale=\(report.logStale) liveTier=\(report.hasLiveTier)"
            )

            guard report.healthy else {
                if report.loaded && report.running && !report.tiers.isEmpty && !report.hasLiveTier {
                    throw ValidationError("all configured model tiers unavailable")
                }
                throw ValidationError(
                    report.loaded
                        ? "daemon loaded but process absent — check ~/.letta/logs/letta-channels.err.log"
                        : "LaunchAgent not loaded — run `andromeda fleet install --destination ~/Library/LaunchAgents/com.binarybros.letta-channels.plist`"
                )
            }
        }
    }

    /// Sibling of the running `andromeda` binary. `swift build` puts
    /// both products in the same directory; launchd needs the Mach-O
    /// at ~/.local/bin before bootstrap, not the .swift source.
    static func builtSupervisorURL() -> URL {
        URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .appendingPathComponent("LettaChannels")
    }

    static func tiersFile(home: String) -> URL {
        URL(fileURLWithPath: home + "/.andromeda/fleet/letta-channels.tiers")
    }

    static func parseTiers(_ raw: String) throws -> [Tier] {
        let parts = raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return try parts.map { token in
            guard let tier = Tier(rawValue: token) else {
                throw ValidationError("unknown model tier \(token)")
            }
            return tier
        }
    }

    static func persistTiers(_ tiers: [Tier], home: String) throws {
        let url = tiersFile(home: home)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let body = tiers.map(\.rawValue).joined(separator: "\n") + "\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    static func loadPersistedTiers(home: String) -> [Tier] {
        guard let text = try? String(contentsOf: tiersFile(home: home), encoding: .utf8) else {
            return []
        }
        return text.split(whereSeparator: \.isNewline).compactMap { Tier(rawValue: String($0)) }
    }
}
