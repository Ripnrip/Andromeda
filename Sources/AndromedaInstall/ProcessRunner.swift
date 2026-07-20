import Foundation

/// Result of a synchronous subprocess invocation.
public struct ProcessResult: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { exitCode == 0 }
}

/// Abstraction over `Process` so install planning/tests stay portable.
public protocol ProcessRunning: Sendable {
    /// Runs `executable` with `arguments` and returns captured output.
    func run(
        executable: String,
        arguments: [String],
        currentDirectory: String?
    ) throws -> ProcessResult
}

/// Foundation-backed runner using absolute executable paths.
public struct FoundationProcessRunner: ProcessRunning {
    public init() {}

    /// Spawns a process and waits for exit; throws when launch itself fails.
    public func run(
        executable: String,
        arguments: [String],
        currentDirectory: String?
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}

extension ProcessRunning {
    /// Runs a command and throws `InstallError.commandFailed` on non-zero exit.
    public func requireSuccess(
        executable: String,
        arguments: [String],
        currentDirectory: String? = nil
    ) throws {
        let result = try run(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory
        )
        guard result.succeeded else {
            throw InstallError.commandFailed(
                executable: executable,
                arguments: arguments,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }
}
