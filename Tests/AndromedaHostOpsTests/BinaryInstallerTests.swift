
@testable import AndromedaHostOps
import Darwin
import Foundation
import Testing

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
        let oldInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)

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
        let oldInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)
        let oldSize = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int)

        let installer = BinaryInstaller(shell: MockShell(failOn: "--sign"))
        await #expect(throws: BinaryInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination)
        }

        // Destination untouched: same inode, same size.
        let newInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)
        let newSize = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int)
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
        let oldInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)

        let installer = BinaryInstaller(shell: MockShell(failOn: "--verify"))
        await #expect(throws: BinaryInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination)
        }

        let newInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)
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

    // MARK: - PR #88 LC_RPATH law

    @Test
    func parseOtoolRpathsExtractsPathsInDeclarationOrder() {
        let sample = """
        /tmp/victim:
        \t@rpath/libcompanion.dylib (compatibility version 0.0.0, current version 0.0.0)
        Load command 3
                  cmd LC_RPATH
              cmdsize 32
                 path @loader_path (offset 12)
        Load command 4
                  cmd LC_RPATH
              cmdsize 48
                 path @executable_path/../lib (offset 12)
        Load command 5
                  cmd LC_LOAD_DYLIB
              cmdsize 56
                 name /usr/lib/libSystem.B.dylib (offset 24)
        """
        let rpaths = BinaryInstaller.parseOtoolRpaths(sample)
        #expect(rpaths.map(\.path) == ["@loader_path", "@executable_path/../lib"])
        #expect(BinaryInstaller.isAdjacentRpath("@loader_path"))
        #expect(BinaryInstaller.isAdjacentRpath("@executable_path"))
        #expect(!BinaryInstaller.isAdjacentRpath("@executable_path/../lib"))
        #expect(!BinaryInstaller.isAdjacentRpath("/usr/local/lib"))
        #expect(!BinaryInstaller.isAdjacentRpath("@loader_path/../Frameworks"))
    }

    /// PR #88 (Codex thread, BinaryInstaller:158): the old adjacent-name
    /// flattening copied `@rpath/libcompanion.dylib` beside the executable
    /// and never read the declared `LC_RPATH` — here `@executable_path/../lib`
    /// — so dyld would look in `<dest>/../lib`, where this layout never
    /// puts the file. Fail closed, naming the rpath.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func nonAdjacentRpathFailsClosedWithLegibleError() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("src")
        let destDir = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        // libcompanion.dylib with a sibling install name, plus an executable
        // whose rpath points OUTSIDE the directory (../lib), not beside it.
        let dummyC = sourceDir.appendingPathComponent("dummy.c")
        try "void dummy(void) {}\n".write(to: dummyC, atomically: true, encoding: .utf8)
        let dylib = sourceDir.appendingPathComponent("libcompanion.dylib")
        let clang = LiveShell()
        let libBuild = try await clang.execute([
            "/usr/bin/clang", "-dynamiclib",
            "-install_name", "@rpath/libcompanion.dylib",
            "-o", dylib.path, dummyC.path,
        ])
        #expect(libBuild.success)

        let mainC = sourceDir.appendingPathComponent("main.c")
        try "int main(void) { return 0; }\n".write(to: mainC, atomically: true, encoding: .utf8)
        let source = sourceDir.appendingPathComponent("victim")
        let link = try await clang.execute([
            "/usr/bin/clang", "-o", source.path, mainC.path, dylib.path,
            "-Wl,-rpath,@executable_path/../lib",
        ])
        #expect(link.success)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)

        let destination = destDir.appendingPathComponent("dest-bin")
        try FileManager.default.copyItem(at: source, to: destination)
        let oldInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)

        let installer = BinaryInstaller()
        await #expect(throws: BinaryInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination)
        }

        let newInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)
        #expect(newInode == oldInode)
        #expect(!FileManager.default.fileExists(atPath: destDir.appendingPathComponent("libcompanion.dylib").path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    /// `@rpath` load with a bare `@loader_path` rpath resolves beside the
    /// executable — the adjacent-rpath law passes (P2), and the companion
    /// publishes into the executable's generation directory (P1), with the
    /// executable's rpath pointing there.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func adjacentRpathLoadStillInstallsBesideExecutable() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("src")
        let destDir = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let dummyC = sourceDir.appendingPathComponent("dummy.c")
        try "void dummy(void) {}\n".write(to: dummyC, atomically: true, encoding: .utf8)
        let dylib = sourceDir.appendingPathComponent("libcompanion.dylib")
        let clang = LiveShell()
        let libBuild = try await clang.execute([
            "/usr/bin/clang", "-dynamiclib",
            "-install_name", "@rpath/libcompanion.dylib",
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

        let destination = destDir.appendingPathComponent("dest-bin")
        try FileManager.default.copyItem(at: source, to: destination)
        let oldInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)

        let installer = BinaryInstaller()
        let report = try await installer.install(source: source, destination: destination)

        #expect(report.publishedInode != UInt64(oldInode))
        #expect(report.companionDylibs == ["libcompanion.dylib"])
        let genName = try #require(report.companionDirectory)
        #expect(
            FileManager.default.fileExists(
                atPath: destDir.appendingPathComponent(genName).appendingPathComponent("libcompanion.dylib").path
            )
        )
        let run = try await LiveShell().execute([destination.path])
        #expect(run.success)
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

    @Test
    func requiredLibraryGapsAllowsSourceAdjacentWhenDestMissing() {
        let libs = BinaryInstaller.parseOtoolL("""
        /tmp/bin:
        \t@loader_path/libcompanion.dylib (compatibility version 0.0.0, current version 0.0.0)
        """)
        let gaps = BinaryInstaller.requiredLibraryGaps(
            libs,
            adjacentDirectory: URL(fileURLWithPath: "/tmp/dest"),
            sourceDirectory: URL(fileURLWithPath: "/tmp/src"),
            fileExists: { $0 == "/tmp/src/libcompanion.dylib" }
        )
        #expect(gaps.isEmpty)
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
        let oldInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)

        let installer = BinaryInstaller()
        await #expect(throws: BinaryInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination)
        }

        let newInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)
        #expect(newInode == oldInode)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".install-") }
        #expect(leftovers.isEmpty)
    }

    /// A previous install's dylib is not trusted because the name exists.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func unsignedReusedDestinationCompanionFailsClosed() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("src")
        let destDir = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

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

        let reused = destDir.appendingPathComponent("libcompanion.dylib")
        try FileManager.default.copyItem(at: dylib, to: reused)
        let stripped = try await clang.execute(["/usr/bin/codesign", "--remove-signature", reused.path])
        #expect(stripped.success)
        try FileManager.default.removeItem(at: dylib)

        let destination = destDir.appendingPathComponent("dest-bin")
        let installer = BinaryInstaller()
        await #expect(throws: BinaryInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func adjacentLoaderPathDylibIsCopiedSignedAndPublished() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("src")
        let destDir = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

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

        let destination = destDir.appendingPathComponent("dest-bin")
        try FileManager.default.copyItem(at: source, to: destination)
        let oldInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)

        let installer = BinaryInstaller()
        let report = try await installer.install(source: source, destination: destination)

        #expect(report.publishedInode != UInt64(oldInode))
        #expect(report.companionDylibs == ["libcompanion.dylib"])

        // PR #88 contract: companions publish into the generation directory,
        // never flat beside the executable.
        let generationDir = try #require(report.companionDirectory)
        #expect(generationDir.hasPrefix(".dest-bin.companions."))
        let publishedDylib = destDir.appendingPathComponent(generationDir).appendingPathComponent("libcompanion.dylib")
        #expect(FileManager.default.fileExists(atPath: publishedDylib.path))
        #expect(!FileManager.default.fileExists(atPath: destDir.appendingPathComponent("libcompanion.dylib").path))

        let binVerify = try await LiveShell().execute(["codesign", "--verify", "--strict", destination.path])
        #expect(binVerify.success)
        let libVerify = try await LiveShell().execute(["codesign", "--verify", "--strict", publishedDylib.path])
        #expect(libVerify.success)

        let run = try await LiveShell().execute([destination.path])
        #expect(run.success)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
            .filter { $0.contains(".install-") }
        #expect(leftovers.isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func binaryRenameFailureRestoresParkedCompanionAndLeavesDestination() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("src")
        let destDir = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

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

        let destination = destDir.appendingPathComponent("dest-bin")
        try FileManager.default.copyItem(at: source, to: destination)
        let oldBinInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)

        let oldDylib = destDir.appendingPathComponent("libcompanion.dylib")
        try FileManager.default.copyItem(at: dylib, to: oldDylib)
        let oldDylibInode = try #require(FileManager.default.attributesOfItem(atPath: oldDylib.path)[.systemFileNumber] as? Int)

        let destPath = destination.path
        let liveMarker = destDir.appendingPathComponent("dest-existed-at-publish")
        let installer = BinaryInstaller(renamePaths: { old, new in
            // Fail only the staged-binary publish. The live path must still
            // exist at that moment — park is a hard link, not a rename-away.
            if new == destPath, URL(fileURLWithPath: old).lastPathComponent.contains(".install-") {
                if FileManager.default.fileExists(atPath: destPath) {
                    FileManager.default.createFile(atPath: liveMarker.path, contents: Data())
                }
                errno = EACCES
                return -1
            }
            return rename(old, new)
        })
        await #expect(throws: BinaryInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination)
        }
        #expect(FileManager.default.fileExists(atPath: liveMarker.path))

        let newBinInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)
        #expect(newBinInode == oldBinInode)

        #expect(FileManager.default.fileExists(atPath: oldDylib.path))
        let restoredDylibInode = try #require(FileManager.default.attributesOfItem(atPath: oldDylib.path)[.systemFileNumber] as? Int)
        #expect(restoredDylibInode == oldDylibInode)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    /// HAB-629: post-publish `codesign --verify --strict` on dest must restore
    /// the parked dest inode and previous companion, not leave the new pair.
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

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func postPublishVerifyFailureRestoresParkedDestAndCompanion() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("src")
        let destDir = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

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

        let destination = destDir.appendingPathComponent("dest-bin")
        try FileManager.default.copyItem(at: source, to: destination)
        let oldBinInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)

        let oldDylib = destDir.appendingPathComponent("libcompanion.dylib")
        try FileManager.default.copyItem(at: dylib, to: oldDylib)
        let oldDylibInode = try #require(FileManager.default.attributesOfItem(atPath: oldDylib.path)[.systemFileNumber] as? Int)

        let installer = BinaryInstaller(shell: PostPublishFailingShell(destPath: destination.path))
        await #expect(throws: BinaryInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination)
        }

        let newBinInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)
        #expect(newBinInode == oldBinInode)

        #expect(FileManager.default.fileExists(atPath: oldDylib.path))
        let restoredDylibInode = try #require(FileManager.default.attributesOfItem(atPath: oldDylib.path)[.systemFileNumber] as? Int)
        #expect(restoredDylibInode == oldDylibInode)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    /// HAB-631: dest post-publish verify succeeding is not enough — a failed
    /// companion dest verify must restore parked dest + companion inodes.
    ///
    /// PR #88: companions publish into a random-id generation directory, so
    /// the shell poisons the companion verify by path SHAPE (`--verify` on
    /// any `<...>.companions.<gen>/libcompanion.dylib`), not exact path.
    private actor PostPublishCompanionFailingShell: ShellExecuting {
        let companionName: String
        let live = LiveShell()

        init(companionName: String) {
            self.companionName = companionName
        }

        func execute(_ arguments: [String]) async throws -> ShellResult {
            if arguments.contains("--verify"),
               let last = arguments.last,
               last.contains(".companions."),
               last.hasSuffix("/\(companionName)")
            {
                return ShellResult(success: false, output: "mocked post-publish companion verify failure")
            }
            return try await live.execute(arguments)
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func postPublishCompanionVerifyFailureRestoresParkedDestAndCompanion() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("src")
        let destDir = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

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

        let destination = destDir.appendingPathComponent("dest-bin")
        try FileManager.default.copyItem(at: source, to: destination)
        let oldBinInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)

        // Legacy pre-#88 flat companion at dest; the failure must leave it
        // exactly where it was.
        let oldDylib = destDir.appendingPathComponent("libcompanion.dylib")
        try FileManager.default.copyItem(at: dylib, to: oldDylib)
        let oldDylibInode = try #require(FileManager.default.attributesOfItem(atPath: oldDylib.path)[.systemFileNumber] as? Int)

        let installer = BinaryInstaller(shell: PostPublishCompanionFailingShell(companionName: "libcompanion.dylib"))
        await #expect(throws: BinaryInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination)
        }

        let newBinInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)
        #expect(newBinInode == oldBinInode)

        #expect(FileManager.default.fileExists(atPath: oldDylib.path))
        let restoredDylibInode = try #require(FileManager.default.attributesOfItem(atPath: oldDylib.path)[.systemFileNumber] as? Int)
        #expect(restoredDylibInode == oldDylibInode)

        // The aborted generation directory must be cleaned up entirely.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
        let generationDirs = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
            .filter { $0.contains(".companions.") }
        #expect(generationDirs.isEmpty)
    }

    // MARK: - HAB-674 nested companion rpaths

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func nestedRequiredLoaderPathDylibFailsClosedAndLeavesDestination() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("src")
        let destDir = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

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
        try FileManager.default.removeItem(at: nested)

        let destination = destDir.appendingPathComponent("dest-bin")
        try FileManager.default.copyItem(at: source, to: destination)
        let oldInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)

        let installer = BinaryInstaller()
        await #expect(throws: BinaryInstaller.InstallError.self) {
            _ = try await installer.install(source: source, destination: destination)
        }

        let newInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)
        #expect(newInode == oldInode)
        #expect(!FileManager.default.fileExists(atPath: destDir.appendingPathComponent("libcompanion.dylib").path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func nestedLoaderPathDylibIsCopiedSignedAndPublished() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("src")
        let destDir = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

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

        let destination = destDir.appendingPathComponent("dest-bin")
        try FileManager.default.copyItem(at: source, to: destination)
        let oldInode = try #require(FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? Int)

        let installer = BinaryInstaller()
        let report = try await installer.install(source: source, destination: destination)

        #expect(report.publishedInode != UInt64(oldInode))
        #expect(report.companionDylibs == ["libcompanion.dylib", "libnested.dylib"])

        // PR #88 contract: both companions publish into the generation dir.
        let generationDir = try #require(report.companionDirectory)
        let generationURL = destDir.appendingPathComponent(generationDir)
        let publishedCompanion = generationURL.appendingPathComponent("libcompanion.dylib")
        let publishedNested = generationURL.appendingPathComponent("libnested.dylib")
        #expect(FileManager.default.fileExists(atPath: publishedCompanion.path))
        #expect(FileManager.default.fileExists(atPath: publishedNested.path))
        #expect(!FileManager.default.fileExists(atPath: destDir.appendingPathComponent("libcompanion.dylib").path))
        #expect(!FileManager.default.fileExists(atPath: destDir.appendingPathComponent("libnested.dylib").path))

        let binVerify = try await LiveShell().execute(["codesign", "--verify", "--strict", destination.path])
        #expect(binVerify.success)
        let companionVerify = try await LiveShell().execute(["codesign", "--verify", "--strict", publishedCompanion.path])
        #expect(companionVerify.success)
        let nestedVerify = try await LiveShell().execute(["codesign", "--verify", "--strict", publishedNested.path])
        #expect(nestedVerify.success)

        let run = try await LiveShell().execute([destination.path])
        #expect(run.success)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
            .filter { $0.contains(".install-") || $0.contains(".rollback-") || $0.contains(".orphan-") }
        #expect(leftovers.isEmpty)
    }

    // MARK: - PR #88 versioned companion generations

    /// Shared fixture builder: a `victim` executable + companion dylib with
    /// distinctive bytes per generation (a data symbol carrying the marker,
    /// so re-signing and differing object bytes stay distinguishable).
    private func makeGenerationsFixture(
        in sourceDir: URL,
        marker: String
    ) async throws -> (source: URL, dylib: URL) {
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let clang = LiveShell()
        let dummyC = sourceDir.appendingPathComponent("dummy-\(marker).c")
        try "const char *generation_marker = \"\(marker)\";\n".write(
            to: dummyC, atomically: true, encoding: .utf8
        )
        let dylib = sourceDir.appendingPathComponent("libcompanion.dylib")
        let libBuild = try await clang.execute([
            "/usr/bin/clang", "-dynamiclib",
            "-install_name", "@loader_path/libcompanion.dylib",
            "-o", dylib.path, dummyC.path,
        ])
        #expect(libBuild.success)
        let mainC = sourceDir.appendingPathComponent("main-\(marker).c")
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

    /// otool -l rpaths of a Mach-O, as strings.
    private func rpaths(ofBinaryAt path: String) async throws -> [String] {
        let result = try await LiveShell().execute(["/usr/bin/otool", "-l", path])
        #expect(result.success)
        return BinaryInstaller.parseOtoolRpaths(result.output).map(\.path)
    }

    /// Lock-protected probe results for the `@Sendable` rename injection.
    private final class ProbeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _executable: Data?
        private var _observations: [String] = []

        var executable: Data? {
            lock.lock()
            defer { lock.unlock() }
            return _executable
        }

        var observations: [String] {
            lock.lock()
            defer { lock.unlock() }
            return _observations
        }

        /// Snapshot what the LIVE (still-old) executable can resolve through
        /// its own declared rpaths at the switch instant, plus any other
        /// generation directories present on disk.
        func record(
            executable: Data?,
            destDirPath: String,
            resolvableRpathDirs: [String],
            previousGenerationBytes: Data
        ) {
            var notes: [String] = []
            for dir in resolvableRpathDirs {
                let companionPath = URL(fileURLWithPath: destDirPath)
                    .appendingPathComponent(dir)
                    .appendingPathComponent("libcompanion.dylib")
                if let bytes = try? Data(contentsOf: companionPath) {
                    notes.append("resolvable:\(dir):\(bytes == previousGenerationBytes ? "previous" : "NEW")")
                } else {
                    notes.append("resolvable:\(dir):missing")
                }
            }
            lock.lock()
            _executable = executable
            _observations.append(contentsOf: notes)
            lock.unlock()
        }
    }

    /// PR #88 core regression (Codex thread, BinaryInstaller:334): install
    /// generation 1, then generation 2. After the second install:
    ///   • the executable's rpath points at generation 2's directory
    ///     (otool -l assertion),
    ///   • generation 1's directory is gone (swept — nothing can resolve it),
    ///   • no dylib ever sits flat beside the executable, and
    ///   • the installed pair launches.
    /// At no instant does a consumer observe old-executable + new-generation
    /// companions: the new generation is fully populated before the single
    /// executable rename, and each generation's files live only in their
    /// own directory.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func twoGenerationsNeverMixAndExecutableTracksTheLiveOne() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let destDir = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destination = destDir.appendingPathComponent("dest-bin")

        // --- generation 1 ---
        let gen1Dir = root.appendingPathComponent("gen1-src")
        let (source1, _) = try await makeGenerationsFixture(in: gen1Dir, marker: "gen1")
        let report1 = try await BinaryInstaller().install(source: source1, destination: destination)
        let gen1Name = try #require(report1.companionDirectory)
        #expect(FileManager.default.fileExists(atPath: destDir.appendingPathComponent(gen1Name).appendingPathComponent("libcompanion.dylib").path))

        // --- generation 2 (companion with different bytes) ---
        let gen2Dir = root.appendingPathComponent("gen2-src")
        let (source2, _) = try await makeGenerationsFixture(in: gen2Dir, marker: "gen2")
        let report2 = try await BinaryInstaller().install(source: source2, destination: destination)
        let gen2Name = try #require(report2.companionDirectory)

        // Different generations get different directories.
        #expect(gen1Name != gen2Name)

        // The executable's rpath points at generation 2 — and ONLY it.
        let destRpaths = try await rpaths(ofBinaryAt: destination.path)
        #expect(destRpaths == ["@loader_path/\(gen2Name)"])

        // Generation 1's directory was swept after generation 2 went live.
        #expect(!FileManager.default.fileExists(atPath: destDir.appendingPathComponent(gen1Name).path))

        // Generation 2's companion is present at its own directory.
        #expect(
            FileManager.default.fileExists(
                atPath: destDir.appendingPathComponent(gen2Name).appendingPathComponent("libcompanion.dylib").path
            )
        )

        // No companion ever sits flat beside the executable.
        #expect(!FileManager.default.fileExists(atPath: destDir.appendingPathComponent("libcompanion.dylib").path))

        // The published pair launches.
        let run = try await LiveShell().execute([destination.path])
        #expect(run.success)

        // Exactly one generation directory remains.
        let generationDirs = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
            .filter { $0.contains(".companions.") }
        #expect(generationDirs == [gen2Name])
    }

    /// Mid-transaction probe: a consumer observing the destination between
    /// companion-publish and executable-switch must see the OLD executable
    /// and NO new-generation companion bytes at any old-resolvable path.
    /// (The generation dir is hidden + new-named, and the old flat layout is
    /// untouched — the old executable keeps resolving its old bytes.)
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/clang")))
    func oldExecutableNeverSeesNewGenerationBytes() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let destDir = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destination = destDir.appendingPathComponent("dest-bin")

        // Generation 1 installed live.
        let gen1Dir = root.appendingPathComponent("gen1-src")
        let (source1, _) = try await makeGenerationsFixture(in: gen1Dir, marker: "gen1")
        let report1 = try await BinaryInstaller().install(source: source1, destination: destination)
        let gen1Name = try #require(report1.companionDirectory)
        // Bytes as INSTALLED (post re-sign) — the ground truth a consumer
        // of generation 1 resolves.
        let installedGen1Bytes = try Data(
            contentsOf: destDir.appendingPathComponent(gen1Name).appendingPathComponent("libcompanion.dylib")
        )

        // Generation 2 attempt with a probe injected at the executable-switch
        // rename: snapshot what a concurrent consumer would observe.
        let gen2Dir = root.appendingPathComponent("gen2-src")
        let (source2, _) = try await makeGenerationsFixture(in: gen2Dir, marker: "gen2")
        let oldExecutableBytes = try Data(contentsOf: destination)
        // The OLD executable's own rpaths — everything it can ever resolve.
        let oldRpathDirs = try await rpaths(ofBinaryAt: destination.path)
            .compactMap { rpath -> String? in
                guard rpath.hasPrefix("@loader_path/") else { return nil }
                return String(rpath.dropFirst("@loader_path/".count))
            }
        #expect(oldRpathDirs == [gen1Name])
        let destPath = destination.path
        let destDirPath = destDir.path
        let probe = ProbeBox()
        let installer = BinaryInstaller(renamePaths: { old, new in
            if new == destPath {
                // Executable-switch instant: the live binary is still the OLD
                // one; everything it can resolve must still be OLD bytes.
                probe.record(
                    executable: try? Data(contentsOf: URL(fileURLWithPath: destPath)),
                    destDirPath: destDirPath,
                    resolvableRpathDirs: oldRpathDirs,
                    previousGenerationBytes: installedGen1Bytes
                )
            }
            return rename(old, new)
        })
        _ = try await installer.install(source: source2, destination: destination)

        // The live executable at the switch instant was still the old one.
        let snapshot = try #require(probe.executable)
        #expect(snapshot == oldExecutableBytes)
        // Every path the OLD executable can resolve still holds the
        // PREVIOUS generation's installed bytes — never gen-2 bytes.
        let observations = probe.observations
        #expect(observations.count == oldRpathDirs.count)
        #expect(observations.allSatisfy { $0.hasPrefix("resolvable:") && $0.hasSuffix(":previous") })
        // Gen-2's own staged bytes genuinely differ from gen-1's installed
        // bytes (data-symbol marker), so the assertion above has teeth.
        let report2Name = try FileManager.default.contentsOfDirectory(atPath: destDirPath)
            .first { $0.hasPrefix(".dest-bin.companions.") }
        let gen2Companion = try Data(
            contentsOf: destDir.appendingPathComponent(#require(report2Name))
                .appendingPathComponent("libcompanion.dylib")
        )
        #expect(gen2Companion != installedGen1Bytes)
    }
}
