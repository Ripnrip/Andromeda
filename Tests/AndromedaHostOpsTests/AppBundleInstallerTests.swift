import AndromedaHostOps
import Foundation
import Testing

@testable import AndromedaHostOps

/// AppBundleInstaller transaction tests.
///
/// Two layers:
/// 1. **Live codesign round-trip** — skipped unless `/usr/bin/codesign` is present.
/// 2. **Mocked shell** — sign/verify failures must leave the destination
///    untouched and remove the staging tree.
@Suite(.serialized)
struct AppBundleInstallerTests {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-bundle-installer-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeSource(_ dir: URL) -> URL {
        let src = dir.appendingPathComponent("source-bin")
        try! FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: src)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: src.path)
        return src
    }

    private func spec(build: String = "202609201506") -> AppBundleInstaller.Spec {
        AppBundleInstaller.Spec(
            productName: "FixtureHome",
            bundleIdentifier: "com.andromeda.fixture.home",
            displayName: "Fixture Home",
            shortVersion: "0.3",
            buildVersion: build,
            lsuiElement: false
        )
    }

    private func leftoverInstallTrees(in dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") }
    }

    private func dummyUnsignedBundle(at url: URL, marker: String) throws {
        let macos = url.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try marker.data(using: .utf8)!.write(to: macos.appendingPathComponent("OLD"))
    }

    // MARK: - Live round-trip

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/codesign")))
    func liveInstallPublishesStrictSignedBundle() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = makeSource(dir)
        let destination = dir.appendingPathComponent("FixtureHome.app")
        try dummyUnsignedBundle(at: destination, marker: "old-bundle")
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/MacOS/OLD").path))

        let installer = AppBundleInstaller()
        let report = try await installer.install(source: source, destination: destination, spec: spec())

        #expect(report.replacedExisting)
        #expect(report.bundleIdentifier == "com.andromeda.fixture.home")
        #expect(report.productName == "FixtureHome")

        let verify = try await LiveShell().execute([
            "codesign", "--verify", "--deep", "--strict", destination.path,
        ])
        #expect(verify.success)

        let inner = destination.appendingPathComponent("Contents/MacOS/FixtureHome")
        #expect(FileManager.default.isExecutableFile(atPath: inner.path))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/MacOS/OLD").path))

        let plistURL = destination.appendingPathComponent("Contents/Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        #expect(plist["CFBundleIdentifier"] as? String == "com.andromeda.fixture.home")
        #expect(plist["CFBundleExecutable"] as? String == "FixtureHome")
        #expect(plist["LSUIElement"] as? Bool == false)

        #expect(try leftoverInstallTrees(in: dir).isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/codesign")))
    func liveFreshInstallWhenDestinationMissing() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = makeSource(dir)
        let destination = dir.appendingPathComponent("FreshHome.app")
        #expect(!FileManager.default.fileExists(atPath: destination.path))

        let installer = AppBundleInstaller()
        let report = try await installer.install(source: source, destination: destination, spec: spec())
        #expect(!report.replacedExisting)

        let verify = try await LiveShell().execute([
            "codesign", "--verify", "--deep", "--strict", destination.path,
        ])
        #expect(verify.success)
        #expect(try leftoverInstallTrees(in: dir).isEmpty)
    }

    // MARK: - Failure modes (mocked codesign)

    private actor MockShell: ShellExecuting {
        let failOn: String

        init(failOn: String) {
            self.failOn = failOn
        }

        func execute(_ arguments: [String]) async throws -> ShellResult {
            let joined = arguments.joined(separator: " ")
            if joined.contains(failOn) {
                return ShellResult(success: false, output: "mocked failure for: \(joined)")
            }
            return ShellResult(success: true, output: "")
        }
    }

    @Test
    func signingFailureLeavesDestinationUntouchedAndCleansStaging() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = makeSource(dir)
        let destination = dir.appendingPathComponent("FixtureHome.app")
        try dummyUnsignedBundle(at: destination, marker: "keep-me")
        let oldMarker = try String(
            contentsOf: destination.appendingPathComponent("Contents/MacOS/OLD"),
            encoding: .utf8
        )

        let installer = AppBundleInstaller(shell: MockShell(failOn: "--sign"))
        await #expect(throws: AppBundleInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination, spec: spec())
        }

        let newMarker = try String(
            contentsOf: destination.appendingPathComponent("Contents/MacOS/OLD"),
            encoding: .utf8
        )
        #expect(newMarker == oldMarker)
        #expect(newMarker == "keep-me")
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/MacOS/FixtureHome").path))
        #expect(try leftoverInstallTrees(in: dir).isEmpty)
    }

    @Test
    func verificationFailureLeavesDestinationUntouchedAndCleansStaging() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = makeSource(dir)
        let destination = dir.appendingPathComponent("FixtureHome.app")
        try dummyUnsignedBundle(at: destination, marker: "keep-me")

        let installer = AppBundleInstaller(shell: MockShell(failOn: "--verify"))
        await #expect(throws: AppBundleInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination, spec: spec())
        }

        let marker = try String(
            contentsOf: destination.appendingPathComponent("Contents/MacOS/OLD"),
            encoding: .utf8
        )
        #expect(marker == "keep-me")
        #expect(try leftoverInstallTrees(in: dir).isEmpty)
    }

    @Test
    func rejectsNonAppDestination() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = makeSource(dir)
        let destination = dir.appendingPathComponent("not-a-bundle")
        let installer = AppBundleInstaller(shell: MockShell(failOn: "never"))
        await #expect(throws: AppBundleInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination, spec: spec())
        }
    }
}
