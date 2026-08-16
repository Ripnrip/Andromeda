import Foundation

/// Result of one subprocess run.
public struct ShellResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public var succeeded: Bool { exitCode == 0 }
}

public enum ShellError: Error, CustomStringConvertible {
    case failed(command: String, result: ShellResult)
    case timedOut(command: String, seconds: Double)

    public var description: String {
        switch self {
        case let .failed(command, result):
            return """
            command failed (\(result.exitCode)): \(command)
            --- stderr ---
            \(result.stderr)
            """
        case let .timedOut(command, seconds):
            return "command timed out after \(Int(seconds))s: \(command)"
        }
    }
}

/// Sequential subprocess helpers. The pipeline is strictly step-by-step,
/// so no concurrency surface is needed.
///
/// Output streams are file-backed, not pipes: a child that fills a pipe
/// buffer on one stream while we block reading the other would deadlock
/// (a noisy failing `npm run build` does exactly this). Files have no
/// bounded buffer, so both streams drain as the child writes.
public enum Shell {
    /// Default ceiling for any single command — builds are slow, hangs are
    /// worse.
    public static let defaultTimeout: Double = 900

    public static func run(
        _ arguments: [String],
        cwd: URL? = nil,
        environment: [String: String] = [:],
        timeout: Double = Shell.defaultTimeout
    ) throws -> ShellResult {
        guard let command = arguments.first, !command.isEmpty else {
            throw CLIError(description: "empty command")
        }
        let process = Process()
        // Route through env for PATH resolution of bare command names; env
        // execs the target, so the PID we hold IS the server process when
        // needed for termination.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }
        if !environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in environment { env[key] = value }
            process.environment = env
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("visual-diff-\(UUID().uuidString).out")
        let errURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("visual-diff-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }
        process.standardOutput = try FileHandle(forWritingTo: outURL)
        process.standardError = try FileHandle(forWritingTo: errURL)

        try process.run()

        // Bounded wait: hang → escalate terminate → interrupt → SIGKILL, so a
        // stubborn child can never wedge the job either running or reaping.
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        if process.isRunning {
            process.terminate()
            waitForExit(process, seconds: 3)
            if process.isRunning {
                process.interrupt()
                waitForExit(process, seconds: 2)
            }
            if process.isRunning {
                Shell.runChecked(["/bin/kill", "-9", String(process.processIdentifier)], timeout: 10)
                waitForExit(process, seconds: 5)
            }
            throw ShellError.timedOut(command: arguments.joined(separator: " "), seconds: timeout)
        }
        process.waitUntilExit()

        // The child is done writing; reading the files now cannot block.
        func contents(_ url: URL) -> String {
            guard let handle = try? FileHandle(forReadingFrom: url),
                  let data = try? handle.readToEnd()
            else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: contents(outURL),
            stderr: contents(errURL)
        )
    }

    /// Polls a process for up to `seconds`, returning when it exits.
    private static func waitForExit(_ process: Process, seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Runs a command, throwing a descriptive error on non-zero exit.
    @discardableResult
    public static func runChecked(
        _ arguments: [String],
        cwd: URL? = nil,
        environment: [String: String] = [:],
        allowFailure: Bool = false,
        timeout: Double = Shell.defaultTimeout
    ) throws -> ShellResult {
        let result = try run(arguments, cwd: cwd, environment: environment, timeout: timeout)
        if !result.succeeded && !allowFailure {
            throw ShellError.failed(command: arguments.joined(separator: " "), result: result)
        }
        return result
    }

    static func toolExists(_ name: String) -> Bool {
        guard let result = try? run(["/usr/bin/which", name], timeout: 10) else { return false }
        return result.succeeded && !result.stdout.trimmed().isEmpty
    }
}

extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
