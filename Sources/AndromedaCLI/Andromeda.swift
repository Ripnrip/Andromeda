import AndromedaCore
import AndromedaGateway
import AndromedaMCP
import ArgumentParser
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

@main
struct Andromeda: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "andromeda",
        abstract: "Andromeda — Swift-native control plane and Hummingbird model/MCP gateway.",
        version: AndromedaVersion.string,
        subcommands: [Serve.self, Status.self, Setup.self, Doctor.self],
        defaultSubcommand: Status.self
    )
}

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show gateway identity, Autocache, and MCP shim readiness."
    )

    func run() async throws {
        let config = try GatewayConfig.loadFromEnvironment()
        let vault = SecretVault.loadFromEnvironment()
        print("\(AndromedaVersion.productName) \(AndromedaVersion.string)")
        print("surface: autocache + mcp_shim")
        print("bind: \(config.serverAddress)")
        print("strategy: \(config.cacheStrategy)")
        print("anthropic: \(config.anthropicURL)")
        print("api_key: \(config.apiKeyConfigured ? "configured" : "per-request headers")")
        print("broker_token: \(config.brokerToken?.isEmpty == false ? "configured" : "missing")")
        print("mcp_shim: \(config.enableMCPShim ? "enabled" : "disabled")")
        for snapshot in vault.snapshots {
            print("secret.\(snapshot.capability.rawValue): \(snapshot.configured ? "present" : "absent")")
        }
        print("ready: run `andromeda serve` or `andromeda setup`")
    }
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the Hummingbird Autocache + MCP shim gateway in the foreground."
    )

    @Option(name: .long, help: "Bind host (default from HOST or 127.0.0.1).")
    var host: String?

    @Option(name: .long, help: "Bind port (default from PORT or 8080).")
    var port: Int?

    @Option(name: .long, help: "Cache strategy: conservative|moderate|aggressive.")
    var strategy: String?

    func run() async throws {
        var config = try GatewayConfig.loadFromEnvironment()
        if let host { config.host = host }
        if let port { config.port = port }
        if let strategy { config.cacheStrategy = strategy }
        try config.validate()
        let resolvedLogLevel = Self.logLevel(from: config.logLevel)

        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = resolvedLogLevel
            return handler
        }

        let logger = Logger(label: "andromeda.cli")
        logger.info(
            """

                 _            _
                / \\   _ __  | |_ __ ___  _ __ ___   ___  __| | __ _
               / _ \\ | '_ \\ | | '__/ _ \\| '_ ` _ \\ / _ \\/ _` |/ _` |
              / ___ \\| | | || | | | (_) | | | | | |  __/ (_| | (_| |
             /_/   \\_\\_| |_||_|_|  \\___/|_| |_| |_|\\___|\\__,_|\\__,_|

             Hummingbird Gateway — Autocache + MCP shim (Slack/GitHub brokered)
            """
        )

        let gateway = GatewayApplication(config: config, logger: logger)
        try await gateway.run()
    }

    private static func logLevel(from value: String) -> Logger.Level {
        switch value.lowercased() {
        case "trace": .trace
        case "debug": .debug
        case "info": .info
        case "warn", "warning": .warning
        case "error": .error
        case "critical": .critical
        default: .info
        }
    }
}

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Interactive host setup: checklist, guest MCP config, gateway start hints."
    )

    @Flag(name: .long, help: "Print the plan without mutating state.")
    var dryRun: Bool = false

    @Option(name: .long, help: "Write guest mcp.json to this path.")
    var writeGuestConfig: String?

    @Option(name: .long, help: "Public gateway base URL for guest wiring.")
    var gatewayURL: String?

    @Flag(name: .long, help: "Skip interactive prompts.")
    var yes: Bool = false

    func run() async throws {
        let config = try GatewayConfig.loadFromEnvironment()
        let vault = SecretVault.loadFromEnvironment()
        let baseURL = gatewayURL ?? "http://\(config.serverAddress)"
        let broker = config.brokerToken ?? ""
        let vmDetected = FileManager.default.fileExists(atPath: "/Volumes")
            && (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes"))?.contains(where: {
                $0.localizedCaseInsensitiveContains("vm") || $0.localizedCaseInsensitiveContains("guest")
            }) == true
        #if os(macOS)
        let menubarAvailable = true
        #else
        let menubarAvailable = false
        #endif

        let plan = HostDiagnostics.setupPlan(
            vault: vault,
            brokerToken: broker,
            gatewayBaseURL: baseURL,
            vmDetected: vmDetected,
            dryRun: dryRun,
            menubarAvailable: menubarAvailable
        )
        print(plan.render())
        print("")
        let guestJSON = try plan.guestConfig.renderMCPJSON()
        print("—— guest mcp.json ——")
        print(guestJSON)

        if GuestMCPConfig.containsUpstreamSecrets(guestJSON) {
            print("ERROR: guest config unexpectedly contains upstream secret markers")
            throw ExitCode(1)
        }

        if let path = writeGuestConfig {
            if dryRun {
                print("[dry-run] would write guest config to \(path)")
            } else {
                try guestJSON.write(toFile: path, atomically: true, encoding: .utf8)
                print("wrote guest config: \(path)")
            }
        }

        if !yes && !dryRun {
            print("Next: keep this process visible — run `andromeda serve` in the foreground.")
            print("On macOS, pair with the HUD/menubar for live status. Then open the VM checklist.")
            print("Getting started: docs/MCP-SHIM.md")
        }

        if dryRun {
            print("dry-run complete — no gateway started")
        }
    }
}

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Diagnose gateway, MCP shims, host secrets presence, and guest config scrub."
    )

    @Option(name: .long, help: "Optional guest mcp.json path to scrub-check.")
    var guestConfig: String?

    @Option(name: .long, help: "Gateway health URL (default http://HOST:PORT/health).")
    var healthURL: String?

    func run() async throws {
        let config = try GatewayConfig.loadFromEnvironment()
        let vault = SecretVault.loadFromEnvironment()
        let brokerConfigured = !(config.brokerToken?.isEmpty ?? true)
        #if os(macOS)
        let menubarAvailable = true
        #else
        let menubarAvailable = false
        #endif

        let urlString = healthURL ?? "http://\(config.serverAddress)/health"
        let gatewayReachable: Bool
        if let url = URL(string: urlString) {
            gatewayReachable = await Self.probe(url: url)
        } else {
            gatewayReachable = false
        }

        let guestText: String?
        if let guestConfig {
            guestText = try? String(contentsOfFile: guestConfig, encoding: .utf8)
        } else {
            guestText = nil
        }

        let report = HostDiagnostics.doctor(
            vault: vault,
            brokerTokenConfigured: brokerConfigured,
            gatewayReachable: gatewayReachable,
            guestConfigText: guestText,
            menubarAvailable: menubarAvailable
        )
        print(report.render())

        // Always print capability curtain IDs for operators.
        print("")
        print("capabilities: slack_proxy, github_proxy")
        print("pillar check: memory + secrets/vault + tools/mcp")

        throw ExitCode(report.exitCode)
    }

    private static func probe(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<500).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
