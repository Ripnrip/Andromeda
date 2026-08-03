import AndromedaDomain
import AndromedaHostOps
import AndromedaSecrets
import AndromedaServer
import AndromedaTools
import ArgumentParser
import Foundation
import Logging

@main
struct AndromedaRuntimeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "andromeda-runtime",
        abstract: "Runnable Andromeda Runtime v2 server.",
        subcommands: [Serve.self, Setup.self, Doctor.self],
        defaultSubcommand: Serve.self
    )
}

// MARK: - Shared host defaults

enum HostDefaults {
    static let githubService = "andromeda.github"
    static let githubAccount = "token"
    static let slackService = "andromeda.slack"
    static let slackAccount = "token"
    static let defaultPort = 8788

    static func env(_ name: String, fallback: String? = nil) -> String? {
        ProcessInfo.processInfo.environment[name] ?? fallback
    }

    static func option(_ value: String?, _ envName: String, fallback: String? = nil) -> String? {
        value ?? env(envName, fallback: fallback)
    }
}

// MARK: - Serve

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the Andromeda runtime memory server in the foreground."
    )

    @Option(name: .long, help: "Bind host. Defaults to 0.0.0.0.")
    var host: String = "0.0.0.0"

    @Option(name: .long, help: "Bind port. Defaults to 8788.")
    var port: Int = 8788

    @Option(name: .long, help: "Path to the canonical JSONL event journal.")
    var journalPath: String

    @Option(name: .long, help: "Directory for the Obsidian-compatible Markdown vault. Defaults to a sibling 'vault' directory next to the journal.")
    var vaultDir: String?

    @Option(name: .long, help: "Base URL for the Qdrant HTTP API. Defaults to http://localhost:6333.")
    var qdrantUrl: String = "http://localhost:6333"

    @Option(name: .long, help: "Bearer token VM agents use for POST /mcp. Env: ANDROMEDA_MCP_BEARER_TOKEN. Enables the tools/MCP endpoint when set.")
    var mcpBearerToken: String?

    @Option(name: .long, help: "Keychain service holding the GitHub token. Env: ANDROMEDA_GITHUB_TOKEN_SERVICE.")
    var githubTokenService: String?

    @Option(name: .long, help: "Keychain account holding the GitHub token. Env: ANDROMEDA_GITHUB_TOKEN_ACCOUNT.")
    var githubTokenAccount: String?

    @Option(name: .long, help: "Keychain service holding the Slack token. Env: ANDROMEDA_SLACK_TOKEN_SERVICE.")
    var slackTokenService: String?

    @Option(name: .long, help: "Keychain account holding the Slack token. Env: ANDROMEDA_SLACK_TOKEN_ACCOUNT.")
    var slackTokenAccount: String?

    @Flag(name: .long, help: "Allow write operations (GitHub POST/PATCH/PUT/DELETE, Slack writes) through the tools broker. Env: ANDROMEDA_TOOLS_AUTOMATION=1.")
    var automationAllowed = false

    func run() async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .info
            return handler
        }

        let logger = Logger(label: "andromeda.runtime.cli")

        // ASCII banner — Andromeda brand identity in the terminal.
        // Respects NO_COLOR env var for non-TTY / accessibility.
        let useColor = ProcessInfo.processInfo.environment["NO_COLOR"] == nil
        print(AndromedaASCIILogo.banner(colored: useColor))
        print()

        guard let qdrantBaseURL = URL(string: qdrantUrl) else {
            throw ValidationError("Invalid Qdrant URL: \(qdrantUrl)")
        }

        let env = ProcessInfo.processInfo.environment
        func option(_ value: String?, _ envName: String) -> String? {
            value ?? env[envName]
        }

        var mcpConfiguration: MCPConfiguration?
        if let bearerToken = option(mcpBearerToken, "ANDROMEDA_MCP_BEARER_TOKEN"), !bearerToken.isEmpty {
            var github: ToolsBrokerConfiguration.GitHub?
            if let service = option(githubTokenService, "ANDROMEDA_GITHUB_TOKEN_SERVICE"),
               let account = option(githubTokenAccount, "ANDROMEDA_GITHUB_TOKEN_ACCOUNT")
            {
                github = .init(tokenReference: SecretReference(service: service, account: account))
            }
            var slack: ToolsBrokerConfiguration.Slack?
            if let service = option(slackTokenService, "ANDROMEDA_SLACK_TOKEN_SERVICE"),
               let account = option(slackTokenAccount, "ANDROMEDA_SLACK_TOKEN_ACCOUNT")
            {
                slack = .init(tokenReference: SecretReference(service: service, account: account))
            }
            let automation = automationAllowed || env["ANDROMEDA_TOOLS_AUTOMATION"] == "1"
            mcpConfiguration = try MCPConfiguration(
                bearerToken: bearerToken,
                tools: ToolsBrokerConfiguration(automationAllowed: automation, github: github, slack: slack)
            )
            logger.info(
                "Tools/MCP broker enabled",
                metadata: [
                    "github": .stringConvertible(github != nil),
                    "slack": .stringConvertible(slack != nil),
                    "automation": .stringConvertible(automation),
                ]
            )
        }

        let server = try AndromedaRuntimeServer(
            configuration: AndromedaRuntimeConfiguration(host: host, port: port, mcp: mcpConfiguration),
            journalFileURL: URL(fileURLWithPath: journalPath),
            vaultDirectoryURL: vaultDir.map { URL(fileURLWithPath: $0) },
            qdrantBaseURL: qdrantBaseURL,
            logger: logger
        )
        try await server.run()
    }
}

// MARK: - Setup (BIN-212)

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Interactive host-first setup: Keychain refs, guest MCP config, live checklist (BIN-212)."
    )

    @Flag(name: .long, help: "Print the plan without mutating state.")
    var dryRun = false

    @Flag(name: .long, help: "Skip interactive prompts.")
    var yes = false

    @Flag(name: .long, help: "Alias for --yes (non-interactive).")
    var nonInteractive = false

    @Flag(name: .long, help: "Apply safe idempotent repairs: create dirs, seed Keychain from env, write guest config.")
    var fix = false

    @Option(name: .long, help: "Public runtime base URL for guest wiring (e.g. http://studio:8788).")
    var runtimeURL: String?

    @Option(name: .long, help: "Write guest mcp.json to this path.")
    var writeGuestConfig: String?

    @Option(name: .long, help: "Journal path used for checklist / --fix mkdir.")
    var journalPath: String?

    @Option(name: .long, help: "Vault directory used for checklist / --fix mkdir.")
    var vaultDir: String?

    @Option(name: .long, help: "Keychain service for GitHub token.")
    var githubTokenService: String?

    @Option(name: .long, help: "Keychain account for GitHub token.")
    var githubTokenAccount: String?

    @Option(name: .long, help: "Keychain service for Slack token.")
    var slackTokenService: String?

    @Option(name: .long, help: "Keychain account for Slack token.")
    var slackTokenAccount: String?

    func run() async throws {
        let skipPrompts = yes || nonInteractive || dryRun
        let applyFixes = fix && !dryRun

        let githubRef = SecretReference(
            service: HostDefaults.option(githubTokenService, "ANDROMEDA_GITHUB_TOKEN_SERVICE", fallback: HostDefaults.githubService)!,
            account: HostDefaults.option(githubTokenAccount, "ANDROMEDA_GITHUB_TOKEN_ACCOUNT", fallback: HostDefaults.githubAccount)!
        )
        let slackRef = SecretReference(
            service: HostDefaults.option(slackTokenService, "ANDROMEDA_SLACK_TOKEN_SERVICE", fallback: HostDefaults.slackService)!,
            account: HostDefaults.option(slackTokenAccount, "ANDROMEDA_SLACK_TOKEN_ACCOUNT", fallback: HostDefaults.slackAccount)!
        )

        let journal = journalPath
            ?? HostDefaults.env("ANDROMEDA_JOURNAL_PATH")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Developer/AndromedaData/journal.jsonl").path
        let vault = vaultDir
            ?? HostDefaults.env("ANDROMEDA_VAULT_DIR")
            ?? URL(fileURLWithPath: journal).deletingLastPathComponent().appendingPathComponent("vault").path

        let presence = KeychainPresenceChecker()
        if applyFixes {
            try Self.seedKeychainIfNeeded(label: "github", reference: githubRef, envKeys: ["ANDROMEDA_GITHUB_TOKEN", "GH_TOKEN"])
            try Self.seedKeychainIfNeeded(label: "slack", reference: slackRef, envKeys: ["ANDROMEDA_SLACK_TOKEN", "SLACK_BOT_TOKEN"])
            try Self.ensureParentFile(journal)
            try FileManager.default.createDirectory(atPath: vault, withIntermediateDirectories: true)
            print("fix: ensured journal parent + vault directory (secrets seeded only when env present)")
        }

        let secrets = [
            SecretPresence(reference: githubRef, present: presence.isPresent(githubRef), label: "github"),
            SecretPresence(reference: slackRef, present: presence.isPresent(slackRef), label: "slack"),
        ]

        let brokerConfigured = !(HostDefaults.env("ANDROMEDA_MCP_BEARER_TOKEN") ?? "").isEmpty
        let baseURL = runtimeURL
            ?? HostDefaults.env("ANDROMEDA_RUNTIME_URL")
            ?? "http://127.0.0.1:\(HostDefaults.defaultPort)"

        #if os(macOS)
        let menubarAvailable = true
        #else
        let menubarAvailable = false
        #endif

        let plan = HostDiagnostics.setupPlan(
            secrets: secrets,
            brokerTokenConfigured: brokerConfigured,
            runtimeBaseURL: baseURL,
            journalPathExists: FileManager.default.fileExists(atPath: journal)
                || FileManager.default.fileExists(atPath: URL(fileURLWithPath: journal).deletingLastPathComponent().path),
            vaultPathExists: FileManager.default.fileExists(atPath: vault),
            vmSignalDetected: GuestSignalDetector.detect(),
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

        let guestPath = writeGuestConfig ?? (applyFixes ? defaultGuestConfigPath() : nil)
        if let guestPath {
            if dryRun {
                print("[dry-run] would write guest config to \(guestPath)")
            } else if applyFixes || yes || skipPrompts || writeGuestConfig != nil {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: guestPath).deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try guestJSON.write(toFile: guestPath, atomically: true, encoding: .utf8)
                print("wrote guest config: \(guestPath)")
            }
        }

        if !skipPrompts {
            print("")
            print("Next (host): keep this process visible — run `andromeda-runtime serve` in the foreground.")
            print("  Example:")
            print("  ANDROMEDA_MCP_BEARER_TOKEN=… andromeda-runtime serve \\")
            print("    --journal-path \(journal) --vault-dir \(vault) \\")
            print("    --mcp-bearer-token \"$ANDROMEDA_MCP_BEARER_TOKEN\" \\")
            print("    --github-token-service \(githubRef.service) --github-token-account \(githubRef.account) \\")
            print("    --slack-token-service \(slackRef.service) --slack-token-account \(slackRef.account)")
            print("Then on the VM: point MCP at \(plan.guestConfig.url) with only the broker bearer — zero GitHub/Slack secrets.")
            print("Docs: docs/SETUP-DOCTOR.md")
        }

        if dryRun {
            print("dry-run complete — no Keychain or filesystem mutations")
        }

        if plan.items.contains(where: { $0.status == .fail }) {
            throw ExitCode(1)
        }
    }

    /// Seeds Keychain from the first non-empty env key. Never prints token values.
    private static func seedKeychainIfNeeded(label: String, reference: SecretReference, envKeys: [String]) throws {
        let presence = KeychainPresenceChecker()
        if presence.isPresent(reference) {
            print("fix: Keychain \(label) already present (\(reference.service)/\(reference.account))")
            return
        }
        let env = ProcessInfo.processInfo.environment
        guard let secret = envKeys.compactMap({ env[$0] }).first(where: { !$0.isEmpty }) else {
            print("fix: skipped Keychain \(label) — no env token among \(envKeys.joined(separator: ", "))")
            return
        }
        try KeychainSeeder().upsert(reference: reference, secret: secret)
        print("fix: seeded Keychain \(label) (\(reference.service)/\(reference.account)) — value not printed")
    }

    private static func ensureParentFile(_ path: String) throws {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: Data())
        }
    }

    private func defaultGuestConfigPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer/AndromedaData/guest-mcp.json").path
    }
}

// MARK: - Doctor (BIN-213)

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Diagnose runtime health, Keychain presence, projections, curated MCP surface (BIN-213)."
    )

    @Option(name: .long, help: "Optional guest mcp.json path to scrub-check.")
    var guestConfig: String?

    @Option(name: .long, help: "Runtime health URL (default http://127.0.0.1:8788/health).")
    var healthURL: String?

    @Option(name: .long, help: "Qdrant base URL to probe (default http://localhost:6333).")
    var qdrantURL: String?

    @Option(name: .long, help: "MCP endpoint URL (default derived from health host + /mcp).")
    var mcpURL: String?

    @Flag(name: .long, help: "Apply safe idempotent repairs (create dirs; seed Keychain from env).")
    var fix = false

    @Option(name: .long, help: "Journal path for existence / --fix.")
    var journalPath: String?

    @Option(name: .long, help: "Vault directory for existence / --fix.")
    var vaultDir: String?

    @Option(name: .long, help: "Keychain service for GitHub token.")
    var githubTokenService: String?

    @Option(name: .long, help: "Keychain account for GitHub token.")
    var githubTokenAccount: String?

    @Option(name: .long, help: "Keychain service for Slack token.")
    var slackTokenService: String?

    @Option(name: .long, help: "Keychain account for Slack token.")
    var slackTokenAccount: String?

    func run() async throws {
        let githubRef = SecretReference(
            service: HostDefaults.option(githubTokenService, "ANDROMEDA_GITHUB_TOKEN_SERVICE", fallback: HostDefaults.githubService)!,
            account: HostDefaults.option(githubTokenAccount, "ANDROMEDA_GITHUB_TOKEN_ACCOUNT", fallback: HostDefaults.githubAccount)!
        )
        let slackRef = SecretReference(
            service: HostDefaults.option(slackTokenService, "ANDROMEDA_SLACK_TOKEN_SERVICE", fallback: HostDefaults.slackService)!,
            account: HostDefaults.option(slackTokenAccount, "ANDROMEDA_SLACK_TOKEN_ACCOUNT", fallback: HostDefaults.slackAccount)!
        )

        let journal = journalPath
            ?? HostDefaults.env("ANDROMEDA_JOURNAL_PATH")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Developer/AndromedaData/journal.jsonl").path
        let vault = vaultDir
            ?? HostDefaults.env("ANDROMEDA_VAULT_DIR")
            ?? URL(fileURLWithPath: journal).deletingLastPathComponent().appendingPathComponent("vault").path

        if fix {
            try Setup.seedViaDoctorFix(github: githubRef, slack: slackRef, journal: journal, vault: vault)
        }

        let presence = KeychainPresenceChecker()
        let secrets = [
            SecretPresence(reference: githubRef, present: presence.isPresent(githubRef), label: "github"),
            SecretPresence(reference: slackRef, present: presence.isPresent(slackRef), label: "slack"),
        ]

        let healthString = healthURL
            ?? HostDefaults.env("ANDROMEDA_HEALTH_URL")
            ?? "http://127.0.0.1:\(HostDefaults.defaultPort)/health"
        guard let health = URL(string: healthString) else {
            throw ValidationError("Invalid health URL: \(healthString)")
        }

        let probes = RuntimeProbes()
        let runtimeReachable = await probes.isHealthy(url: health)

        let qdrantString = qdrantURL
            ?? HostDefaults.env("ANDROMEDA_TEST_QDRANT_URL")
            ?? HostDefaults.env("ANDROMEDA_QDRANT_URL")
            ?? "http://localhost:6333"
        let qdrantReachable: Bool?
        if let qdrant = URL(string: qdrantString) {
            qdrantReachable = await probes.isQdrantReachable(baseURL: qdrant)
        } else {
            qdrantReachable = false
        }

        let bearer = HostDefaults.env("ANDROMEDA_MCP_BEARER_TOKEN") ?? ""
        var tools: Set<String>?
        if !bearer.isEmpty {
            let mcpString = mcpURL ?? healthString
                .replacingOccurrences(of: "/health", with: "/mcp")
            if let mcp = URL(string: mcpString) {
                tools = await probes.listMCPToolNames(mcpURL: mcp, bearerToken: bearer)
            }
        }

        let guestText: String?
        if let guestConfig {
            guestText = try? String(contentsOfFile: guestConfig, encoding: .utf8)
        } else {
            let defaultGuest = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Developer/AndromedaData/guest-mcp.json").path
            guestText = try? String(contentsOfFile: defaultGuest, encoding: .utf8)
        }

        #if os(macOS)
        let menubarAvailable = true
        #else
        let menubarAvailable = false
        #endif

        let report = HostDiagnostics.doctor(
            runtimeReachable: runtimeReachable,
            brokerTokenConfigured: !bearer.isEmpty,
            secrets: secrets,
            qdrantReachable: qdrantReachable,
            journalPathExists: FileManager.default.fileExists(atPath: journal),
            vaultPathExists: FileManager.default.fileExists(atPath: vault),
            guestConfigText: guestText,
            toolsListNames: tools,
            vmSignalDetected: GuestSignalDetector.detect(),
            menubarAvailable: menubarAvailable
        )

        print(report.render())
        print("")
        print("capabilities (curtain): andromeda_github_*, andromeda_slack_* — never Linear/Multica/provider brands")
        print("pillars: memory + secrets/vault + tools/mcp")

        throw ExitCode(report.exitCode)
    }
}

private extension Setup {
    /// Shared --fix path invoked from doctor without duplicating seed logic visibility.
    static func seedViaDoctorFix(
        github: SecretReference,
        slack: SecretReference,
        journal: String,
        vault: String
    ) throws {
        try seedKeychainIfNeeded(label: "github", reference: github, envKeys: ["ANDROMEDA_GITHUB_TOKEN", "GH_TOKEN"])
        try seedKeychainIfNeeded(label: "slack", reference: slack, envKeys: ["ANDROMEDA_SLACK_TOKEN", "SLACK_BOT_TOKEN"])
        try ensureParentFile(journal)
        try FileManager.default.createDirectory(atPath: vault, withIntermediateDirectories: true)
        print("fix: doctor applied safe repairs (dirs + optional Keychain seed)")
    }
}
