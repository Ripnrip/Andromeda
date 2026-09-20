import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// Fail-closed, atomic install transaction for bare Mach-O executables.
///
/// HAB-606 (2026-09-20): a freshly copied SwiftPM executable published at
/// `~/.local/bin/andromeda` was SIGKILLed by the macOS 26 signing monitor
/// (`Taskgated Invalid Signature` / `Invalid Page`) because the copy landed at
/// its final path *before* its post-copy ad-hoc signature settled. This
/// installer inverts the order into a single transaction:
///
/// 1. validate the source executable,
/// 2. stage a **fresh inode** (randomized name) inside the destination
///    directory — same volume, so the final publish is a true `rename(2)`,
/// 3. ad-hoc re-sign the **staged** copy (`codesign --force --sign -`),
/// 4. strictly verify the staged copy (`codesign --verify --strict`),
/// 5. atomically `rename(2)` staging → destination.
///
/// The live destination path is never written into: a process that is running
/// the old binary keeps its inode, and new launches always observe either the
/// fully-signed old artifact or the fully-signed new one. Any failure before
/// the rename leaves the destination untouched and removes the staging file.
///
/// Scope: single-file executables whose dependencies are all system libraries
/// (the `andromeda` CLI links only `/usr/lib` and system frameworks, with an
/// `@loader_path` rpath and no adjacent dylibs). Bundles that ship adjacent
/// rpath dylibs must re-sign those dylibs too and use `codesign --deep` on the
/// `.app` — that path is out of scope for this type.
public actor BinaryInstaller {

    /// Outcome of a successful install transaction.
    public struct Report: Sendable, CustomStringConvertible {
        /// The built artifact that was installed.
        public let source: String
        /// The final install path.
        public let destination: String
        /// Inode of the signed staging file captured just before the rename.
        ///
        /// NOTE: `codesign --force` replaces the file it signs (new inode), so
        /// this is captured *after* signing — it is the inode that the atomic
        /// rename then publishes, and equals `publishedInode`.
        public let signedInode: UInt64
        /// Inode previously at the destination, if any (fresh installs have none).
        public let previousDestinationInode: UInt64?
        /// Inode now at the destination (rename preserves the staged inode).
        public let publishedInode: UInt64
        /// Size of the installed executable in bytes.
        public let bytes: Int

        public var description: String {
            let previous = previousDestinationInode.map(String.init) ?? "none (fresh install)"
            return """
                install-cli report
                  source:          \(source)
                  destination:     \(destination)
                  signed inode:    \(signedInode)
                  previous inode:  \(previous)
                  published inode: \(publishedInode)  (atomic rename, fresh inode)
                  size:            \(bytes) bytes
                """
        }
    }

    /// Every failure mode of the transaction. All of them leave the
    /// destination untouched (or, for `postPublishVerificationFailed`, fail
    /// loudly after a staged-and-verified publish).
    public enum InstallError: Error, CustomStringConvertible, Sendable {
        case sourceMissing(String)
        case sourceNotExecutable(String)
        case destinationIsDirectory(String)
        case stagingFailed(String)
        case chmodFailed(String)
        case signingFailed(String)
        case verificationFailed(String)
        case publishFailed(String)
        case postPublishVerificationFailed(String)

        public var description: String {
            switch self {
            case .sourceMissing(let path):
                "Source executable not found: \(path)"
            case .sourceNotExecutable(let path):
                "Source is not an executable file: \(path)"
            case .destinationIsDirectory(let path):
                "Destination exists and is a directory: \(path)"
            case .stagingFailed(let detail):
                "Failed to stage fresh copy: \(detail)"
            case .chmodFailed(let detail):
                "Failed to make staged copy executable: \(detail)"
            case .signingFailed(let detail):
                "Ad-hoc signing of staged copy failed (destination untouched): \(detail)"
            case .verificationFailed(let detail):
                "Strict signature verification of staged copy failed (destination untouched): \(detail)"
            case .publishFailed(let detail):
                "Atomic rename into destination failed (destination untouched): \(detail)"
            case .postPublishVerificationFailed(let detail):
                "Published artifact failed post-publish verification: \(detail)"
            }
        }
    }

    private let shell: any ShellExecuting
    private let fileManager: FileManager

    public init(
        shell: (any ShellExecuting)? = LiveShell(),
        fileManager: FileManager = .default
    ) {
        self.shell = shell ?? LiveShell()
        self.fileManager = fileManager
    }

    /// Run the full install transaction and return its report.
    ///
    /// - Parameters:
    ///   - source: built executable to install.
    ///   - destination: final install path (parent directories are created).
    /// - Throws: `InstallError`; the destination is left untouched on any
    ///   pre-publish failure.
    public func install(source: URL, destination: URL) async throws -> Report {
        // 1. Validate source (exists, is a file, is executable).
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw InstallError.sourceMissing(source.path)
        }
        guard fileManager.isExecutableFile(atPath: source.path) else {
            throw InstallError.sourceNotExecutable(source.path)
        }
        if fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw InstallError.destinationIsDirectory(destination.path)
        }

        // 2. Stage a fresh inode next to the destination (same volume → the
        //    publish is a true atomic rename, never a cross-volume copy).
        let destinationDirectory = destination.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } catch {
            throw InstallError.stagingFailed("could not create \(destinationDirectory.path): \(error.localizedDescription)")
        }
        let stagingURL = destinationDirectory
            .appendingPathComponent(".\(destination.lastPathComponent).install-\(UUID().uuidString).tmp")
        do {
            try fileManager.copyItem(at: source, to: stagingURL)
        } catch {
            throw InstallError.stagingFailed(error.localizedDescription)
        }
        // Fail-closed helper: never leak the staging file.
        func cleanupAndThrow(_ error: InstallError) -> InstallError {
            try? fileManager.removeItem(at: stagingURL)
            return error
        }

        // 3. Executable bit (copyItem preserves source mode; enforce anyway).
        do {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagingURL.path)
        } catch {
            throw cleanupAndThrow(.chmodFailed(error.localizedDescription))
        }

        // 4. Ad-hoc re-sign the staged copy — never the live destination.
        let signResult = try await shell.execute(["codesign", "--force", "--sign", "-", stagingURL.path])
        guard signResult.success else {
            throw cleanupAndThrow(.signingFailed(signResult.output))
        }

        // 5. Strict verification before anything is published.
        let verifyResult = try await shell.execute(["codesign", "--verify", "--strict", stagingURL.path])
        guard verifyResult.success else {
            throw cleanupAndThrow(.verificationFailed(verifyResult.output))
        }
        // codesign --force replaces the file it signs (fresh inode); capture
        // the signed inode here — it is what the rename below publishes.
        let signedInode = inodeNumber(at: stagingURL)

        // 6. Atomic publish: rename(2) replaces the directory entry only.
        let previousInode = inodeNumber(at: destination)
        let renameResult = rename(stagingURL.path, destination.path)
        guard renameResult == 0 else {
            let detail = String(cString: strerror(errno))
            throw cleanupAndThrow(.publishFailed("rename(\(stagingURL.path) -> \(destination.path)): \(detail)"))
        }
        let publishedInode = inodeNumber(at: destination)
        let bytes = ((try? fileManager.attributesOfItem(atPath: destination.path))?[.size] as? Int) ?? 0

        // 7. Post-publish verification — the world sees the new inode now.
        let postVerify = try await shell.execute(["codesign", "--verify", "--strict", destination.path])
        guard postVerify.success, publishedInode == signedInode else {
            throw InstallError.postPublishVerificationFailed(
                "publish sanity failed (verify.success=\(postVerify.success), " +
                "published=\(publishedInode.map(String.init) ?? "nil") signed=\(signedInode.map(String.init) ?? "nil")): \(postVerify.output)"
            )
        }

        return Report(
            source: source.path,
            destination: destination.path,
            signedInode: signedInode ?? 0,
            previousDestinationInode: previousInode,
            publishedInode: publishedInode ?? 0,
            bytes: bytes
        )
    }

    private func inodeNumber(at url: URL) -> UInt64? {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.systemFileNumber] as? Int).map(UInt64.init)
    }
}
