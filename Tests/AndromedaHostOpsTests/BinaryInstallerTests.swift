import AndromedaHostOps
import Foundation
import Testing

@testable import AndromedaHostOps

/// BinaryInstaller transaction tests.
///
/// Two layers:
/// 1. **Mocked shell** — failure-mode coverage: every failure path must leave
///    the destination untouched and remove the staging file.
/// 2. **Live codesign round-trip** — skipped unless `/usr/bin/codesign` and a
///    real Mach-O source are both present (macOS runners).
@Suite(.serialized)
struct BinaryInstallerTests {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("binary-installer-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Small real Mach-O executable used as install source: `/usr/bin/true` copy.
    private func makeSource(_ dir: URL) -> URL {
        let src = dir.appendingPathComponent("source-bin")
        try! FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: src)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: src.path)
        return src
    }

    // MARK: - Live round-trip (codesign present)

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/codesign")))
    func liveInstallPublishesFreshSignedInode() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = makeSource(dir)
        let destination = dir.appendingPathComponent("dest-bin")

        // Pre-existing old artifact at the destination (different inode).
        try FileManager.default.copyItem(at: source, to: destination)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int

        let installer = BinaryInstaller()
        let report = try await installer.install(source: source, destination: destination)

        // Fresh inode published atomically.
        #expect(report.publishedInode != UInt64(oldInode))
        #expect(report.publishedInode == report.signedInode)

        // Destination carries a strict-valid signature.
        let verify = try await LiveShell().execute(["codesign", "--verify", "--strict", destination.path])
        #expect(verify.success)

        // No staging leftovers.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") }
        #expect(leftovers.isEmpty)
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
        let destination = dir.appendingPathComponent("dest-bin")

        // Old artifact exists — must survive the failed install untouched.
        try FileManager.default.copyItem(at: source, to: destination)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let oldSize = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as! Int

        let installer = BinaryInstaller(shell: MockShell(failOn: "--sign"))
        await #expect(throws: BinaryInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination)
        }

        // Destination untouched: same inode, same size.
        let newInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        let newSize = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as! Int
        #expect(newInode == oldInode)
        #expect(newSize == oldSize)

        // No staging leftovers.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") }
        #expect(leftovers.isEmpty)
    }

    @Test
    func verificationFailureLeavesDestinationUntouchedAndCleansStaging() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = makeSource(dir)
        let destination = dir.appendingPathComponent("dest-bin")
        try FileManager.default.copyItem(at: source, to: destination)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int

        let installer = BinaryInstaller(shell: MockShell(failOn: "--verify"))
        await #expect(throws: BinaryInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination)
        }

        let newInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        #expect(newInode == oldInode)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") }
        #expect(leftovers.isEmpty)
    }

    // MARK: - HAB-625 linked-library policy

    @Test
    func parseOtoolLSkipsHeaderAndNotesWeak() {
        let sample = """
        /tmp/andromeda:
        \t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1356.0.0)
        \t/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation (compatibility version 300.0.0, current version 1.0.0)
        \t@rpath/libswiftCompatibilitySpan.dylib (compatibility version 0.0.0, current version 0.0.0, weak)
        \t@loader_path/libmissing.dylib (compatibility version 0.0.0, current version 0.0.0)
        """
        let libs = BinaryInstaller.parseOtoolL(sample)
        #expect(libs.count == 4)
        #expect(libs[0].isSystem)
        #expect(!libs[0].isWeak)
        #expect(libs[2].installName == "@rpath/libswiftCompatibilitySpan.dylib")
        #expect(libs[2].isWeak)
        #expect(libs[2].adjacentFileName == "libswiftCompatibilitySpan.dylib")
        #expect(libs[3].adjacentFileName == "libmissing.dylib")
        #expect(!libs[3].isWeak)
    }

    @Test
    func requiredLibraryGapsAllowsWeakMissingAndSystem() {
        let libs = BinaryInstaller.parseOtoolL("""
        /tmp/bin:
        \t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)
        \t@rpath/libswiftCompatibilitySpan.dylib (compatibility version 0.0.0, current version 0.0.0, weak)
        """)
        let gaps = BinaryInstaller.requiredLibraryGaps(
            libs,
            adjacentDirectory: URL(fileURLWithPath: "/tmp"),
            fileExists: { _ in false }
        )
        #expect(gaps.isEmpty)
    }

    @Test
    func requiredLibraryGapsFailsOnMissingRequiredLoaderPath() {
        let libs = BinaryInstaller.parseOtoolL("""
        /tmp/bin:
        \t@loader_path/libmissing.dylib (compatibility version 0.0.0, current version 0.0.0)
        """)
        let gaps = BinaryInstaller.requiredLibraryGaps(
            libs,
            adjacentDirectory: URL(fileURLWithPath: "/tmp"),
            fileExists: { _ in false }
        )
        #expect(gaps.map(\.installName) == ["@loader_path/libmissing.dylib"])
    }

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

        let destination = dir.appendingPathComponent("dest-bin")
        try FileManager.default.copyItem(at: source, to: destination)
        let oldInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int

        let installer = BinaryInstaller()
        await #expect(throws: BinaryInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination)
        }

        let newInode = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as! Int
        #expect(newInode == oldInode)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") }
        #expect(leftovers.isEmpty)
    }
}
