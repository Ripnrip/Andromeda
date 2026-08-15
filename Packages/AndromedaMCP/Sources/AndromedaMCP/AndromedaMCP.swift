// AndromedaMCP — MCP stdio server exposing ast-grep search/rewrite as tools.
// Replaces the OMC Node bridge: one small Swift 6 binary, zero dependencies.
//
// Protocol: Model Context Protocol over stdio (JSON-RPC 2.0, line-delimited).
// Tools:
//   code.search  — AST pattern search (engine behind the curtain)
//   code.replace — AST rewrite (dry-run by default)

import Foundation

// MARK: - JSON-RPC types

struct RPCRequest: Decodable {
    let jsonrpc: String?
    let id: JSONValue?
    let method: String
    let params: JSONValue?
}

/// Minimal JSON value model — enough to route JSON-RPC without a dependency.
enum JSONValue: Decodable, @unchecked Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if let n = try? container.decode(Double.self) { self = .number(n) }
        else if let s = try? container.decode(String.self) { self = .string(s) }
        else if let a = try? container.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? container.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unsupported JSON")) }
    }

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var doubleValue: Double? { if case .number(let n) = self { return n }; return nil }
    var intValue: Int? { if case .number(let n) = self { return n == n.rounded() ? Int(n) : nil }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }

    /// Serialize back to JSON text.
    var encoded: String {
        switch self {
        case .string(let s): return Self.escaped(s)
        case .number(let n):
            if n == n.rounded(), abs(n) < 1e15 { return String(Int(n)) }
            return String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let a): return "[" + a.map(\.encoded).joined(separator: ",") + "]"
        case .object(let o):
            let keys = o.keys.sorted()
            return "{" + keys.map { "\(Self.escaped($0)):\(o[$0]!.encoded)" }.joined(separator: ",") + "}"
        }
    }

    private static func escaped(_ raw: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [raw]) else { return raw }
        let text = String(decoding: data, as: UTF8.self)
        return String(text.dropFirst().dropLast())
    }
}

// MARK: - Tool schemas (hand-rolled JSON to stay dependency-free)

func toolSchemas() -> JSONValue {
    .object([
        "code.search": .object([
            "name": .string("code.search"),
            "description": .string("""
                Search for code patterns using AST matching. More precise than text search.

                Use meta-variables in patterns:
                - $NAME - matches any single AST node (identifier, expression, etc.)
                - $$$ARGS - matches multiple nodes (for function arguments, list items, etc.)

                Examples:
                - "func $NAME($$$ARGS)" - find all function declarations
                - "print($MSG)" - find all print calls
                - "$X === nil" - find nil equality checks

                Note: Patterns must be valid AST nodes for the language.
                """),
            "inputSchema": .object([
                "type": .string("object"),
                "properties": .object([
                    "pattern": .object([
                        "type": .string("string"),
                        "description": .string("AST pattern with meta-variables ($X, $$$ARGS)"),
                    ]),
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("File or directory to search, resolved under the workspace root (default: root). Paths resolving outside the root are rejected."),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string("Language hint when file extension is ambiguous (swift, python, javascript, …)"),
                    ]),
                ]),
                "required": .array([.string("pattern")]),
            ]),
        ]),
        "code.replace": .object([
            "name": .string("code.replace"),
            "description": .string("""
                Replace code patterns using AST matching. Preserves matched content via meta-variables.

                IMPORTANT: dryRun=true (default) only previews changes. Set dryRun=false to apply.

                Examples:
                - Pattern: "print($MSG)" → Replacement: "logger.debug($MSG)"
                - Pattern: "var $NAME = $VALUE" → Replacement: "let $NAME = $VALUE"
                """),
            "inputSchema": .object([
                "type": .string("object"),
                "properties": .object([
                    "pattern": .object([
                        "type": .string("string"),
                        "description": .string("AST pattern with meta-variables"),
                    ]),
                    "replacement": .object([
                        "type": .string("string"),
                        "description": .string("Replacement template; reuse $NAME / $$$ARGS captures"),
                    ]),
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("File or directory to rewrite, resolved under the workspace root (default: root). Paths resolving outside the root are rejected."),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string("Language hint (swift, python, javascript, …)"),
                    ]),
                    "dryRun": .object([
                        "type": .string("boolean"),
                        "description": .string("true (default) = preview only; false = write changes to disk"),
                    ]),
                ]),
                "required": .array([.string("pattern"), .string("replacement")]),
            ]),
        ]),
    ])
}

// MARK: - ast-grep output model

/// A single match as emitted by `sg run --json=compact`, decoded directly
/// into a typed model — plus the presentation views the tools print.
struct ASTGrepMatch: Decodable {
    struct Position: Decodable {
        let line: Int
        let column: Int
    }

    struct Range: Decodable {
        let start: Position
        let end: Position
    }

    struct Capture: Decodable {
        let text: String
    }

    struct MetaVariables: Decodable {
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

// MARK: - ast-grep runner

enum ASTGrepError: Error, LocalizedError {
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

/// Thread-safe accumulator so we can drain child pipes while waiting for exit.
private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private struct CommandResult {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

/// True only if `path` is actually ast-grep (rejects shadowing tools named `sg`).
func isASTGrepExecutable(_ path: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["--version"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return false }

    let collected = LockedData()
    pipe.fileHandleForReading.readabilityHandler = { collected.append($0.availableData) }
    let deadline = DispatchTime.now() + .seconds(2)
    while process.isRunning, DispatchTime.now() < deadline {
        Thread.sleep(forTimeInterval: 0.01)
    }
    if process.isRunning { process.terminate() }
    pipe.fileHandleForReading.readabilityHandler = nil
    collected.append(pipe.fileHandleForReading.readDataToEndOfFile())
    let banner = String(decoding: collected.snapshot(), as: UTF8.self)
    return banner.localizedCaseInsensitiveContains("ast-grep")
}

/// Resolve the pattern engine: `ast-grep` first, then a verified `sg`.
func locateASTGrep() -> String? {
    var candidates: [String] = []
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for dir in path.split(separator: ":") {
        for name in ["ast-grep", "sg"] {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                candidates.append(candidate)
            }
        }
    }
    candidates += [
        "/opt/homebrew/bin/ast-grep",
        "/usr/local/bin/ast-grep",
        "/opt/homebrew/bin/sg",
        "/usr/local/bin/sg",
    ]

    var seen = Set<String>()
    return candidates.first { candidate in
        seen.insert(candidate).inserted && isASTGrepExecutable(candidate)
    }
}

/// Resolve a client-supplied search/rewrite target under the workspace root
/// (the server's working directory). Absolute paths must resolve inside the
/// root; `..` components that climb out of it are rejected. Symlinks are
/// resolved on both sides so an in-tree link cannot pivot outside the root.
func containedTarget(
    _ clientPath: String?,
    root: String = FileManager.default.currentDirectoryPath
) throws -> String {
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

/// Run the pattern engine and decode its matches.
///
/// `--json` is inherently dry-run, so an apply pass runs twice: preview
/// (`--json=compact` + `--rewrite`) then writer (`--update-all`, no `--json`).
/// Child stdout/stderr are drained while the process runs so a large match
/// set cannot deadlock on a full pipe buffer. All targets are contained to
/// the workspace root before the engine is invoked.
func runASTGrep(
    pattern: String,
    replacement: String? = nil,
    path: String? = nil,
    language: String? = nil,
    apply: Bool = false
) throws -> [ASTGrepMatch] {
    guard let engine = locateASTGrep() else { throw ASTGrepError.binaryNotFound }
    let workingDirectory = FileManager.default.currentDirectoryPath
    let target = try containedTarget(path, root: workingDirectory)

    func launch(_ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: engine)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let stdout = LockedData()
        let stderr = LockedData()
        outPipe.fileHandleForReading.readabilityHandler = { stdout.append($0.availableData) }
        errPipe.fileHandleForReading.readabilityHandler = { stderr.append($0.availableData) }

        try process.run()

        let timeout = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timeout.schedule(deadline: .now() + 120)
        timeout.setEventHandler { if process.isRunning { process.terminate() } }
        timeout.resume()

        let completion = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            process.waitUntilExit()
            completion.signal()
        }
        completion.wait()
        timeout.cancel()

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        stdout.append(outPipe.fileHandleForReading.readDataToEndOfFile())
        stderr.append(errPipe.fileHandleForReading.readDataToEndOfFile())

        return CommandResult(
            status: process.terminationStatus,
            stdout: stdout.snapshot(),
            stderr: stderr.snapshot()
        )
    }

    func decodeMatches(from result: CommandResult) throws -> [ASTGrepMatch] {
        let output = String(decoding: result.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return [] }
        return try JSONDecoder().decode([ASTGrepMatch].self, from: Data(output.utf8))
    }

    var previewArguments = ["run", "--pattern", pattern, "--json=compact"]
    if let replacement { previewArguments += ["--rewrite", replacement] }
    if let language { previewArguments += ["--lang", language] }
    previewArguments += [target]

    let preview = try launch(previewArguments)
    let matches = try decodeMatches(from: preview)
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

    var writeArguments = ["run", "--pattern", pattern, "--rewrite", replacement, "--update-all"]
    if let language { writeArguments += ["--lang", language] }
    writeArguments += [target]

    let writer = try launch(writeArguments)
    guard writer.status == 0 else {
        throw ASTGrepError.exited(
            code: Int(writer.status),
            stderr: String(decoding: writer.stderr, as: UTF8.self)
        )
    }
    return matches
}

// MARK: - Tool dispatch

func callTool(name: String, arguments: JSONValue?) throws -> String {
    let args = arguments?.objectValue ?? [:]

    switch name {
    case "code.search":
        guard let pattern = args["pattern"]?.stringValue else {
            return "Error: missing required argument 'pattern'"
        }
        let matches = try runASTGrep(
            pattern: pattern,
            path: args["path"]?.stringValue,
            language: args["language"]?.stringValue
        )
        guard !matches.isEmpty else { return "No matches found." }
        return (["Found \(matches.count) match(es):", ""]
            + matches.flatMap { match -> [String] in
                ["\(match.file):\(match.displayLine): \(match.text)"]
                    + (match.captureSummary.isEmpty ? [] : ["  ↳ \(match.captureSummary)"])
            }).joined(separator: "\n")

    case "code.replace":
        guard let pattern = args["pattern"]?.stringValue,
              let replacement = args["replacement"]?.stringValue else {
            return "Error: missing required arguments 'pattern' and 'replacement'"
        }
        let apply = args["dryRun"]?.boolValue.map({ !$0 }) ?? false
        let matches = try runASTGrep(
            pattern: pattern,
            replacement: replacement,
            path: args["path"]?.stringValue,
            language: args["language"]?.stringValue,
            apply: apply
        )
        guard !matches.isEmpty else { return "No matches found — nothing to replace." }

        let mode = apply ? "APPLIED" : "DRY RUN"
        var lines = ["\(mode): \(matches.count) replacement(s)", ""]
        for match in matches {
            guard let replacement = match.replacement else { continue }
            lines += [
                "\(match.file):\(match.displayLine):",
                "  - \(match.text)",
                "  + \(replacement)",
            ]
        }
        if !apply { lines += ["", "Preview only. Set dryRun=false to apply."] }
        return lines.joined(separator: "\n")

    default:
        return "Error: unknown tool '\(name)'"
    }
}

// MARK: - Server loop

@main
struct AndromedaMCPServer {
    static func main() {
        let input = FileHandle.standardInput
        var buffer = Data()

        func send(_ value: JSONValue) {
            var fields: [String: JSONValue] = ["jsonrpc": .string("2.0")]
            if case .object(let inner) = value { fields.merge(inner) { _, new in new } }
            FileHandle.standardOutput.write(Data((JSONValue.object(fields).encoded + "\n").utf8))
        }

        while let chunk = try? input.read(upToCount: 65536), !chunk.isEmpty {
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[buffer.index(after: newline)...])
                let line = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }
                guard let request = try? JSONDecoder().decode(
                    RPCRequest.self, from: Data(line.utf8)
                ) else {
                    send(.object([
                        "id": .null,
                        "error": .object([
                            "code": .number(-32700),
                            "message": .string("Parse error"),
                        ]),
                    ]))
                    continue
                }

                handle(request, send: send)
            }
        }
    }

    private static func handle(_ request: RPCRequest, send: (JSONValue) -> Void) {
        switch request.method {
        case "initialize":
            send(.object([
                "id": request.id ?? .null,
                "result": .object([
                    "protocolVersion": .string("2025-06-18"),
                    "capabilities": .object([
                        "tools": .object([:]),
                    ]),
                    "serverInfo": .object([
                        "name": .string("andromeda-mcp"),
                        "version": .string("1.0.0"),
                    ]),
                ]),
            ]))

        case "notifications/initialized":
            break // notification — no response

        case "tools/list":
            let schemas = toolSchemas()
            let tools: [JSONValue] = schemas.objectValue.map { toolMap in
                toolMap.keys.sorted().map { toolMap[$0]! }
            } ?? []
            send(.object([
                "id": request.id ?? .null,
                "result": .object(["tools": .array(tools)]),
            ]))

        case "tools/call":
            let name = request.params?.objectValue?["name"]?.stringValue ?? ""
            let arguments = request.params?.objectValue?["arguments"]
            let content: (text: String, isError: Bool)
            do {
                content = (try callTool(name: name, arguments: arguments), false)
            } catch {
                content = ("Error: \(error.localizedDescription)", true)
            }
            var result: [String: JSONValue] = [
                "content": .array([.object([
                    "type": .string("text"),
                    "text": .string(content.text),
                ])]),
            ]
            if content.isError { result["isError"] = .bool(true) }
            send(.object(["id": request.id ?? .null, "result": .object(result)]))

        default:
            guard request.id != nil else { break } // unknown notification
            send(.object([
                "id": request.id ?? .null,
                "error": .object([
                    "code": .number(-32601),
                    "message": .string("Method not found: \(request.method)"),
                ]),
            ]))
        }
    }
}
