import Foundation

/// `capture` — checkout a side's SHA, install, build, serve, screenshot, stop.
/// `diff` — invoke the Node pixel-differ.
public enum Capture {
    public struct Options {
        public let side: String
        public let sha: String
        public let port: Int
        public let repoRoot: URL
        public let toolingDir: URL

        public init(side: String, sha: String, port: Int, repoRoot: URL, toolingDir: URL) {
            self.side = side
            self.sha = sha
            self.port = port
            self.repoRoot = repoRoot
            self.toolingDir = toolingDir
        }
    }

    @discardableResult
    public static func run(_ options: Options) throws -> ShellResult {
        let root = options.repoRoot
        log("capturing \(options.side) @ \(options.sha.prefix(8))")

        try Shell.runChecked(["git", "checkout", "-q", options.sha], cwd: root)

        // npm/cli#4828: optional platform binaries can vanish from a cached
        // install — probe lightningcss and reinstall from scratch if missing.
        try Shell.runChecked(["npm", "install"], cwd: root)
        if !lightningcssLoads(root: root) {
            log("lightningcss probe failed — clean reinstall (npm/cli#4828)")
            try shellRemove(paths: ["node_modules", "web/node_modules", "package-lock.json"], root: root)
            try Shell.runChecked(["npm", "install"], cwd: root)
        }

        try Shell.runChecked(["npm", "run", "build"], cwd: root)

        let server = try startServer(port: options.port, root: root)
        defer {
            server.process.terminate()
            server.process.waitUntilExit()
        }
        try waitForHealth(port: options.port)

        let shotsDir = root.appendingPathComponent("shots/\(options.side)")
        try FileManager.default.createDirectory(
            at: shotsDir, withIntermediateDirectories: true
        )
        try Shell.runChecked(
            ["node", options.toolingDir.appendingPathComponent("shot.mjs").path,
             "http://localhost:\(options.port)", shotsDir.path],
            cwd: root
        )
        // Reinstalls may have rewritten the lockfile; restore the committed
        // state so the NEXT capture's checkout can never be blocked by a
        // locally-modified file (e.g. a PR that changes package-lock.json).
        _ = try? Shell.runChecked(
            ["git", "checkout", "-q", "--", "package-lock.json", "web/package-lock.json"],
            cwd: root
        )
        log("captured \(options.side)")
        return ShellResult(exitCode: 0, stdout: "", stderr: "")
    }

    public static func diff(base: URL, head: URL, out: URL, toolingDir: URL) throws {
        try FileManager.default.createDirectory(
            at: out, withIntermediateDirectories: true
        )
        try Shell.runChecked(
            ["node", toolingDir.appendingPathComponent("diff.mjs").path,
             base.path, head.path, out.path]
        )
    }

    /// The server runs the real `next` entrypoint under `node`, so terminating
    /// the process kills the server itself (no orphaned shim children).
    /// Startup output is teed to our stderr: a config error inside `next
    /// start` must be visible in the CI log, not swallowed into a health-loop
    /// timeout.
    private static func startServer(port: Int, root: URL) throws -> (process: Process, url: String) {
        let nextBin = resolveNextBin(root: root)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", nextBin, "start", "-p", String(port)]
        process.currentDirectoryURL = root.appendingPathComponent("web")
        process.standardOutput = FileHandle.standardError
        process.standardError = FileHandle.standardError
        try process.run()
        return (process, "http://localhost:\(port)")
    }

    private static func resolveNextBin(root: URL) -> String {
        // npm workspaces hoist — the package may sit at the root or in web/.
        for candidate in [
            root.appendingPathComponent("node_modules/next/dist/bin/next"),
            root.appendingPathComponent("web/node_modules/next/dist/bin/next"),
        ] {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        return "next" // let node fail loudly if truly absent
    }

    private static func waitForHealth(port: Int) throws {
        let url = "http://localhost:\(port)/"
        for _ in 0..<45 {
            if let result = try? Shell.run(["curl", "-sf", url]), result.succeeded {
                return
            }
            Thread.sleep(forTimeInterval: 2)
        }
        throw ShellError.failed(
            command: "curl -sf \(url)",
            result: ShellResult(exitCode: 1, stdout: "", stderr: "server never became healthy")
        )
    }

    private static func lightningcssLoads(root: URL) -> Bool {
        let probe = "try { require('lightningcss'); console.log('ok') } catch { process.exit(1) }"
        let result = (try? Shell.run(
            ["node", "-e", probe],
            cwd: root.appendingPathComponent("web")
        ))
        return result?.succeeded ?? false
    }

    private static func shellRemove(paths: [String], root: URL) throws {
        for path in paths {
            let url = root.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("[visual-diff] \(message)\n".utf8))
    }
}
