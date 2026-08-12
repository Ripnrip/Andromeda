import AndromedaPowerKit
import Foundation

/// Archive and upload an Xcode project to TestFlight under a power lease.
///
/// The lease prevents system sleep during long archive + upload operations.
/// On any failure (build, export, upload, or cancellation), the lease is released.
public actor TestFlightUploader {
    private let coordinator: PowerLeaseCoordinator
    private let shell: any ShellExecuting

    public init(
        coordinator: PowerLeaseCoordinator = PowerLeaseCoordinator(),
        shell: any ShellExecuting = LiveShell()
    ) {
        self.coordinator = coordinator
        self.shell = shell
    }

    // MARK: - Public API

    public struct Configuration: Sendable {
        public let projectPath: String
        public let scheme: String
        public let exportOptionsPath: String
        public let outputDir: String
        public let teamID: String?
        public let apiKeyPath: String?
        public let apiKeyID: String?
        public let apiIssuerID: String?
        public let archiveOnly: Bool

        public init(
            projectPath: String,
            scheme: String,
            exportOptionsPath: String,
            outputDir: String,
            teamID: String? = nil,
            apiKeyPath: String? = nil,
            apiKeyID: String? = nil,
            apiIssuerID: String? = nil,
            archiveOnly: Bool = false
        ) {
            self.projectPath = projectPath
            self.scheme = scheme
            self.exportOptionsPath = exportOptionsPath
            self.outputDir = outputDir
            self.teamID = teamID
            self.apiKeyPath = apiKeyPath
            self.apiKeyID = apiKeyID
            self.apiIssuerID = apiIssuerID
            self.archiveOnly = archiveOnly
        }
    }

    public struct Result: Sendable {
        public let archivePath: String
        public let ipaPath: String?
        public let uploadSuccess: Bool
        public let logs: [String]
    }

    public enum UploadError: Error, Sendable {
        case archiveFailed(String)
        case exportFailed(String)
        case uploadFailed(String)
        case missingUploadCredentials
        case ipaNotFound(String)
    }

    public func run(_ config: Configuration) async throws -> Result {
        try await coordinator.withLease(
            owner: "testflight-agent",
            reason: "Archive + upload \(config.scheme)",
            requirements: [.preventSystemSleep]
        ) {
            try await self.archive(config)
        }
    }

    // MARK: - Pipeline steps

    private func archive(_ config: Configuration) async throws -> Result {
        let archivePath = "\(config.outputDir)/\(config.scheme).xcarchive"
        let dateFormatter = ISO8601DateFormatter()
        var logs: [String] = []

        // Step 1: Archive — select -workspace vs -project from path extension
        logs.append("[\(dateFormatter.string(from: Date()))] Starting archive: \(config.scheme)")
        let isWorkspace = config.projectPath.hasSuffix(".xcworkspace")
        let projectFlag = isWorkspace ? "-workspace" : "-project"
        var archiveArgs = [
            "xcodebuild", "archive",
            projectFlag, config.projectPath,
            "-scheme", config.scheme,
            "-archivePath", archivePath,
            "-destination", "generic/platform=iOS",
            "CODE_SIGNING_REQUIRED=YES",
            "CODE_SIGNING_ALLOWED=YES",
        ]
        if let teamID = config.teamID {
            archiveArgs.append("DEVELOPMENT_TEAM=\(teamID)")
        }

        let archiveResult = try await shell.execute(archiveArgs)
        logs.append(archiveResult.output)
        if !archiveResult.success {
            throw UploadError.archiveFailed(archiveResult.output.suffix(500).description)
        }
        logs.append("[\(dateFormatter.string(from: Date()))] Archive complete: \(archivePath)")

        // Step 2: Export IPA
        logs.append("[\(dateFormatter.string(from: Date()))] Exporting IPA…")
        let exportArgs = [
            "xcodebuild", "-exportArchive",
            "-archivePath", archivePath,
            "-exportOptionsPlist", config.exportOptionsPath,
            "-exportPath", config.outputDir,
        ]
        let exportResult = try await shell.execute(exportArgs)
        logs.append(exportResult.output)
        if !exportResult.success {
            throw UploadError.exportFailed(exportResult.output.suffix(500).description)
        }

        // Discover the actual IPA — xcodebuild names it after the product,
        // not the scheme, so we scan the export directory.
        let ipaPath = discoverIPA(in: config.outputDir) ?? "\(config.outputDir)/\(config.scheme).ipa"
        logs.append("[\(dateFormatter.string(from: Date()))] IPA exported: \(ipaPath)")

        if config.archiveOnly {
            return Result(archivePath: archivePath, ipaPath: ipaPath, uploadSuccess: false, logs: logs)
        }

        // Step 3: Upload to TestFlight via altool
        guard let keyPath = config.apiKeyPath,
              let keyID = config.apiKeyID,
              let issuerID = config.apiIssuerID
        else {
            throw UploadError.missingUploadCredentials
        }

        logs.append("[\(dateFormatter.string(from: Date()))] Uploading to TestFlight…")
        let uploadArgs = [
            "xcrun", "altool",
            "--upload-app",
            "--type", "ios",
            "--file", ipaPath,
            "--apiKey", keyID,
            "--apiIssuer", issuerID,
            "--key", keyPath,
        ]
        let uploadResult = try await shell.execute(uploadArgs)
        logs.append(uploadResult.output)
        if !uploadResult.success {
            throw UploadError.uploadFailed(uploadResult.output.suffix(500).description)
        }
        logs.append("[\(dateFormatter.string(from: Date()))] Upload complete ✅")

        return Result(archivePath: archivePath, ipaPath: ipaPath, uploadSuccess: true, logs: logs)
    }

    private func discoverIPA(in directory: String) -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { return nil }
        return entries.first { $0.hasSuffix(".ipa") }
            .map { "\(directory)/\($0)" }
    }
}

// MARK: - Shell protocol

public struct ShellResult: Sendable {
    public let success: Bool
    public let output: String

    public init(success: Bool, output: String) {
        self.success = success
        self.output = output
    }
}

public protocol ShellExecuting: Sendable {
    func execute(_ arguments: [String]) async throws -> ShellResult
}

/// Live shell executor using Process.
///
/// Uses readabilityHandler to drain output concurrently (prevents pipe-buffer
/// deadlock when xcodebuild writes large volumes).  Terminates the child on
/// task cancellation so power leases are released promptly.
public struct LiveShell: ShellExecuting {
    public init() {}

    public func execute(_ arguments: [String]) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Accumulate output incrementally via readabilityHandler.
        // This drains the pipe concurrently while the process runs,
        // preventing the deadlock where the child blocks on a full pipe
        // while the parent blocks in waitUntilExit.
        let outputBox = SendableBox()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                outputBox.append(data)
            }
        }

        return try await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                do {
                    try process.run()
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: ShellResult(
                        success: false,
                        output: "Failed to launch: \(error.localizedDescription)"
                    ))
                    return
                }

                // Wait for exit on a background thread so we don't block the actor.
                process.terminationHandler = { proc in
                    // Stop the readabilityHandler and read any remaining bytes.
                    pipe.fileHandleForReading.readabilityHandler = nil
                    let finalData = pipe.fileHandleForReading.readDataToEndOfFile()
                    outputBox.append(finalData)

                    continuation.resume(returning: ShellResult(
                        success: proc.terminationStatus == 0,
                        output: outputBox.string
                    ))
                }
            }
        } onCancel: {
            // Terminate the child process when the task is cancelled
            // so the power lease is released promptly.
            if process.isRunning {
                process.terminate()
            }
        }
    }
}

/// Thread-safe mutable byte accumulator for concurrent pipe draining.
private final class SendableBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
