import AndromedaServer
import ArgumentParser
import Foundation
import Logging

@main
struct AndromedaRuntimeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "andromeda-runtime",
        abstract: "Runnable Andromeda Runtime v2 server.",
        subcommands: [Serve.self],
        defaultSubcommand: Serve.self
    )
}

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

    func run() async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .info
            return handler
        }

        let logger = Logger(label: "andromeda.runtime.cli")
        guard let qdrantBaseURL = URL(string: qdrantUrl) else {
            throw ValidationError("Invalid Qdrant URL: \(qdrantUrl)")
        }
        let server = try AndromedaRuntimeServer(
            configuration: AndromedaRuntimeConfiguration(host: host, port: port),
            journalFileURL: URL(fileURLWithPath: journalPath),
            vaultDirectoryURL: vaultDir.map { URL(fileURLWithPath: $0) },
            qdrantBaseURL: qdrantBaseURL,
            logger: logger
        )
        try await server.run()
    }
}
