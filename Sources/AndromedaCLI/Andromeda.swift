import AndromedaBrand
import AndromedaCore
import AndromedaGateway
import AndromedaHostOps
import ArgumentParser
import Darwin
import Foundation
import Logging

@main
struct Andromeda: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "andromeda",
        abstract: "Andromeda — Swift-native control plane and Hummingbird model gateway.",
        version: AndromedaVersion.string,
        subcommands: [Serve.self, Status.self, Brand.self, InstallCLI.self, InstallApp.self, InstallLaunchAgent.self, MCPHubCommand.self],
        defaultSubcommand: Status.self
    )
}

/// 🎨 Design-system surface: prints the Andromeda mark, palette and chrome so the
/// TUI vocabulary is inspectable from the terminal it ships in.
struct Brand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the Andromeda terminal design system: mark, palette, status chips."
    )

    @Flag(name: .long, help: "Print the narrow trefoil instead of the full mark.")
    var compact = false

    func run() throws {
        let style = TerminalStyle.detect()
        print(
            AndromedaChrome.banner(
                surface: "design system",
                version: AndromedaVersion.string,
                tagline: "One visual system across web, TUI and macOS surfaces.",
                style: style,
                compact: compact
            )
        )
        print("")
        print("  " + AndromedaChrome.eyebrow("palette", style: style))
        for token in AndromedaPalette.all {
            print("  " + AndromedaChrome.field(token.name, style.paint(token.color.hex, token.color), style: style, keyWidth: 22))
        }
        print("")
        print("  " + AndromedaChrome.eyebrow("status vocabulary", style: style))
        for status in BrandStatus.allCases {
            print("  " + AndromedaChrome.statusChip(status, style: style))
        }
        print("")
        print("  " + AndromedaChrome.principles(
            ["Local first.", "Visible by default.", "No silent sprawl."],
            style: style
        ))
        print("")
        print("  " + AndromedaChrome.caveat("Colour degrades to 256-colour and to plain text; NO_COLOR is honoured.", style: style))
    }
}

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show gateway identity and Autocache surface readiness."
    )

    func run() async throws {
        let config = try GatewayConfig.loadFromEnvironment()
        let style = TerminalStyle.detect()

        print(AndromedaChrome.paintedMark(.compact, style: style).joined(separator: "\n"))
        print("")
        print("  " + AndromedaChrome.eyebrow("autocache gateway", style: style))
        print("  " + style.paint("\(AndromedaVersion.productName) v\(AndromedaVersion.string)", AndromedaPalette.foreground, bold: true))
        print("  " + AndromedaChrome.rule(min(style.width, 62), style: style))
        print("  " + AndromedaChrome.field("surface", "autocache (Anthropic prompt-cache proxy)", style: style))
        print("  " + AndromedaChrome.field("bind", config.serverAddress, style: style))
        print("  " + AndromedaChrome.field("strategy", config.cacheStrategy, style: style))
        print("  " + AndromedaChrome.field("anthropic", config.anthropicURL, style: style))
        print("  " + AndromedaChrome.field("api_key", config.apiKeyConfigured ? "configured" : "per-request headers", style: style))
        print("  " + AndromedaChrome.field("pillar 4", status: .partial, detail: "LLM proxy — Anthropic surface only", style: style))
        print("  " + AndromedaChrome.rule(min(style.width, 62), style: style))
        print("  " + style.paint("ready: run `andromeda serve` to start the Hummingbird gateway", AndromedaPalette.mutedForeground))
    }
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the Hummingbird Autocache model gateway in the foreground."
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

        // Banner goes to stdout, not the log stream, so the mark keeps its brand
        // colour and structured log lines stay machine-parseable.
        let style = TerminalStyle.detect()
        print(
            AndromedaChrome.banner(
                surface: "autocache gateway",
                version: AndromedaVersion.string,
                tagline: "Hummingbird Autocache — Anthropic prompt-cache proxy.",
                style: style
            )
        )

        let logger = Logger(label: "andromeda.cli")

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

/// BIN-101 slice · HAB-606 prevention: fail-closed atomic install of a built
/// executable (fresh inode → ad-hoc re-sign → strict verify → atomic rename).
///
/// HAB-606: freshly copied SwiftPM binaries published at their final path
/// before their post-copy signature settled were SIGKILLed by the macOS 26
/// signing monitor (Taskgated Invalid Signature / Invalid Page). This command
/// stages and signs a fresh inode next to the destination and only then
/// renames it into place, so consumers never observe an unsigned inode.
struct InstallCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-cli",
        abstract: "Atomically install a built executable: stage fresh inode, re-sign, verify, rename.",
        discussion: """
        Fail-closed install transaction (HAB-606 prevention, BIN-101 slice).

        The destination is never written in place: a staging copy with a fresh
        inode is ad-hoc re-signed and strictly verified next to the destination,
        then atomically renamed into it. Required adjacent rpath dylibs found
        next to the source are staged, re-signed, and published beside the
        destination (HAB-626); missing required companions fail closed (HAB-625).
        Post-publish verify covers dest AND each companion; failure restores
        parked dest + companions (HAB-629 / HAB-631). Any failure before
        publish leaves the destination binary untouched.
        """
    )

    @Option(help: "Built executable to install (e.g. .build/release/andromeda).")
    var source: String

    @Option(help: "Final install path (e.g. ~/.local/bin/andromeda). Parent directories are created.")
    var destination: String

    func run() async throws {
        let installer = BinaryInstaller()
        let report = try await installer.install(
            source: URL(fileURLWithPath: source),
            destination: URL(fileURLWithPath: (destination as NSString).expandingTildeInPath)
        )
        print(report)
    }
}


/// BIN-101 slice · HAB-621: fail-closed atomic install of a minimal `.app`
/// bundle (stage tree → strip leftover sigs → `codesign --force --deep` →
/// `--verify --deep --strict` → atomic replace).
///
/// Companion to `install-cli` (bare Mach-O). Does **not** open the app, does
/// **not** install LaunchAgents, and does **not** default to `~/Applications`
/// — callers pass `--destination` explicitly.
struct InstallApp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-app",
        abstract: "Atomically install a built executable as a signed .app bundle.",
        discussion: """
        Fail-closed .app install transaction (HAB-621 / HAB-630 / HAB-671 / HAB-673 / HAB-675, BIN-101 slice).

        Assembles Contents/MacOS + Info.plist at a staging .app next to the
        destination, inspects the inner executable with otool -L, then BFS
        otool -L source-adjacent companions (HAB-675). Copies required rpath
        dylibs (including nested adjacent names) into Contents/MacOS (fails
        closed if a required non-system dylib is missing), ad-hoc deep-signs
        and strictly verifies that staging tree, parks any previous dest
        bundle, then publishes staging. A failed post-publish --deep --strict
        dest verify or companion --strict verify restores the parked bundle
        (HAB-630 / HAB-673). The live destination is never overwritten with
        an unsigned tree.

        Does not `open -a` and does not touch LaunchAgents.
        """
    )

    @Option(help: "Built executable to wrap (e.g. .build/release/AndromedaHome).")
    var source: String

    @Option(help: "Final .app path (e.g. /tmp/AndromedaHome.app). Parent directories are created.")
    var destination: String

    @Option(name: .customLong("bundle-id"), help: "CFBundleIdentifier (e.g. com.andromeda.home).")
    var bundleId: String

    @Option(name: .customLong("display-name"), help: "CFBundleDisplayName. Defaults to the product name.")
    var displayName: String?

    @Option(help: "CFBundleExecutable / MacOS filename. Defaults to the source basename.")
    var product: String?

    @Option(help: "CFBundleShortVersionString.")
    var version: String = "0.3"

    @Option(help: "CFBundleVersion. Defaults to yyyyMMddHHmm.")
    var build: String?

    @Flag(name: .customLong("lsui-element"), help: "Set LSUIElement (accessory HUD, no Dock icon).")
    var lsuiElement: Bool = false

    func run() async throws {
        let sourceURL = URL(fileURLWithPath: source)
        let destURL = URL(fileURLWithPath: (destination as NSString).expandingTildeInPath)
        let productName = product ?? sourceURL.lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        let spec = AppBundleInstaller.Spec(
            productName: productName,
            bundleIdentifier: bundleId,
            displayName: displayName ?? productName,
            shortVersion: version,
            buildVersion: build ?? formatter.string(from: Date()),
            lsuiElement: lsuiElement
        )
        let installer = AppBundleInstaller()
        let report = try await installer.install(source: sourceURL, destination: destURL, spec: spec)
        print(report)
    }
}


/// BIN-101 leftover · HAB-622: rewrite Studio HOME template in a LaunchAgent
/// plist, write it to an explicit destination, optionally bootstrap.
///
/// Kickstart is opt-in (`--kickstart`) and requires `--bootstrap`. Heartbeat
/// cron must not pass `--kickstart` (AGENTS.md: no invisible launchd jobs).
/// Destination is required — this command never defaults to
/// `~/Library/LaunchAgents`.
struct InstallLaunchAgent: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-launch-agent",
        abstract: "Render a LaunchAgent plist (HOME rewrite) and optionally bootstrap it.",
        discussion: """
        Fail-closed LaunchAgent install (HAB-622 / HAB-632 / HAB-676 / HAB-677 / HAB-678 / HAB-680 / HAB-681 / HAB-682 / HAB-683 / HAB-684 / HAB-686 / HAB-687 / HAB-688 / HAB-689, BIN-101 leftover).

        launchd does not expand $HOME/~. ops/*.plist bake the Studio home
        template /Users/admin; this command rewrites that string to --home
        (absolute) and writes the result to --destination.

        Previous dest is parked until publish succeeds; a failed
        bootstrap+load restores that inode (or leaves dest absent on a
        fresh install). --bootstrap requires the rendered Program path to
        exist and be executable before dest is parked (HAB-676). If that
        Program is Mach-O it must also pass codesign --verify --strict
        (HAB-677), have required adjacent rpath dylibs present (HAB-678),
        and those companions must themselves pass codesign --verify
        --strict (HAB-680) — unsigned Mach-O is Taskgated SIGKILL
        (HAB-606) and a missing or unsigned companion dyld-fails; both
        KeepAlive-hammer. If WorkingDirectory is present it must be an
        absolute existing directory (HAB-681): bootstrap can return 0
        when chdir would fail. Missing key is allowed. If StandardOutPath
        / StandardErrorPath is present it must be absolute and must not
        be a directory (HAB-682): bootstrap can return 0 when launchd
        cannot open the log. Missing keys allowed. If
        EnvironmentVariables.HOME is present it must be an absolute
        existing directory (HAB-683): bootstrap can return 0 when HOME
        is relative, missing, or a file, then KeepAlive hammers.
        Missing key allowed. If EnvironmentVariables.PATH is present,
        every colon-component must be absolute (HAB-684): bootstrap can
        return 0 when PATH contains relative, empty, $HOME, or ~
        components (launchd does not expand them). Components need not
        exist. Missing key allowed. /usr/bin/open is refused on
        --bootstrap (HAB-686): LaunchServices open -a can inherit
        Aqua/agent-shell env (paid API keys). /usr/bin/osascript is
        refused on --bootstrap (HAB-687): osascript inherits the same
        Aqua/agent-shell env. HAB-688 also refuses those binaries in
        any ProgramArguments slot (arch/env trampolines). Scripts/shebangs
        stay allowed. Paid provider API keys in EnvironmentVariables
        (OPENROUTER_/ANTHROPIC_/OPENAI_/XAI_/GROQ_ prefixes plus
        GOOGLE_API_KEY/GEMINI_API_KEY) are refused on --bootstrap
        (HAB-689); HOME/PATH/LANG allowed. Rewrite-only does not
        inspect those keys.
        Rewrite-only (no --bootstrap) stays a dry-run.
        --bootstrap runs bootout then bootstrap (legacy load fallback).
        --kickstart is opt-in and refused without --bootstrap. Cron must
        not kickstart live HUD.
        """
    )

    @Option(help: "Source plist (e.g. ops/com.andromeda.hud.plist).")
    var source: String

    @Option(help: "Destination plist path. Parent directories are created. No default.")
    var destination: String

    @Option(help: "Expected Label. Defaults to the Label inside the rendered plist.")
    var label: String?

    @Option(help: "Absolute HOME to rewrite the Studio template to. Defaults to the process home.")
    var home: String?

    @Option(help: "uid for gui/<uid> domain. Defaults to the process uid.")
    var uid: UInt32?

    @Flag(help: "launchctl bootout + bootstrap (legacy load fallback). Off by default.")
    var bootstrap: Bool = false

    @Flag(help: "launchctl kickstart -k after bootstrap. Off by default; requires --bootstrap.")
    var kickstart: Bool = false

    func run() async throws {
        let sourceURL = URL(fileURLWithPath: (source as NSString).expandingTildeInPath)
        let destURL = URL(fileURLWithPath: (destination as NSString).expandingTildeInPath)
        let homePath = (home ?? NSHomeDirectory())
        let resolvedUID = uid ?? UInt32(getuid())
        let spec = LaunchAgentInstaller.Spec(
            label: label,
            home: homePath,
            uid: resolvedUID,
            bootstrap: bootstrap,
            kickstart: kickstart
        )
        let installer = LaunchAgentInstaller()
        let report = try await installer.install(source: sourceURL, destination: destURL, spec: spec)
        print(report)
    }
}

