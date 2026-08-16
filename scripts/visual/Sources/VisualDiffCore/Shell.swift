import Foundation

/// Result of one subprocess run.
public struct ShellResult {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public var succeeded: Bool { exitCode == 0 }
}

enum ShellError: Error, CustomStringConvertible {
    case failed(command: String, result: ShellResult)

    var description: String {
        guard case let .failed(command, result) = self else { return "shell error" }
        return """
        command failed (\(result.exitCode)): \(command)
        --- stderr ---
        \(result.stderr)
        """
    }
}

/// Sequential subprocess helpers. The pipeline is strictly step-by-step,
/// so no concurrency surface is needed.
enum Shell {
    static func run(
        _ arguments: [String],
        cwd: URL? = nil,
        environment: [String: String] = [:]
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
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Runs a command, throwing a descriptive error on non-zero exit.
    @discardableResult
    static func runChecked(
        _ arguments: [String],
        cwd: URL? = nil,
        environment: [String: String] = [:],
        allowFailure: Bool = false
    ) throws -> ShellResult {
        let result = try run(arguments, cwd: cwd, environment: environment)
        if !result.succeeded && !allowFailure {
            throw ShellError.failed(command: arguments.joined(separator: " "), result: result)
        }
        return result
    }

    static func toolExists(_ name: String) -> Bool {
        guard let result = try? run(["/usr/bin/which", name]) else { return false }
        return result.succeeded && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
