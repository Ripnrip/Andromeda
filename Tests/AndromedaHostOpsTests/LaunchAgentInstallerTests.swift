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


    @discardableResult
    private func plantFixtureProgram(home: String) -> URL {
        let url = URL(fileURLWithPath: home)
            .appendingPathComponent("Applications/Fixture.app/Contents/MacOS/Fixture")
        try! FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// Bare Mach-O at `home/bin/Fixture` (not inside a `.app` — codesign
    /// would otherwise walk up the bundle). Linker-signed by default;
    /// `--remove-signature` then optional ad-hoc re-sign (HAB-677).
    @discardableResult
    private func plantBareMachO(home: String, signed: Bool) async throws -> URL {
        let url = URL(fileURLWithPath: home).appendingPathComponent("bin/Fixture")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let mainC = url.deletingLastPathComponent().appendingPathComponent("main.c")
        try "int main(void) { return 0; }\n".write(to: mainC, atomically: true, encoding: .utf8)
        let clang = LiveShell()
        let build = try await clang.execute(["/usr/bin/clang", "-o", url.path, mainC.path])
        guard build.success else {
            throw LaunchAgentInstaller.InstallError.programMissing("clang: \(build.output)")
        }
        try FileManager.default.removeItem(at: mainC)
        _ = try await clang.execute(["/usr/bin/codesign", "--remove-signature", url.path])
        if signed {
            let sign = try await clang.execute([
                "/usr/bin/codesign", "--force", "--sign", "-", url.path,
            ])
            guard sign.success else {
                throw LaunchAgentInstaller.InstallError.programNotSigned("sign: \(sign.output)")
            }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }


    /// Signed Mach-O at `home/bin/Fixture` linked to adjacent
    /// `@loader_path` dylibs (HAB-678). Companion/nested files can be
    /// deleted after link so otool still lists them as missing.
    @discardableResult
    private func plantSignedMachOWithLoaderPathDylibs(
        home: String,
        keepCompanion: Bool,
        keepNested: Bool
    ) async throws -> URL {
        let binDir = URL(fileURLWithPath: home).appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let clang = LiveShell()

        let nestedC = binDir.appendingPathComponent("nested.c")
        try "void nested(void) {}\n".write(to: nestedC, atomically: true, encoding: .utf8)
        let nested = binDir.appendingPathComponent("libnested.dylib")
        let nestedBuild = try await clang.execute([
            "/usr/bin/clang", "-dynamiclib",
            "-install_name", "@loader_path/libnested.dylib",
            "-o", nested.path, nestedC.path,
        ])
        guard nestedBuild.success else {
            throw LaunchAgentInstaller.InstallError.programMissing("clang nested: \(nestedBuild.output)")
        }

        let companionC = binDir.appendingPathComponent("companion.c")
        try "void nested(void); void dummy(void) { nested(); }\n".write(
            to: companionC, atomically: true, encoding: .utf8
        )
        let companion = binDir.appendingPathComponent("libcompanion.dylib")
        let companionBuild = try await clang.execute([
            "/usr/bin/clang", "-dynamiclib",
            "-install_name", "@loader_path/libcompanion.dylib",
            "-o", companion.path, companionC.path, nested.path,
            "-Wl,-rpath,@loader_path",
        ])
        guard companionBuild.success else {
            throw LaunchAgentInstaller.InstallError.programMissing("clang companion: \(companionBuild.output)")
        }

        let mainC = binDir.appendingPathComponent("main.c")
        try "int main(void) { return 0; }\n".write(to: mainC, atomically: true, encoding: .utf8)
        let program = binDir.appendingPathComponent("Fixture")
        let link = try await clang.execute([
            "/usr/bin/clang", "-o", program.path, mainC.path, companion.path,
            "-Wl,-rpath,@loader_path",
        ])
        guard link.success else {
            throw LaunchAgentInstaller.InstallError.programMissing("clang fixture: \(link.output)")
        }

        for url in [nested, companion, program] {
            _ = try await clang.execute(["/usr/bin/codesign", "--remove-signature", url.path])
            let sign = try await clang.execute([
                "/usr/bin/codesign", "--force", "--sign", "-", url.path,
            ])
            guard sign.success else {
                throw LaunchAgentInstaller.InstallError.programNotSigned("sign \(url.lastPathComponent): \(sign.output)")
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        try? FileManager.default.removeItem(at: nestedC)
        try? FileManager.default.removeItem(at: companionC)
        try? FileManager.default.removeItem(at: mainC)
        if !keepNested {
            try FileManager.default.removeItem(at: nested)
        }
        if !keepCompanion {
            try FileManager.default.removeItem(at: companion)
        }
        return program
    }

    /// Studio-template plist whose Program is the planted bare Mach-O.
    /// Other paths still contain the studio HOME so rewrite stays honest.
    private func machOPlist(program: String) -> String {
        let studio = LaunchAgentInstaller.studioHomeTemplate
        return fixturePlist().replacingOccurrences(
            of: "\(studio)/Applications/Fixture.app/Contents/MacOS/Fixture",
            with: program
        )
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
        _ = plantFixtureProgram(home: home)
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
        _ = plantFixtureProgram(home: home)
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
        _ = plantFixtureProgram(home: home)
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
        _ = plantFixtureProgram(home: home)
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
        _ = plantFixtureProgram(home: home)
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
        _ = plantFixtureProgram(home: home)
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


    @Test
    func bootstrapMissingProgramFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = writePlist(dir, name: "src.plist", body: fixturePlist())
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        // Intentionally do not plant Program.
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapMissingProgramLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = writePlist(dir, name: "src.plist", body: fixturePlist())
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapNonExecutableProgramFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = writePlist(dir, name: "src.plist", body: fixturePlist())
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = URL(fileURLWithPath: home)
            .appendingPathComponent("Applications/Fixture.app/Contents/MacOS/Fixture")
        try FileManager.default.createDirectory(
            at: program.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: program.path, contents: Data("not-exec".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: program.path)
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func rewriteOnlyDoesNotRequireProgram() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = writePlist(dir, name: "src.plist", body: fixturePlist())
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
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

    // MARK: - HAB-677 unsigned Mach-O Program

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func bootstrapUnsignedMachOFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let program = try await plantBareMachO(home: home, signed: false)
        #expect(LaunchAgentInstaller.isMachO(at: program.path))
        let source = writePlist(dir, name: "src.plist", body: machOPlist(program: program.path))
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func bootstrapUnsignedMachOLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = try await plantBareMachO(home: home, signed: false)
        let source = writePlist(dir, name: "src.plist", body: machOPlist(program: program.path))
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func bootstrapSignedMachOProceedsToLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = try await plantBareMachO(home: home, signed: true)
        #expect(LaunchAgentInstaller.isMachO(at: program.path))
        let source = writePlist(dir, name: "src.plist", body: machOPlist(program: program.path))
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
        )
        #expect(report.bootstrapped)
        #expect(!report.kickstarted)
        let calls = await shell.recorded()
        #expect(!calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func rewriteOnlyDoesNotRequireMachOSignature() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = try await plantBareMachO(home: home, signed: false)
        let source = writePlist(dir, name: "src.plist", body: machOPlist(program: program.path))
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    // MARK: - HAB-678 missing Program rpath dylibs

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func bootstrapMachOMissingCompanionFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let program = try await plantSignedMachOWithLoaderPathDylibs(
            home: home, keepCompanion: false, keepNested: false
        )
        #expect(LaunchAgentInstaller.isMachO(at: program.path))
        let source = writePlist(dir, name: "src.plist", body: machOPlist(program: program.path))
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func bootstrapMachOMissingCompanionLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = try await plantSignedMachOWithLoaderPathDylibs(
            home: home, keepCompanion: false, keepNested: false
        )
        let source = writePlist(dir, name: "src.plist", body: machOPlist(program: program.path))
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func bootstrapMachOWithCompanionProceedsToLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = try await plantSignedMachOWithLoaderPathDylibs(
            home: home, keepCompanion: true, keepNested: true
        )
        let source = writePlist(dir, name: "src.plist", body: machOPlist(program: program.path))
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
        )
        #expect(report.bootstrapped)
        #expect(!report.kickstarted)
        let calls = await shell.recorded()
        #expect(!calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func bootstrapMachOMissingNestedCompanionFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let program = try await plantSignedMachOWithLoaderPathDylibs(
            home: home, keepCompanion: true, keepNested: false
        )
        let source = writePlist(dir, name: "src.plist", body: machOPlist(program: program.path))
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        let restoredInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        #expect(restoredInode == oldInode)
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func rewriteOnlyDoesNotRequireCompanionDylibs() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = try await plantSignedMachOWithLoaderPathDylibs(
            home: home, keepCompanion: false, keepNested: false
        )
        let source = writePlist(dir, name: "src.plist", body: machOPlist(program: program.path))
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    // MARK: - HAB-680 unsigned companion dylibs

    /// Strip ad-hoc signature from a planted companion (HAB-680).
    private func stripSignature(at url: URL) async throws {
        let clang = LiveShell()
        _ = try await clang.execute(["/usr/bin/codesign", "--remove-signature", url.path])
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func bootstrapMachOUnsignedCompanionFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let program = try await plantSignedMachOWithLoaderPathDylibs(
            home: home, keepCompanion: true, keepNested: true
        )
        let companion = program.deletingLastPathComponent().appendingPathComponent("libcompanion.dylib")
        try await stripSignature(at: companion)
        let source = writePlist(dir, name: "src.plist", body: machOPlist(program: program.path))
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func bootstrapMachOUnsignedCompanionLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = try await plantSignedMachOWithLoaderPathDylibs(
            home: home, keepCompanion: true, keepNested: true
        )
        let companion = program.deletingLastPathComponent().appendingPathComponent("libcompanion.dylib")
        try await stripSignature(at: companion)
        let source = writePlist(dir, name: "src.plist", body: machOPlist(program: program.path))
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func bootstrapMachOUnsignedNestedCompanionFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let program = try await plantSignedMachOWithLoaderPathDylibs(
            home: home, keepCompanion: true, keepNested: true
        )
        let nested = program.deletingLastPathComponent().appendingPathComponent("libnested.dylib")
        try await stripSignature(at: nested)
        let source = writePlist(dir, name: "src.plist", body: machOPlist(program: program.path))
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        let restoredInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        #expect(restoredInode == oldInode)
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func rewriteOnlyDoesNotRequireCompanionSignatures() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = try await plantSignedMachOWithLoaderPathDylibs(
            home: home, keepCompanion: true, keepNested: true
        )
        let companion = program.deletingLastPathComponent().appendingPathComponent("libcompanion.dylib")
        try await stripSignature(at: companion)
        let source = writePlist(dir, name: "src.plist", body: machOPlist(program: program.path))
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    // MARK: - HAB-681 missing WorkingDirectory

    /// Studio-template plist with an explicit Program + WorkingDirectory.
    /// `workingDirectory` nil omits the key (launchd default `/`).
    private func workingDirectoryPlist(
        program: String,
        workingDirectory: String?,
        home: String = LaunchAgentInstaller.studioHomeTemplate
    ) -> String {
        let cwd: String
        if let workingDirectory {
            cwd = """
                <key>WorkingDirectory</key>
                <string>\(workingDirectory)</string>
            """
        } else {
            cwd = ""
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.andromeda.fixture.agent</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(program)</string>
            </array>
            \(cwd)
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

    @Test
    func bootstrapMissingWorkingDirectoryFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let missing = URL(fileURLWithPath: home).appendingPathComponent("missing-cwd").path
        let source = writePlist(
            dir,
            name: "src.plist",
            body: workingDirectoryPlist(program: program.path, workingDirectory: missing)
        )
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func bootstrapMissingWorkingDirectoryLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let missing = URL(fileURLWithPath: home).appendingPathComponent("missing-cwd").path
        let source = writePlist(
            dir,
            name: "src.plist",
            body: workingDirectoryPlist(program: program.path, workingDirectory: missing)
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapWorkingDirectoryIsFileFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let fileCwd = URL(fileURLWithPath: home).appendingPathComponent("cwd-file")
        FileManager.default.createFile(atPath: fileCwd.path, contents: Data("not-a-dir".utf8))
        let source = writePlist(
            dir,
            name: "src.plist",
            body: workingDirectoryPlist(program: program.path, workingDirectory: fileCwd.path)
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapWithoutWorkingDirectoryKeyProceedsToLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: workingDirectoryPlist(program: program.path, workingDirectory: nil)
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
        )
        #expect(report.bootstrapped)
        let calls = await shell.recorded()
        #expect(!calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func rewriteOnlyDoesNotRequireWorkingDirectory() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let missing = URL(fileURLWithPath: home).appendingPathComponent("missing-cwd").path
        let source = writePlist(
            dir,
            name: "src.plist",
            body: workingDirectoryPlist(
                program: "\(LaunchAgentInstaller.studioHomeTemplate)/Applications/Fixture.app/Contents/MacOS/Fixture",
                workingDirectory: missing
            )
        )
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    // MARK: - HAB-682 relative StandardOutPath / StandardErrorPath

    /// Studio-template plist with optional log paths. Nil omits the key.
    private func logPathPlist(
        program: String,
        standardOutPath: String?,
        standardErrorPath: String?,
        standardInPath: String? = nil,
        home: String = LaunchAgentInstaller.studioHomeTemplate
    ) -> String {
        func key(_ name: String, _ value: String?) -> String {
            guard let value else { return "" }
            return """
                <key>\(name)</key>
                <string>\(value)</string>
            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.andromeda.fixture.agent</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(program)</string>
            </array>
            <key>WorkingDirectory</key>
            <string>\(home)</string>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            \(key("StandardInPath", standardInPath))
            \(key("StandardOutPath", standardOutPath))
            \(key("StandardErrorPath", standardErrorPath))
            <key>EnvironmentVariables</key>
            <dict>
                <key>HOME</key>
                <string>\(home)</string>
            </dict>
        </dict>
        </plist>
        """
    }

    @Test
    func bootstrapRelativeStandardOutPathFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: logPathPlist(
                program: program.path,
                standardOutPath: "relative/out.log",
                standardErrorPath: "\(LaunchAgentInstaller.studioHomeTemplate)/.multibrain/logs/fixture.launchd.log"
            )
        )
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("relative").path))
    }

    @Test
    func bootstrapRelativeStandardErrorPathLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: logPathPlist(
                program: program.path,
                standardOutPath: "\(LaunchAgentInstaller.studioHomeTemplate)/.multibrain/logs/fixture.launchd.log",
                standardErrorPath: "relative/err.log"
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("relative").path))
    }

    @Test
    func bootstrapLogPathIsDirectoryFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let logDir = URL(fileURLWithPath: home).appendingPathComponent("logs-dir")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: logPathPlist(
                program: program.path,
                standardOutPath: logDir.path,
                standardErrorPath: logDir.path
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapWithoutLogKeysProceedsToLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: logPathPlist(
                program: program.path,
                standardOutPath: nil,
                standardErrorPath: nil
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
        )
        #expect(report.bootstrapped)
        let calls = await shell.recorded()
        #expect(!calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func rewriteOnlyDoesNotRequireLogPaths() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: logPathPlist(
                program: "\(LaunchAgentInstaller.studioHomeTemplate)/Applications/Fixture.app/Contents/MacOS/Fixture",
                standardOutPath: "relative/out.log",
                standardErrorPath: "relative/err.log"
            )
        )
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("relative").path))
    }

    // MARK: - HAB-683 EnvironmentVariables.HOME

    /// Studio-template plist with optional EnvironmentVariables.HOME.
    /// Nil omits the EnvironmentVariables dict entirely.
    private func environmentHomePlist(
        program: String,
        environmentHome: String?,
        home: String = LaunchAgentInstaller.studioHomeTemplate
    ) -> String {
        let env: String
        if let environmentHome {
            env = """
                <key>EnvironmentVariables</key>
                <dict>
                    <key>HOME</key>
                    <string>\(environmentHome)</string>
                </dict>
            """
        } else {
            env = ""
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.andromeda.fixture.agent</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(program)</string>
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
            \(env)
        </dict>
        </plist>
        """
    }

    @Test
    func bootstrapRelativeEnvironmentHomeFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentHomePlist(
                program: program.path,
                environmentHome: "relative-home"
            )
        )
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func bootstrapMissingEnvironmentHomeLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let missing = URL(fileURLWithPath: home).appendingPathComponent("missing-env-home").path
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentHomePlist(program: program.path, environmentHome: missing)
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapEnvironmentHomeIsFileFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let fileHome = URL(fileURLWithPath: home).appendingPathComponent("home-file")
        FileManager.default.createFile(atPath: fileHome.path, contents: Data("not-a-dir".utf8))
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentHomePlist(program: program.path, environmentHome: fileHome.path)
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapWithoutEnvironmentHomeKeyProceedsToLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentHomePlist(program: program.path, environmentHome: nil)
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
        )
        #expect(report.bootstrapped)
        let calls = await shell.recorded()
        #expect(!calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func rewriteOnlyDoesNotRequireEnvironmentHome() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentHomePlist(
                program: "\(LaunchAgentInstaller.studioHomeTemplate)/Applications/Fixture.app/Contents/MacOS/Fixture",
                environmentHome: "relative-home"
            )
        )
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    // MARK: - HAB-684 EnvironmentVariables.PATH

    /// Studio-template plist with optional EnvironmentVariables.PATH.
    /// Nil omits the EnvironmentVariables dict entirely.
    private func environmentPathPlist(
        program: String,
        path: String?,
        home: String = LaunchAgentInstaller.studioHomeTemplate
    ) -> String {
        let env: String
        if let path {
            env = """
                <key>EnvironmentVariables</key>
                <dict>
                    <key>PATH</key>
                    <string>\(path)</string>
                </dict>
            """
        } else {
            env = ""
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.andromeda.fixture.agent</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(program)</string>
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
            \(env)
        </dict>
        </plist>
        """
    }

    @Test
    func bootstrapRelativeEnvironmentPathFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPathPlist(
                program: program.path,
                path: "relative/bin:/usr/bin"
            )
        )
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func bootstrapEmptyEnvironmentPathComponentLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPathPlist(program: program.path, path: "/usr/bin:")
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapDollarHomeEnvironmentPathFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPathPlist(
                program: program.path,
                path: "$HOME/.local/bin:/usr/bin"
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapWithoutEnvironmentPathKeyProceedsToLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPathPlist(program: program.path, path: nil)
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
        )
        #expect(report.bootstrapped)
        let calls = await shell.recorded()
        #expect(!calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func rewriteOnlyDoesNotRequireEnvironmentPath() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPathPlist(
                program: "\(LaunchAgentInstaller.studioHomeTemplate)/Applications/Fixture.app/Contents/MacOS/Fixture",
                path: "relative/bin:/usr/bin"
            )
        )
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    // MARK: - HAB-686 /usr/bin/open

    /// Studio-template plist whose Program is LaunchServices `open`.
    private func openProgramPlist(
        program: String = "/usr/bin/open",
        extraArguments: [String] = ["-a", "\(LaunchAgentInstaller.studioHomeTemplate)/Applications/AndromedaHUD.app"]
    ) -> String {
        let extras = extraArguments.map { "                <string>\($0)</string>" }.joined(separator: "\n")
        let extraBlock = extras.isEmpty ? "" : "\n\(extras)"
        let home = LaunchAgentInstaller.studioHomeTemplate
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.andromeda.fixture.agent</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(program)</string>\(extraBlock)
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

    @Test
    func bootstrapOpenProgramFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let source = writePlist(dir, name: "src.plist", body: openProgramPlist())
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func bootstrapOpenProgramLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(dir, name: "src.plist", body: openProgramPlist())
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapOpenDotSlashPathFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: openProgramPlist(program: "/usr/bin/./open")
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func rewriteOnlyDoesNotRejectOpen() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(dir, name: "src.plist", body: openProgramPlist())
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        let rendered = try String(contentsOf: destination, encoding: .utf8)
        #expect(rendered.contains("/usr/bin/open"))
        #expect(!rendered.contains(LaunchAgentInstaller.studioHomeTemplate))
    }



    // MARK: - HAB-687 /usr/bin/osascript

    /// Studio-template plist whose Program is `/usr/bin/osascript`.
    private func osascriptProgramPlist(
        program: String = "/usr/bin/osascript",
        extraArguments: [String] = ["-e", "return 1"]
    ) -> String {
        let extras = extraArguments.map { "                <string>\($0)</string>" }.joined(separator: "\n")
        let extraBlock = extras.isEmpty ? "" : "\n\(extras)"
        let home = LaunchAgentInstaller.studioHomeTemplate
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.andromeda.fixture.agent</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(program)</string>\(extraBlock)
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

    @Test
    func bootstrapOsascriptProgramFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let source = writePlist(dir, name: "src.plist", body: osascriptProgramPlist())
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func bootstrapOsascriptProgramLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(dir, name: "src.plist", body: osascriptProgramPlist())
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapOsascriptDotSlashPathFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: osascriptProgramPlist(program: "/usr/bin/./osascript")
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func rewriteOnlyDoesNotRejectOsascript() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(dir, name: "src.plist", body: osascriptProgramPlist())
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        let rendered = try String(contentsOf: destination, encoding: .utf8)
        #expect(rendered.contains("/usr/bin/osascript"))
        #expect(!rendered.contains(LaunchAgentInstaller.studioHomeTemplate))
    }

    // MARK: - HAB-688 wrapped open/osascript argv

    @Test
    func bootstrapArchWrappingOpenFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: openProgramPlist(
                program: "/usr/bin/arch",
                extraArguments: [
                    "-arm64",
                    "/usr/bin/open",
                    "-a",
                    "\(LaunchAgentInstaller.studioHomeTemplate)/Applications/AndromedaHUD.app",
                ]
            )
        )
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func bootstrapEnvWrappingOsascriptLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: osascriptProgramPlist(
                program: "/usr/bin/env",
                extraArguments: ["/usr/bin/osascript", "-e", "return 1"]
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapArchWrappingDotSlashOpenFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: openProgramPlist(
                program: "/usr/bin/arch",
                extraArguments: [
                    "-arm64",
                    "/usr/bin/./open",
                    "-a",
                    "\(LaunchAgentInstaller.studioHomeTemplate)/Applications/AndromedaHUD.app",
                ]
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func rewriteOnlyDoesNotRejectArchWrappingOpen() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: openProgramPlist(
                program: "/usr/bin/arch",
                extraArguments: [
                    "-arm64",
                    "/usr/bin/open",
                    "-a",
                    "\(LaunchAgentInstaller.studioHomeTemplate)/Applications/AndromedaHUD.app",
                ]
            )
        )
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        let rendered = try String(contentsOf: destination, encoding: .utf8)
        #expect(rendered.contains("/usr/bin/arch"))
        #expect(rendered.contains("/usr/bin/open"))
        #expect(!rendered.contains(LaunchAgentInstaller.studioHomeTemplate))
    }

    // MARK: - HAB-689 paid EnvironmentVariables API keys

    /// Studio-template plist with HOME/PATH plus optional extra env keys.
    private func environmentPaidKeyPlist(
        program: String,
        extraKeys: [String: String],
        home: String = LaunchAgentInstaller.studioHomeTemplate
    ) -> String {
        var extra = ""
        for key in extraKeys.keys.sorted() {
            let value = extraKeys[key]!
            extra += """
                    <key>\(key)</key>
                    <string>\(value)</string>

            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.andromeda.fixture.agent</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(program)</string>
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
                <key>PATH</key>
                <string>/usr/bin:/bin</string>
                \(extra)
            </dict>
        </dict>
        </plist>
        """
    }

    @Test
    func bootstrapOpenRouterKeyFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPaidKeyPlist(
                program: program.path,
                extraKeys: ["OPENROUTER_API_KEY": "sk-or-test"]
            )
        )
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func bootstrapAnthropicKeyLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPaidKeyPlist(
                program: program.path,
                extraKeys: ["ANTHROPIC_API_KEY": "sk-ant-test"]
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapGoogleApiKeyFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPaidKeyPlist(
                program: program.path,
                extraKeys: ["GOOGLE_API_KEY": "AIza-test"]
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapHomePathLangEnvironmentProceedsToLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPaidKeyPlist(
                program: program.path,
                extraKeys: ["LANG": "en_US.UTF-8"]
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
        )
        #expect(report.bootstrapped)
        let calls = await shell.recorded()
        #expect(!calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func rewriteOnlyDoesNotRejectOpenRouterKey() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPaidKeyPlist(
                program: "\(LaunchAgentInstaller.studioHomeTemplate)/Applications/Fixture.app/Contents/MacOS/Fixture",
                extraKeys: ["OPENROUTER_API_KEY": "sk-or-test"]
            )
        )
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        let rendered = try String(contentsOf: destination, encoding: .utf8)
        #expect(rendered.contains("OPENROUTER_API_KEY"))
        #expect(!rendered.contains(LaunchAgentInstaller.studioHomeTemplate))
    }


    // MARK: - HAB-690 DYLD_* EnvironmentVariables

    @Test
    func bootstrapDyldInsertLibrariesFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPaidKeyPlist(
                program: program.path,
                extraKeys: ["DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib"]
            )
        )
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func bootstrapDyldLibraryPathLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPaidKeyPlist(
                program: program.path,
                extraKeys: ["DYLD_LIBRARY_PATH": "/tmp"]
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapDyldFrameworkPathFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPaidKeyPlist(
                program: program.path,
                extraKeys: ["DYLD_FRAMEWORK_PATH": "/tmp"]
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapLowercaseDyldPrefixFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPaidKeyPlist(
                program: program.path,
                extraKeys: ["dyld_insert_libraries": "/tmp/evil.dylib"]
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func rewriteOnlyDoesNotRejectDyldInsertLibraries() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentPaidKeyPlist(
                program: "\(LaunchAgentInstaller.studioHomeTemplate)/Applications/Fixture.app/Contents/MacOS/Fixture",
                extraKeys: ["DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib"]
            )
        )
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        let rendered = try String(contentsOf: destination, encoding: .utf8)
        #expect(rendered.contains("DYLD_INSERT_LIBRARIES"))
        #expect(!rendered.contains(LaunchAgentInstaller.studioHomeTemplate))
    }

    // MARK: - HAB-692 StandardInPath

    @Test
    func bootstrapRelativeStandardInPathFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: logPathPlist(
                program: program.path,
                standardOutPath: "\(LaunchAgentInstaller.studioHomeTemplate)/.multibrain/logs/fixture.launchd.log",
                standardErrorPath: "\(LaunchAgentInstaller.studioHomeTemplate)/.multibrain/logs/fixture.launchd.log",
                standardInPath: "relative/stdin"
            )
        )
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func bootstrapMissingStandardInPathLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let missing = "\(LaunchAgentInstaller.studioHomeTemplate)/.multibrain/missing-stdin"
        let source = writePlist(
            dir,
            name: "src.plist",
            body: logPathPlist(
                program: program.path,
                standardOutPath: "\(LaunchAgentInstaller.studioHomeTemplate)/.multibrain/logs/fixture.launchd.log",
                standardErrorPath: "\(LaunchAgentInstaller.studioHomeTemplate)/.multibrain/logs/fixture.launchd.log",
                standardInPath: missing
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: home).appendingPathComponent(".multibrain/missing-stdin").path))
    }

    @Test
    func bootstrapStandardInPathIsDirectoryFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let stdinDir = URL(fileURLWithPath: home).appendingPathComponent("stdin-dir")
        try FileManager.default.createDirectory(at: stdinDir, withIntermediateDirectories: true)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: logPathPlist(
                program: program.path,
                standardOutPath: "\(LaunchAgentInstaller.studioHomeTemplate)/.multibrain/logs/fixture.launchd.log",
                standardErrorPath: "\(LaunchAgentInstaller.studioHomeTemplate)/.multibrain/logs/fixture.launchd.log",
                standardInPath: stdinDir.path
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapValidStandardInPathProceedsToLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let stdin = URL(fileURLWithPath: home).appendingPathComponent(".multibrain/stdin")
        try FileManager.default.createDirectory(at: stdin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: stdin)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: logPathPlist(
                program: program.path,
                standardOutPath: "\(LaunchAgentInstaller.studioHomeTemplate)/.multibrain/logs/fixture.launchd.log",
                standardErrorPath: "\(LaunchAgentInstaller.studioHomeTemplate)/.multibrain/logs/fixture.launchd.log",
                standardInPath: stdin.path
            )
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
        )
        #expect(report.bootstrapped)
        let calls = await shell.recorded()
        #expect(!calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func rewriteOnlyDoesNotRequireStandardInPath() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: logPathPlist(
                program: "\(LaunchAgentInstaller.studioHomeTemplate)/Applications/Fixture.app/Contents/MacOS/Fixture",
                standardOutPath: "\(LaunchAgentInstaller.studioHomeTemplate)/.multibrain/logs/fixture.launchd.log",
                standardErrorPath: "\(LaunchAgentInstaller.studioHomeTemplate)/.multibrain/logs/fixture.launchd.log",
                standardInPath: "relative/stdin"
            )
        )
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("relative").path))
    }

    // MARK: - HAB-693 RootDirectory

    /// Studio-template plist with optional RootDirectory. Nil omits the key.
    private func rootDirectoryPlist(
        program: String,
        rootDirectory: String?,
        home: String = LaunchAgentInstaller.studioHomeTemplate
    ) -> String {
        let root: String
        if let rootDirectory {
            root = """
                <key>RootDirectory</key>
                <string>\(rootDirectory)</string>
            """
        } else {
            root = ""
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.andromeda.fixture.agent</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(program)</string>
            </array>
            \(root)
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

    @Test
    func bootstrapRelativeRootDirectoryFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: rootDirectoryPlist(program: program.path, rootDirectory: "relative/chroot")
        )
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func bootstrapMissingRootDirectoryLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let missing = URL(fileURLWithPath: home).appendingPathComponent("missing-root").path
        let source = writePlist(
            dir,
            name: "src.plist",
            body: rootDirectoryPlist(program: program.path, rootDirectory: missing)
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapRootDirectoryIsFileFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let fileRoot = URL(fileURLWithPath: home).appendingPathComponent("root-file")
        FileManager.default.createFile(atPath: fileRoot.path, contents: Data("not-a-dir".utf8))
        let source = writePlist(
            dir,
            name: "src.plist",
            body: rootDirectoryPlist(program: program.path, rootDirectory: fileRoot.path)
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapWithoutRootDirectoryKeyProceedsToLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: rootDirectoryPlist(program: program.path, rootDirectory: nil)
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
        )
        #expect(report.bootstrapped)
        let calls = await shell.recorded()
        #expect(!calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func rewriteOnlyDoesNotRequireRootDirectory() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: rootDirectoryPlist(
                program: "\(LaunchAgentInstaller.studioHomeTemplate)/Applications/Fixture.app/Contents/MacOS/Fixture",
                rootDirectory: "relative/chroot"
            )
        )
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        let rendered = try String(contentsOf: destination, encoding: .utf8)
        #expect(rendered.contains("relative/chroot"))
        #expect(!rendered.contains(LaunchAgentInstaller.studioHomeTemplate))
    }

    // MARK: - HAB-695 EnvironmentVariables.TMPDIR

    /// Studio-template plist with optional EnvironmentVariables.TMPDIR.
    /// Nil omits the EnvironmentVariables dict entirely.
    private func environmentTmpdirPlist(
        program: String,
        environmentTmpdir: String?,
        home: String = LaunchAgentInstaller.studioHomeTemplate
    ) -> String {
        let env: String
        if let environmentTmpdir {
            env = """
                <key>EnvironmentVariables</key>
                <dict>
                    <key>TMPDIR</key>
                    <string>\(environmentTmpdir)</string>
                </dict>
            """
        } else {
            env = ""
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.andromeda.fixture.agent</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(program)</string>
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
            \(env)
        </dict>
        </plist>
        """
    }

    @Test
    func bootstrapRelativeEnvironmentTmpdirFailsClosedBeforeLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let previous = "keep-me\n"
        try previous.write(to: destination, atomically: true, encoding: .utf8)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentTmpdirPlist(
                program: program.path,
                environmentTmpdir: "relative/tmp"
            )
        )
        let shell = RecordingShell()
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
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func bootstrapMissingEnvironmentTmpdirLeavesFreshDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let missing = URL(fileURLWithPath: home).appendingPathComponent("missing-tmpdir").path
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentTmpdirPlist(program: program.path, environmentTmpdir: missing)
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapEnvironmentTmpdirIsFileFailsClosed() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("fresh.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let fileTmp = URL(fileURLWithPath: home).appendingPathComponent("tmpdir-file")
        FileManager.default.createFile(atPath: fileTmp.path, contents: Data("not-a-dir".utf8))
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentTmpdirPlist(program: program.path, environmentTmpdir: fileTmp.path)
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        await #expect(throws: LaunchAgentInstaller.InstallError.self) {
            _ = try await installer.install(
                source: source,
                destination: destination,
                spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let calls = await shell.recorded()
        #expect(calls.isEmpty)
    }

    @Test
    func bootstrapWithoutEnvironmentTmpdirKeyProceedsToLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentTmpdirPlist(program: program.path, environmentTmpdir: nil)
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
        )
        #expect(report.bootstrapped)
        let calls = await shell.recorded()
        #expect(!calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func bootstrapValidEnvironmentTmpdirProceedsToLaunchctl() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let program = plantFixtureProgram(home: home)
        let tmpdir = URL(fileURLWithPath: home).appendingPathComponent(".tmp")
        try FileManager.default.createDirectory(at: tmpdir, withIntermediateDirectories: true)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentTmpdirPlist(program: program.path, environmentTmpdir: tmpdir.path)
        )
        let shell = RecordingShell()
        let installer = LaunchAgentInstaller(shell: shell)
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: true)
        )
        #expect(report.bootstrapped)
        let calls = await shell.recorded()
        #expect(!calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func rewriteOnlyDoesNotRequireEnvironmentTmpdir() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.plist")
        let home = isolatedHome(in: dir)
        let source = writePlist(
            dir,
            name: "src.plist",
            body: environmentTmpdirPlist(
                program: "\(LaunchAgentInstaller.studioHomeTemplate)/Applications/Fixture.app/Contents/MacOS/Fixture",
                environmentTmpdir: "relative/tmp"
            )
        )
        let installer = LaunchAgentInstaller(shell: RecordingShell())
        let report = try await installer.install(
            source: source,
            destination: destination,
            spec: LaunchAgentInstaller.Spec(home: home, uid: 501, bootstrap: false)
        )
        #expect(report.rewritten)
        #expect(!report.bootstrapped)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        let rendered = try String(contentsOf: destination, encoding: .utf8)
        #expect(rendered.contains("relative/tmp"))
        #expect(!rendered.contains(LaunchAgentInstaller.studioHomeTemplate))
    }

}
