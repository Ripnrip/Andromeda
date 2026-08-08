import AndromedaBrand
import AndromedaCore
import AndromedaGateway
import ArgumentParser
import Foundation
import Logging

@main
struct Andromeda: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "andromeda",
        abstract: "Andromeda — Swift-native control plane and Hummingbird model gateway.",
        version: AndromedaVersion.string,
        subcommands: [Serve.self, Status.self, Brand.self],
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
