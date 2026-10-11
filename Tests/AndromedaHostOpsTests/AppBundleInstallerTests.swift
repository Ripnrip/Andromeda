
@testable import AndromedaHostOps
import Foundation
import Testing

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
            .filter {
                $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-")
            }
    }

    private func bundleInode(at url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.systemFileNumber] as! Int
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
        let plist = try #require(PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any])
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

    private actor PostPublishFailingShell: ShellExecuting {
        let destPath: String
        let live = LiveShell()

        init(destPath: String) {
            self.destPath = destPath
        }

        func execute(_ arguments: [String]) async throws -> ShellResult {
            if arguments.contains("--verify"), arguments.last == destPath {
                return ShellResult(success: false, output: "mocked post-publish verify failure")
            }
            return try await live.execute(arguments)
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/codesign")))
    func postPublishVerifyFailureRestoresParkedBundle() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = makeSource(dir)
        let destination = dir.appendingPathComponent("FixtureHome.app")
        try dummyUnsignedBundle(at: destination, marker: "keep-me")
        let oldInode = try bundleInode(at: destination)
        let oldMarkerPath = destination.appendingPathComponent("Contents/MacOS/OLD")

        let installer = AppBundleInstaller(shell: PostPublishFailingShell(destPath: destination.path))
        await #expect(throws: AppBundleInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination, spec: spec())
        }

        #expect(FileManager.default.fileExists(atPath: oldMarkerPath.path))
        let marker = try String(contentsOf: oldMarkerPath, encoding: .utf8)
        #expect(marker == "keep-me")
        let restoredInode = try bundleInode(at: destination)
        #expect(restoredInode == oldInode)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/MacOS/FixtureHome").path))
        #expect(try leftoverInstallTrees(in: dir).isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/codesign")))
    func postPublishVerifyFailureOnFreshInstallLeavesDestAbsent() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = makeSource(dir)
        let destination = dir.appendingPathComponent("FreshHome.app")
        #expect(!FileManager.default.fileExists(atPath: destination.path))

        let installer = AppBundleInstaller(shell: PostPublishFailingShell(destPath: destination.path))
        await #expect(throws: AppBundleInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination, spec: spec())
        }

        #expect(!FileManager.default.fileExists(atPath: destination.path))
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

    // MARK: - Adjacent rpath dylibs (HAB-671)

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func missingRequiredLoaderPathDylibFailsClosedAndLeavesDestination() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dummyC = dir.appendingPathComponent("dummy.c")
        try "void dummy(void) {}\n".write(to: dummyC, atomically: true, encoding: .utf8)
        let dylib = dir.appendingPathComponent("libmissing.dylib")
        let clang = LiveShell()
        let libBuild = try await clang.execute([
            "/usr/bin/clang", "-dynamiclib",
            "-install_name", "@loader_path/libmissing.dylib",
            "-o", dylib.path, dummyC.path,
        ])
        #expect(libBuild.success)

        let mainC = dir.appendingPathComponent("main.c")
        try "int main(void) { return 0; }\n".write(to: mainC, atomically: true, encoding: .utf8)
        let source = dir.appendingPathComponent("victim")
        let link = try await clang.execute([
            "/usr/bin/clang", "-o", source.path, mainC.path, dylib.path,
            "-Wl,-rpath,@loader_path",
        ])
        #expect(link.success)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        try FileManager.default.removeItem(at: dylib)

        let destination = dir.appendingPathComponent("FixtureHome.app")
        try dummyUnsignedBundle(at: destination, marker: "keep-me")
        let oldInode = try bundleInode(at: destination)

        let installer = AppBundleInstaller()
        await #expect(throws: AppBundleInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination, spec: spec())
        }

        let restoredInode = try bundleInode(at: destination)
        #expect(restoredInode == oldInode)
        let marker = try String(
            contentsOf: destination.appendingPathComponent("Contents/MacOS/OLD"),
            encoding: .utf8
        )
        #expect(marker == "keep-me")
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/MacOS/FixtureHome").path))
        #expect(try leftoverInstallTrees(in: dir).isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang") && FileManager.default.fileExists(atPath: "/usr/bin/codesign")))
    func adjacentLoaderPathDylibIsCopiedIntoMacOSAndDeepSigned() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let dummyC = sourceDir.appendingPathComponent("dummy.c")
        try "void dummy(void) {}\n".write(to: dummyC, atomically: true, encoding: .utf8)
        let dylib = sourceDir.appendingPathComponent("libcompanion.dylib")
        let clang = LiveShell()
        let libBuild = try await clang.execute([
            "/usr/bin/clang", "-dynamiclib",
            "-install_name", "@loader_path/libcompanion.dylib",
            "-o", dylib.path, dummyC.path,
        ])
        #expect(libBuild.success)

        let mainC = sourceDir.appendingPathComponent("main.c")
        try "int main(void) { return 0; }\n".write(to: mainC, atomically: true, encoding: .utf8)
        let source = sourceDir.appendingPathComponent("victim")
        let link = try await clang.execute([
            "/usr/bin/clang", "-o", source.path, mainC.path, dylib.path,
            "-Wl,-rpath,@loader_path",
        ])
        #expect(link.success)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)

        let destination = root.appendingPathComponent("FixtureHome.app")
        try dummyUnsignedBundle(at: destination, marker: "old-bundle")

        let installer = AppBundleInstaller()
        let report = try await installer.install(source: source, destination: destination, spec: spec())
        #expect(report.companionDylibs == ["libcompanion.dylib"])

        let publishedDylib = destination.appendingPathComponent("Contents/MacOS/libcompanion.dylib")
        #expect(FileManager.default.fileExists(atPath: publishedDylib.path))
        let verify = try await LiveShell().execute([
            "codesign", "--verify", "--deep", "--strict", destination.path,
        ])
        #expect(verify.success)
        let dylibVerify = try await LiveShell().execute([
            "codesign", "--verify", "--strict", publishedDylib.path,
        ])
        #expect(dylibVerify.success)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/MacOS/OLD").path))
        #expect(try leftoverInstallTrees(in: root).isEmpty)
    }

    /// HAB-673: dest `--deep --strict` succeeding is not enough — a failed
    /// companion dest verify must restore the parked bundle.
    private actor PostPublishCompanionFailingShell: ShellExecuting {
        let companionPath: String
        let live = LiveShell()

        init(companionPath: String) {
            self.companionPath = companionPath
        }

        func execute(_ arguments: [String]) async throws -> ShellResult {
            if arguments.contains("--verify"), arguments.last == companionPath {
                return ShellResult(success: false, output: "mocked post-publish companion verify failure")
            }
            return try await live.execute(arguments)
        }
    }

    private func makeLoaderPathFixture(in sourceDir: URL) async throws -> (source: URL, dylib: URL) {
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let dummyC = sourceDir.appendingPathComponent("dummy.c")
        try "void dummy(void) {}\n".write(to: dummyC, atomically: true, encoding: .utf8)
        let dylib = sourceDir.appendingPathComponent("libcompanion.dylib")
        let clang = LiveShell()
        let libBuild = try await clang.execute([
            "/usr/bin/clang", "-dynamiclib",
            "-install_name", "@loader_path/libcompanion.dylib",
            "-o", dylib.path, dummyC.path,
        ])
        #expect(libBuild.success)

        let mainC = sourceDir.appendingPathComponent("main.c")
        try "int main(void) { return 0; }\n".write(to: mainC, atomically: true, encoding: .utf8)
        let source = sourceDir.appendingPathComponent("victim")
        let link = try await clang.execute([
            "/usr/bin/clang", "-o", source.path, mainC.path, dylib.path,
            "-Wl,-rpath,@loader_path",
        ])
        #expect(link.success)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        return (source, dylib)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang") && FileManager.default.fileExists(atPath: "/usr/bin/codesign")))
    func postPublishCompanionVerifyFailureRestoresParkedBundle() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("src")
        let (source, _) = try await makeLoaderPathFixture(in: sourceDir)

        let destination = root.appendingPathComponent("FixtureHome.app")
        try dummyUnsignedBundle(at: destination, marker: "keep-me")
        let oldInode = try bundleInode(at: destination)
        let oldMarkerPath = destination.appendingPathComponent("Contents/MacOS/OLD")
        let companionPath = destination.appendingPathComponent("Contents/MacOS/libcompanion.dylib").path

        let installer = AppBundleInstaller(shell: PostPublishCompanionFailingShell(companionPath: companionPath))
        await #expect(throws: AppBundleInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination, spec: spec())
        }

        #expect(FileManager.default.fileExists(atPath: oldMarkerPath.path))
        let marker = try String(contentsOf: oldMarkerPath, encoding: .utf8)
        #expect(marker == "keep-me")
        let restoredInode = try bundleInode(at: destination)
        #expect(restoredInode == oldInode)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/MacOS/FixtureHome").path))
        #expect(!FileManager.default.fileExists(atPath: companionPath))
        #expect(try leftoverInstallTrees(in: root).isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang") && FileManager.default.fileExists(atPath: "/usr/bin/codesign")))
    func postPublishCompanionVerifyFailureOnFreshInstallLeavesDestAbsent() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("src")
        let (source, _) = try await makeLoaderPathFixture(in: sourceDir)

        let destination = root.appendingPathComponent("FreshHome.app")
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let companionPath = destination.appendingPathComponent("Contents/MacOS/libcompanion.dylib").path

        let installer = AppBundleInstaller(shell: PostPublishCompanionFailingShell(companionPath: companionPath))
        await #expect(throws: AppBundleInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination, spec: spec())
        }

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try leftoverInstallTrees(in: root).isEmpty)
    }

    // MARK: - HAB-675 nested companion rpaths

    private func makeNestedLoaderPathFixture(in sourceDir: URL) async throws -> (source: URL, companion: URL, nested: URL) {
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let clang = LiveShell()

        let nestedC = sourceDir.appendingPathComponent("nested.c")
        try "void nested(void) {}\n".write(to: nestedC, atomically: true, encoding: .utf8)
        let nested = sourceDir.appendingPathComponent("libnested.dylib")
        let nestedBuild = try await clang.execute([
            "/usr/bin/clang", "-dynamiclib",
            "-install_name", "@loader_path/libnested.dylib",
            "-o", nested.path, nestedC.path,
        ])
        #expect(nestedBuild.success)

        let companionC = sourceDir.appendingPathComponent("companion.c")
        try "void nested(void); void dummy(void) { nested(); }\n".write(
            to: companionC, atomically: true, encoding: .utf8
        )
        let companion = sourceDir.appendingPathComponent("libcompanion.dylib")
        let companionBuild = try await clang.execute([
            "/usr/bin/clang", "-dynamiclib",
            "-install_name", "@loader_path/libcompanion.dylib",
            "-o", companion.path, companionC.path, nested.path,
            "-Wl,-rpath,@loader_path",
        ])
        #expect(companionBuild.success)

        let mainC = sourceDir.appendingPathComponent("main.c")
        try "int main(void) { return 0; }\n".write(to: mainC, atomically: true, encoding: .utf8)
        let source = sourceDir.appendingPathComponent("victim")
        let link = try await clang.execute([
            "/usr/bin/clang", "-o", source.path, mainC.path, companion.path,
            "-Wl,-rpath,@loader_path",
        ])
        #expect(link.success)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        return (source, companion, nested)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func nestedRequiredLoaderPathDylibFailsClosedAndLeavesDestination() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("src")
        let (source, _, nested) = try await makeNestedLoaderPathFixture(in: sourceDir)
        try FileManager.default.removeItem(at: nested)

        let destination = root.appendingPathComponent("FixtureHome.app")
        try dummyUnsignedBundle(at: destination, marker: "keep-me")
        let oldInode = try bundleInode(at: destination)

        let installer = AppBundleInstaller()
        await #expect(throws: AppBundleInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination, spec: spec())
        }

        let restoredInode = try bundleInode(at: destination)
        #expect(restoredInode == oldInode)
        let marker = try String(
            contentsOf: destination.appendingPathComponent("Contents/MacOS/OLD"),
            encoding: .utf8
        )
        #expect(marker == "keep-me")
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/MacOS/FixtureHome").path))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/MacOS/libcompanion.dylib").path))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/MacOS/libnested.dylib").path))
        #expect(try leftoverInstallTrees(in: root).isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang") && FileManager.default.fileExists(atPath: "/usr/bin/codesign")))
    func nestedLoaderPathDylibIsCopiedIntoMacOSAndDeepSigned() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("src")
        let (source, _, _) = try await makeNestedLoaderPathFixture(in: sourceDir)

        let destination = root.appendingPathComponent("FixtureHome.app")
        try dummyUnsignedBundle(at: destination, marker: "old-bundle")

        let installer = AppBundleInstaller()
        let report = try await installer.install(source: source, destination: destination, spec: spec())
        #expect(report.companionDylibs == ["libcompanion.dylib", "libnested.dylib"])

        let publishedCompanion = destination.appendingPathComponent("Contents/MacOS/libcompanion.dylib")
        let publishedNested = destination.appendingPathComponent("Contents/MacOS/libnested.dylib")
        #expect(FileManager.default.fileExists(atPath: publishedCompanion.path))
        #expect(FileManager.default.fileExists(atPath: publishedNested.path))

        let verify = try await LiveShell().execute([
            "codesign", "--verify", "--deep", "--strict", destination.path,
        ])
        #expect(verify.success)
        let companionVerify = try await LiveShell().execute([
            "codesign", "--verify", "--strict", publishedCompanion.path,
        ])
        #expect(companionVerify.success)
        let nestedVerify = try await LiveShell().execute([
            "codesign", "--verify", "--strict", publishedNested.path,
        ])
        #expect(nestedVerify.success)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/MacOS/OLD").path))
        #expect(try leftoverInstallTrees(in: root).isEmpty)
    }
}
