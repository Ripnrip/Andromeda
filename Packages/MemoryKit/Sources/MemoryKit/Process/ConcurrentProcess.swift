// ConcurrentProcess.swift — spawn a child and drain its pipes BEFORE
// waiting for exit (swift-canon Exhibit 3: await-exit-then-read deadlocks
// once the child fills the ~64KB pipe buffer — a fleet-scale `ps -axo`
// with long command lines crosses it trivially).
//
// Sync shape: both pipes drain on dispatch threads (never the cooperative
// pool), the caller waits for exit, then joins the drains. In-repo
// precedent: RetrievalService's PipeDataBoxes — this is that pattern
// extracted for the registry / project-state call sites.

import Foundation

enum ConcurrentProcess {
    struct Output: Sendable {
        let status: Int32
        let stdout: Data
        let stderr: Data
    }

    enum ProcessError: Error, LocalizedError {
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let message): return message
            }
        }
    }

    /// Written by exactly one dispatch drain thread; read by the caller only
    /// after the matching semaphore signals — that happens-before ordering
    /// is the stated invariant behind the `@unchecked` (same justification
    /// as RetrievalService.PipeDataBoxes).
    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    /// Run a child to completion with both pipes drained concurrently.
    /// The drain-before-wait ordering is the entire point: swapping this in
    /// for a wait-then-read sequence is how Exhibit 3 deadlocks ship.
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do { try process.run() } catch {
            throw ProcessError.launchFailed(error.localizedDescription)
        }

        // Start BOTH drains before waiting for exit.
        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let stdoutDone = DispatchSemaphore(value: 0)
        let stderrDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            stdoutDone.signal()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            stderrDone.signal()
        }

        process.waitUntilExit()
        stdoutDone.wait()
        stderrDone.wait()

        return Output(
            status: process.terminationStatus,
            stdout: stdoutBox.data,
            stderr: stderrBox.data
        )
    }
}
