// ASTGrep.swift — the engine behind the curtain: locating the ast-grep
// binary, containing every target under the workspace root, and running
// child processes with drained pipes and a timeout race.

import Foundation

// MARK: - Match model

/// A single match as emitted by `sg run --json=compact`.
struct ASTGrepMatch: Decodable, Sendable {
    struct Position: Decodable, Sendable {
        let line: Int
        let column: Int
    }

    struct Range: Decodable, Sendable {
        let start: Position
        let end: Position
    }

    struct Capture: Decodable, Sendable {
        let text: String
    }

    struct MetaVariables: Decodable, Sendable {
        let single: [String: Capture]?
        let multi: [String: [Capture]]?
    }

    let file: String
    let text: String
    let range: Range
    let replacement: String?
    let metaVariables: MetaVariables?

    /// 1-based display line (ast-grep reports 0-based).
    var displayLine: Int { range.start.line + 1 }

    /// Human-facing capture digest, e.g. `MSG="one", ARGS=a b c`.
    var captureSummary: String {
        let singles = (metaVariables?.single ?? [:])
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.text)" }
        let multis = (metaVariables?.multi ?? [:])
            .sorted { $0.key < $1.key }
            .compactMap { key, captures in
                let texts = captures.map(\.text)
                return texts.isEmpty ? nil : "\(key)=\(texts.joined(separator: " "))"
            }
        return (singles + multis).joined(separator: ", ")
    }
}

// MARK: - Errors

enum ASTGrepError: Error, LocalizedError, Sendable {
    case binaryNotFound
    case timedOut
    case exited(code: Int, stderr: String)
    case pathEscapesWorkspace(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return "code search engine not found on PATH"
        case .timedOut: return "code search timed out"
        case .exited(let code, let stderr): return "code search exited \(code): \(stderr)"
        case .pathEscapesWorkspace(let path): return "path escapes workspace root: \(path)"
        }
    }
}

// MARK: - Workspace containment (pure)

/// Resolve a client-supplied search/rewrite target under the workspace root
/// (the server's working directory). Absolute paths must resolve inside the
/// root; `..` components that climb out of it are rejected. Symlinks are
/// resolved on both sides so an in-tree link cannot pivot outside the root.
func containedTarget(_ clientPath: String?, root: String) throws -> String {
    let rootURL = URL(fileURLWithPath: root).resolvingSymlinksInPath()
    let rootPath = rootURL.path
    guard let clientPath = clientPath?.trimmingCharacters(in: .whitespacesAndNewlines),
          !clientPath.isEmpty else {
        return rootPath
    }
    let candidate = clientPath.hasPrefix("/")
        ? URL(fileURLWithPath: clientPath)
        : rootURL.appendingPathComponent(clientPath)
    let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL.path
    let contained = resolved == rootPath
        || resolved.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    guard contained else { throw ASTGrepError.pathEscapesWorkspace(clientPath) }
    return resolved
}

// MARK: - Command line construction (pure)

enum ASTGrepCommand {
    /// `--json` is inherently dry-run, so an apply pass runs twice: preview
    /// (`--json=compact` + `--rewrite`) then writer (`--update-all`).
    static func previewArguments(
        pattern: String, replacement: String?, language: String?, target: String
    ) -> [String] {
        var arguments = ["run", "--pattern", pattern, "--json=compact"]
        if let replacement { arguments += ["--rewrite", replacement] }
        if let language { arguments += ["--lang", language] }
        return arguments + [target]
    }

    static func writeArguments(
        pattern: String, replacement: String, language: String?, target: String
    ) -> [String] {
        var arguments = ["run", "--pattern", pattern, "--rewrite", replacement, "--update-all"]
        if let language { arguments += ["--lang", language] }
        return arguments + [target]
    }

    static func decodeMatches(from data: Data) throws -> [ASTGrepMatch] {
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return [] }
        return try JSONDecoder().decode([ASTGrepMatch].self, from: Data(output.utf8))
    }
}

// MARK: - Process execution

struct CommandResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

private enum Termination: Sendable {
    case exited(Int32)
    case timedOut
}

/// Foundation's `Process` predates Swift concurrency and is not `Sendable`.
/// This is the package's one deliberate unchecked box: termination, signal,
/// and status access are thread-safe, and every spawn is confined to a
/// single function so the handle never escapes further.
private struct SpawnHandle: @unchecked Sendable {
    let process = Process()
}

/// Drain a pipe as an async stream so a large match set cannot deadlock on a
/// full pipe buffer while the process runs.
private func collectOutput(_ handle: FileHandle) async -> Data {
    var data = Data()
    let chunks = AsyncStream(Data.self) { continuation in
        handle.readabilityHandler = { pipe in
            let chunk = pipe.availableData
            if chunk.isEmpty {
                pipe.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(chunk)
            }
        }
    }
    for await chunk in chunks {
        data.append(chunk)
    }
    return data
}

func runCommand(
    executable: URL,
    arguments: [String],
    workingDirectory: String,
    timeout: TimeInterval = 120
) async throws -> CommandResult {
    let spawn = SpawnHandle()
    spawn.process.executableURL = executable
    spawn.process.arguments = arguments
    spawn.process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    spawn.process.standardOutput = stdoutPipe
    spawn.process.standardError = stderrPipe

    do {
        try spawn.process.run()
    } catch {
        throw ASTGrepError.exited(code: 127, stderr: error.localizedDescription)
    }

    async let stdout = collectOutput(stdoutPipe.fileHandleForReading)
    async let stderr = collectOutput(stderrPipe.fileHandleForReading)

    // First of {exit, timeout} wins; the group waits for both, so after a
    // timeout the terminate() below lets the exit task complete promptly.
    // A child that ignores SIGTERM can still stall us — same posture as the
    // previous implementation.
    let termination = await withTaskGroup(of: Termination.self) { group in
        group.addTask {
            await withCheckedContinuation { continuation in
                spawn.process.terminationHandler = { exited in
                    continuation.resume(returning: .exited(exited.terminationStatus))
                }
            }
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(timeout))
            return .timedOut
        }
        let first = await group.next() ?? .timedOut
        group.cancelAll()
        if case .timedOut = first { spawn.process.terminate() }
        return first
    }

    switch termination {
    case .timedOut:
        throw ASTGrepError.timedOut
    case .exited(let status):
        return CommandResult(
            status: status,
            stdout: await stdout,
            stderr: await stderr
        )
    }
}

// MARK: - Engine location

enum EngineLocator {
    /// Resolve the pattern engine once per server lifetime: `ast-grep`
    /// first, then an `sg` that actually identifies as ast-grep (rejecting
    /// unrelated executables like `/usr/bin/sg` that merely shadow the name).
    static func locate() async -> URL? {
        var seen = Set<String>()
        for candidate in candidates() where seen.insert(candidate.path).inserted {
            guard FileManager.default.isExecutableFile(atPath: candidate.path) else { continue }
            if await identifiesAsASTGrep(candidate) { return candidate }
        }
        return nil
    }

    private static func candidates() -> [URL] {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var urls: [URL] = []
        for directory in path.split(separator: ":") {
            let base = URL(fileURLWithPath: String(directory))
            urls.append(base.appendingPathComponent("ast-grep"))
            urls.append(base.appendingPathComponent("sg"))
        }
        urls += [
            "/opt/homebrew/bin/ast-grep",
            "/usr/local/bin/ast-grep",
            "/opt/homebrew/bin/sg",
            "/usr/local/bin/sg",
        ].map { URL(fileURLWithPath: $0) }
        return urls
    }

    /// Predicate probe: any failure (missing, hung, wrong tool) means "not
    /// ast-grep," so collapsing the throw into `false` is the answer itself,
    /// not lost evidence.
    private static func identifiesAsASTGrep(_ candidate: URL) async -> Bool {
        guard let result = try? await runCommand(
            executable: candidate,
            arguments: ["--version"],
            workingDirectory: "/",
            timeout: 2
        ) else { return false }
        let banner = String(decoding: result.stdout + result.stderr, as: UTF8.self)
        return banner.localizedCaseInsensitiveContains("ast-grep")
    }
}

// MARK: - Tool execution

func runASTGrep(
    engine: URL,
    pattern: String,
    replacement: String? = nil,
    path: String? = nil,
    language: String? = nil,
    apply: Bool = false,
    workspaceRoot: String = FileManager.default.currentDirectoryPath
) async throws -> [ASTGrepMatch] {
    let target = try containedTarget(path, root: workspaceRoot)

    let preview = try await runCommand(
        executable: engine,
        arguments: ASTGrepCommand.previewArguments(
            pattern: pattern, replacement: replacement, language: language, target: target
        ),
        workingDirectory: workspaceRoot
    )

    let matches = try ASTGrepCommand.decodeMatches(from: preview.stdout)
    switch preview.status {
    case 0: break
    case 15, -15: throw ASTGrepError.timedOut
    default:
        throw ASTGrepError.exited(
            code: Int(preview.status),
            stderr: String(decoding: preview.stderr, as: UTF8.self)
        )
    }

    guard apply, let replacement else { return matches }

    let writer = try await runCommand(
        executable: engine,
        arguments: ASTGrepCommand.writeArguments(
            pattern: pattern, replacement: replacement, language: language, target: target
        ),
        workingDirectory: workspaceRoot
    )
    guard writer.status == 0 else {
        throw ASTGrepError.exited(
            code: Int(writer.status),
            stderr: String(decoding: writer.stderr, as: UTF8.self)
        )
    }
    return matches
}
