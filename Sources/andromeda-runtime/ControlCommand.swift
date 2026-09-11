import ArgumentParser
import Foundation

// MARK: - Control (pillar 3 access surface)

//
// NOTE: files in this executable target are compiled as one module with
// top-level-code main.swift, so this file must NOT use @main and all command
// structs stay non-top-level.

/// Thin CLI translator onto the loopback control plane. Holds no logic of
/// its own — state, actions, and their names all come from the plane.
struct Control: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Drive the runtime control plane: curated state, typed actions.",
        subcommands: [State.self, Actions.self, Run.self],
        defaultSubcommand: State.self
    )

    @Option(name: .long, help: "Runtime base URL (default http://127.0.0.1:8788). Env: ANDROMEDA_RUNTIME_URL.")
    var url: String?

    @Option(name: .long, help: "Bearer token for /control/*. Env: ANDROMEDA_MCP_BEARER_TOKEN.")
    var token: String?

    static func baseURL(_ option: String?) -> URL {
        let raw = option
            ?? HostDefaults.env("ANDROMEDA_RUNTIME_URL")
            ?? "http://127.0.0.1:\(HostDefaults.defaultPort)"
        return URL(string: raw) ?? URL(string: "http://127.0.0.1:\(HostDefaults.defaultPort)")!
    }

    static func bearer(_ option: String?) -> String {
        option ?? HostDefaults.env("ANDROMEDA_MCP_BEARER_TOKEN") ?? ""
    }

    /// Shared request helper. Prints response body; non-2xx exits non-zero.
    static func request(_ method: String, _ path: String, base: URL, bearer: String, body: Data? = nil) async throws {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        guard !bearer.isEmpty else {
            throw ValidationError("No bearer token — pass --token or set ANDROMEDA_MCP_BEARER_TOKEN.")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ValidationError("Unreachable: \(base) — is the runtime serving? (\(error.localizedDescription))")
        }
        guard let http = response as? HTTPURLResponse else {
            throw ValidationError("Non-HTTP response from \(base)")
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            print(text)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw ExitCode(1)
        }
    }
}

extension Control {
    /// GET /control/state — curated snapshot.
    struct State: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Read the curated runtime state snapshot.")

        @OptionGroup var options: Control

        func run() async throws {
            try await Control.request(
                "GET",
                "/control/state",
                base: Control.baseURL(options.url),
                bearer: Control.bearer(options.token)
            )
        }
    }

    /// GET /control/actions — the action catalogue.
    struct Actions: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List control-plane actions.")

        @OptionGroup var options: Control

        func run() async throws {
            try await Control.request(
                "GET",
                "/control/actions",
                base: Control.baseURL(options.url),
                bearer: Control.bearer(options.token)
            )
        }
    }

    /// POST /control/action — typed dispatch.
    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Execute a control-plane action.")

        @OptionGroup var options: Control

        @Argument(help: "Action name (see `control actions`).")
        var action: String

        func run() async throws {
            let body = try JSONEncoder().encode(["action": action])
            try await Control.request(
                "POST",
                "/control/action",
                base: Control.baseURL(options.url),
                bearer: Control.bearer(options.token),
                body: body
            )
        }
    }
}
