import AndromedaHostOps
import Foundation
import Testing

@testable import AndromedaHostOps

/// LaunchAgentInstaller tests.
///
/// Never writes to `~/Library/LaunchAgents` and never calls live `launchctl`
/// against `com.andromeda.hud` / `com.andromeda.mcp-hub`. Bootstrap/kickstart
/// coverage is mocked.
@Suite(.serialized)
struct LaunchAgentInstallerTests {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("launch-agent-installer-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func isolatedHome(in dir: URL) -> String {
        dir.appendingPathComponent("other-home").path
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func writePlist(_ dir: URL, name: String, body: String) -> URL {
        let url = dir.appendingPathComponent(name)
        try! body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func fixturePlist(
        label: String = "com.andromeda.fixture.agent",
        home: String = LaunchAgentInstaller.studioHomeTemplate
    ) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(home)/Applications/Fixture.app/Contents/MacOS/Fixture</string>
            </array>
            <key>WorkingDirectory</key>
            <string>\(home)</string>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>StandardOutPath</key>
            <string>\(home)/.multibrain/logs/fixture.launchd.log</string>
            <key>StandardErrorPath</key>
            <string>\(home)/.multibrain/logs/fixture.launchd.log</string>
            <key>EnvironmentVariables</key>
            <dict>
                <key>HOME</key>
                <string>\(home)</string>
            </dict>
        </dict>
        </plist>
        """
    }

    private actor RecordingShell: ShellExecuting {
        private(set) var calls: [[String]] = []
        var failIfContains: [String] = []

        func setFailIfContains(_ values: [String]) {
            failIfContains = values
        }

        func execute(_ arguments: [String]) async throws -> ShellResult {
            calls.append(arguments)
            let joined = arguments.joined(separator: " ")
            if failIfContains.contains(where: { joined.contains($0) }) {
                return ShellResult(success: false, output: "mocked failure for: \(joined)")
            }
            return ShellResult(success: true, output: "")
        }

        func recorded() -> [[String]] { calls }
    }

    // MARK: - Rewrite

    @Test
    func rewritesStudioHomeTemplateAndCreatesLogDirectory() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = writePlist(dir, name: "src.plist", body: fixturePlist())
        let destination = dir.appendingPathComponent("LaunchAgents/com.andromeda.fixture.agent.plist")
        let otherHome = dir.appendingPathComponent("other-home").path
        let logDir = URL(fileURLWithPath: otherHome).appendingPathComponent(".multibrain/logs")

        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: otherHome, uid: 501, bootstrap: false)
        )

        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(!report.kickstarted)
        #expect(report.label == "com.andromeda.fixture.agent")
        #expect(report.domain == "gui/501")

        let rendered = try String(contentsOf: destination, encoding: .utf8)
        #expect(rendered.contains(otherHome))
        #expect(!rendered.contains(LaunchAgentInstaller.studioHomeTemplate))
        #expect(FileManager.default.fileExists(atPath: logDir.path))
        #expect(!destination.path.contains("/Library/LaunchAgents/"))
    }

    @Test
    func sameHomeDoesNotRequireTemplateAndDoesNotRewrite() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let already = fixturePlist(home: LaunchAgentInstaller.studioHomeTemplate)
        let source = writePlist(dir, name: "src.plist", body: already)
        let destination = dir.appendingPathComponent("out.plist")
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(
                home: LaunchAgentInstaller.studioHomeTemplate,
                uid: 501
            )
        )
        #expect(!report.rewritten)
        let rendered = try String(contentsOf: destination, encoding: .utf8)
        #expect(rendered.contains(LaunchAgentInstaller.studioHomeTemplate))
    }

    @Test
    func missingTemplateWhenHomeDiffersFails() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = writePlist(dir, name: "src.plist", body: fixturePlist(home: "/Users/someone-else"))
        let destination = dir.appendingPathComponent("out.plist")
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: "/Users/other", uid: 501)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func rejectsRelativeHome() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = writePlist(dir, name: "src.plist", body: fixturePlist())
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: dir.appendingPathComponent("out.plist"),
                spec: LaunchAgentInstaller.Spec(home: "Users/admin", uid: 501)
            )
        }
    }

    @Test
    func labelMismatchFails() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = writePlist(dir, name: "src.plist", body: fixturePlist())
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: dir.appendingPathComponent("out.plist"),
                spec: LaunchAgentInstaller.Spec(
                    label: "com.andromeda.hud",
                    home: "/Users/other",
                    uid: 501
                )
            )
        }
    }

    @Test
    func kickstartWithoutBootstrapFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = writePlist(dir, name: "src.plist", body: fixturePlist())
        let destination = dir.appendingPathComponent("out.plist")
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(
                    home: "/Users/other",
                    uid: 501,
                    bootstrap: false,
                    kickstart: true
                )
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    // MARK: - Bootstrap (mocked launchctl)

    @Test
    func bootstrapCallsBootoutThenBootstrapAndSkipsKickstart() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = writePlist(dir, name: "src.plist", body: fixturePlist())
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
        )
        #expect(report.bootstrapped)
        #expect(!report.usedLegacyLoad)
        #expect(!report.kickstarted)

        let calls = await shell.recorded()
        let joined = calls.map { $0.joined(separator: " ") }
        #expect(joined.contains("launchctl bootout gui/501/com.andromeda.fixture.agent"))
        #expect(joined.contains("launchctl bootstrap gui/501 \(destination.path)"))
        #expect(!joined.contains(where: { $0.contains("kickstart") }))
    }

    @Test
    func bootstrapFailureFallsBackToLegacyLoad() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = writePlist(dir, name: "src.plist", body: fixturePlist())
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let shell = RecordingShell()
        await shell.setFailIfContains(["launchctl bootstrap"])
        let installer = LaunchAgentInstaller(shell: shell)
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
        )
        #expect(report.bootstrapped)
        #expect(report.usedLegacyLoad)

        let calls = await shell.recorded()
        let joined = calls.map { $0.joined(separator: " ") }
        #expect(joined.contains(where: { $0.hasPrefix("launchctl unload ") }))
        #expect(joined.contains(where: { $0.hasPrefix("launchctl load ") }))
    }

    @Test
    func bootstrapAndLoadFailureThrows() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = writePlist(dir, name: "src.plist", body: fixturePlist())
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let shell = RecordingShell()
        await shell.setFailIfContains(["launchctl bootstrap", "launchctl load "])
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func bootstrapAndLoadFailureRestoresPreviousPlist() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = writePlist(dir, name: "src.plist", body: fixturePlist())
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "previous-plist-inode-marker\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let shell = RecordingShell()
        await shell.setFailIfContains(["launchctl bootstrap", "launchctl load "])
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(FileManager.default.fileExists(atPath: destination.path))
        let restored = try String(contentsOf: destination, encoding: .utf8)
        #expect(restored == previous)
        let restoredInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        #expect(restoredInode == oldInode)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func bootstrapAndLoadFailureLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = writePlist(dir, name: "src.plist", body: fixturePlist())
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let shell = RecordingShell()
        await shell.setFailIfContains(["launchctl bootstrap", "launchctl load "])
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func kickstartOptInSendsDashKThenFallsBack() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = writePlist(dir, name: "src.plist", body: fixturePlist())
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let shell = RecordingShell()
        await shell.setFailIfContains(["kickstart -k"])
        let installer = LaunchAgentInstaller(shell: shell)
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(
                home: home,
                uid: 501,
                bootstrap: true,
                kickstart: true
            )
        )
        #expect(report.bootstrapped)
        #expect(report.kickstarted)
        let calls = await shell.recorded()
        let joined = calls.map { $0.joined(separator: " ") }
        #expect(joined.contains("launchctl kickstart -k gui/501/com.andromeda.fixture.agent"))
        #expect(joined.contains("launchctl kickstart gui/501/com.andromeda.fixture.agent"))
    }

    // MARK: - Real ops templates (rewrite only)

    @Test
    func rewritesHudOpsTemplate() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = repoRoot().appendingPathComponent("ops/com.andromeda.hud.plist")
        let destination = dir.appendingPathComponent("com.andromeda.hud.plist")
        let otherHome = isolatedHome(in: dir)
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(
                label: "com.andromeda.hud",
                home: otherHome,
                uid: 501
            )
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        let rendered = try String(contentsOf: destination, encoding: .utf8)
        #expect(rendered.contains("\(otherHome)/Applications/AndromedaHUD.app/Contents/MacOS/AndromedaHUD"))
        #expect(!rendered.contains(LaunchAgentInstaller.studioHomeTemplate))
    }

    @Test
    func rewritesMcpHubOpsTemplate() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = repoRoot().appendingPathComponent("ops/com.andromeda.mcp-hub.plist")
        let destination = dir.appendingPathComponent("com.andromeda.mcp-hub.plist")
        let otherHome = isolatedHome(in: dir)
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(
                label: "com.andromeda.mcp-hub",
                home: otherHome,
                uid: 501
            )
        )
        #expect(report.rewritten)
        let rendered = try String(contentsOf: destination, encoding: .utf8)
        #expect(rendered.contains("\(otherHome)/.local/bin/andromeda"))
        #expect(!rendered.contains(LaunchAgentInstaller.studioHomeTemplate))
    }
}
