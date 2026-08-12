import AndromedaHostOps
import AndromedaPowerKit
import Foundation
import Testing

@Suite("TestFlightUploader")
struct TestFlightUploaderTests {

    @Test("archive + export + upload succeeds under power lease")
    func fullPipelineSuccess() async throws {
        let shell = MockShell(responses: [
            "xcodebuild archive": ShellResult(success: true, output: "ARCHIVE SUCCESS"),
            "xcodebuild -exportArchive": ShellResult(success: true, output: "EXPORT SUCCESS"),
            "xcrun altool": ShellResult(success: true, output: "UPLOAD SUCCESS"),
        ])
        let uploader = TestFlightUploader(
            coordinator: PowerLeaseCoordinator(backend: NoopPowerBackend()),
            shell: shell
        )

        let config = TestFlightUploader.Configuration(
            projectPath: "/tmp/Test.xcodeproj",
            scheme: "TestApp",
            exportOptionsPath: "/tmp/ExportOptions.plist",
            outputDir: "/tmp/output",
            apiKeyPath: "/tmp/AuthKey.p8",
            apiKeyID: "ABC123",
            apiIssuerID: "uuid-here"
        )

        let result = try await uploader.run(config)
        #expect(result.uploadSuccess == true)
        #expect(result.ipaPath == "/tmp/output/TestApp.ipa")
        #expect(result.logs.contains { $0.contains("Archive complete") })
        #expect(result.logs.contains { $0.contains("Upload complete") })
    }

    @Test("archive failure propagates error and releases lease")
    func archiveFailure() async {
        let shell = MockShell(responses: [
            "xcodebuild archive": ShellResult(success: false, output: "BUILD FAILED"),
        ])
        let coordinator = PowerLeaseCoordinator(backend: NoopPowerBackend())
        let uploader = TestFlightUploader(coordinator: coordinator, shell: shell)

        let config = TestFlightUploader.Configuration(
            projectPath: "/tmp/Test.xcodeproj",
            scheme: "TestApp",
            exportOptionsPath: "/tmp/ExportOptions.plist",
            outputDir: "/tmp/output"
        )

        await #expect(throws: TestFlightUploader.UploadError.self) {
            try await uploader.run(config)
        }

        // Verify lease was released
        let status = await coordinator.status()
        #expect(status.activeLeases.count == 0)
    }

    @Test("archiveOnly skips upload")
    func archiveOnlySkipsUpload() async throws {
        let shell = MockShell(responses: [
            "xcodebuild archive": ShellResult(success: true, output: "ARCHIVE SUCCESS"),
            "xcodebuild -exportArchive": ShellResult(success: true, output: "EXPORT SUCCESS"),
        ])
        let uploader = TestFlightUploader(
            coordinator: PowerLeaseCoordinator(backend: NoopPowerBackend()),
            shell: shell
        )

        let config = TestFlightUploader.Configuration(
            projectPath: "/tmp/Test.xcodeproj",
            scheme: "TestApp",
            exportOptionsPath: "/tmp/ExportOptions.plist",
            outputDir: "/tmp/output",
            archiveOnly: true
        )

        let result = try await uploader.run(config)
        #expect(result.uploadSuccess == false)
        #expect(result.ipaPath != nil)
    }

    @Test("upload without credentials throws missingUploadCredentials")
    func missingCredentials() async {
        let shell = MockShell(responses: [
            "xcodebuild archive": ShellResult(success: true, output: "ARCHIVE SUCCESS"),
            "xcodebuild -exportArchive": ShellResult(success: true, output: "EXPORT SUCCESS"),
        ])
        let coordinator = PowerLeaseCoordinator(backend: NoopPowerBackend())
        let uploader = TestFlightUploader(coordinator: coordinator, shell: shell)

        let config = TestFlightUploader.Configuration(
            projectPath: "/tmp/Test.xcodeproj",
            scheme: "TestApp",
            exportOptionsPath: "/tmp/ExportOptions.plist",
            outputDir: "/tmp/output"
        )

        await #expect(throws: TestFlightUploader.UploadError.self) {
            try await uploader.run(config)
        }

        // Lease released even on upload failure
        let status = await coordinator.status()
        #expect(status.activeLeases.count == 0)
    }
}

// MARK: - Mock shell

private actor MockShell: ShellExecuting {
    let responses: [String: ShellResult]

    init(responses: [String: ShellResult]) {
        self.responses = responses
    }

    func execute(_ arguments: [String]) async throws -> ShellResult {
        let joined = arguments.joined(separator: " ")
        for (key, response) in responses {
            if joined.contains(key) {
                return response
            }
        }
        return ShellResult(success: false, output: "No mock for: \(joined)")
    }
}

/// No-op power backend for tests.
private actor NoopPowerBackend: PowerAssertionBackend {
    func apply(preventSystemSleep: Bool, preventDisplaySleep: Bool, reason: String) async {}
    func clear() async {}
}
