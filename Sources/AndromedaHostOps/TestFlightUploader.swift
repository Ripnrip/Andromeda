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
        /// Path to .xcodeproj or .xcworkspace.
        public let projectPath: String
        /// Xcode scheme name to archive.
        public let scheme: String
        /// Path to ExportOptions.plist for IPA export.
        public let exportOptionsPath: String
        /// Output directory for archive + IPA.
        public let outputDir: String
        /// Optional team ID for signing.
        public let teamID: String?
        /// Optional API key path (.p8) for altool upload.
        public let apiKeyPath: String?
        /// Optional API key ID for altool upload.
        public let apiKeyID: String?
        /// Optional API issuer ID for altool upload.
        public let apiIssuerID: String?
        /// Skip upload — only archive + export IPA.
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
    }

    /// Run the full archive → export → upload pipeline under a power lease.
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

        // Step 1: Archive
        logs.append("[\(dateFormatter.string(from: Date()))] Starting archive: \(config.scheme)")
        var archiveArgs = [
            "xcodebuild", "archive",
            "-project", config.projectPath,
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
        let ipaPath = "\(config.outputDir)/\(config.scheme).ipa"
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
public struct LiveShell: ShellExecuting {
    public init() {}

    public func execute(_ arguments: [String]) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Run in a detached task so it's not bound to the actor's executor
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
            } catch {
                continuation.resume(returning: ShellResult(success: false, output: "Failed to launch: \(error.localizedDescription)"))
                return
            }

            DispatchQueue.global().async {
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: ShellResult(
                    success: process.terminationStatus == 0,
                    output: output
                ))
            }
        }
    }
}
