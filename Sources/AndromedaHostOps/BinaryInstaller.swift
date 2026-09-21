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
/// Scope: single-file executables. System libraries (`/usr/lib`, `/System`,
/// `/Library/Apple`) and **weak** loads are allowed to be missing (the live
/// `andromeda` CLI weakly links `@rpath/libswiftCompatibilitySpan.dylib`).
/// Required runtime-relative dylibs (`@rpath` / `@loader_path` /
/// `@executable_path`) must exist next to the staged copy — otherwise the
/// transaction fails closed and the destination is left untouched. Bundles
/// that ship adjacent rpath dylibs must re-sign those dylibs too and use
/// `codesign --deep` on the `.app` (`AppBundleInstaller`). HAB-625.
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
        case linkedLibraryInspectionFailed(String)
        case missingRequiredLinkedLibrary(String)

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
            case .linkedLibraryInspectionFailed(let detail):
                "Could not inspect staged linked libraries (destination untouched): \(detail)"
            case .missingRequiredLinkedLibrary(let detail):
                "Staged copy is missing a required non-system dylib (destination untouched): \(detail)"
            }
        }
    }

    /// One `otool -L` load command from a Mach-O.
    public struct LinkedLibrary: Sendable, Equatable {
        public let installName: String
        public let isWeak: Bool

        public var isSystem: Bool {
            installName.hasPrefix("/usr/lib/")
                || installName.hasPrefix("/System/")
                || installName.hasPrefix("/Library/Apple/")
        }

        public var isRuntimeRelative: Bool {
            installName.hasPrefix("@rpath/")
                || installName.hasPrefix("@loader_path/")
                || installName.hasPrefix("@executable_path/")
        }

        /// Last path component when the install name is `@rpath/foo.dylib` (no subdirs).
        public var adjacentFileName: String? {
            for prefix in ["@rpath/", "@loader_path/", "@executable_path/"] {
                guard installName.hasPrefix(prefix) else { continue }
                let rest = String(installName.dropFirst(prefix.count))
                if rest.isEmpty || rest.contains("/") { return nil }
                return rest
            }
            return nil
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

        // 4. Fail closed if required runtime-relative dylibs are missing next
        //    to the staged copy. Weak loads (e.g. libswiftCompatibilitySpan)
        //    and system libraries are allowed to be absent. HAB-625.
        do {
            try await inspectLinkedLibraries(at: stagingURL)
        } catch let error as InstallError {
            throw cleanupAndThrow(error)
        } catch {
            throw cleanupAndThrow(.linkedLibraryInspectionFailed(error.localizedDescription))
        }

        // 5. Ad-hoc re-sign the staged copy — never the live destination.
        let signResult = try await shell.execute(["codesign", "--force", "--sign", "-", stagingURL.path])
        guard signResult.success else {
            throw cleanupAndThrow(.signingFailed(signResult.output))
        }

        // 6. Strict verification before anything is published.
        let verifyResult = try await shell.execute(["codesign", "--verify", "--strict", stagingURL.path])
        guard verifyResult.success else {
            throw cleanupAndThrow(.verificationFailed(verifyResult.output))
        }
        // codesign --force replaces the file it signs (fresh inode); capture
        // the signed inode here — it is what the rename below publishes.
        let signedInode = inodeNumber(at: stagingURL)

        // 7. Atomic publish: rename(2) replaces the directory entry only.
        let previousInode = inodeNumber(at: destination)
        let renameResult = rename(stagingURL.path, destination.path)
        guard renameResult == 0 else {
            let detail = String(cString: strerror(errno))
            throw cleanupAndThrow(.publishFailed("rename(\(stagingURL.path) -> \(destination.path)): \(detail)"))
        }
        let publishedInode = inodeNumber(at: destination)
        let bytes = ((try? fileManager.attributesOfItem(atPath: destination.path))?[.size] as? Int) ?? 0

        // 8. Post-publish verification — the world sees the new inode now.
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

    private func inspectLinkedLibraries(at staged: URL) async throws {
        let result = try await shell.execute(["/usr/bin/otool", "-L", staged.path])
        guard result.success else {
            throw InstallError.linkedLibraryInspectionFailed(result.output)
        }
        let libraries = Self.parseOtoolL(result.output)
        let gaps = Self.requiredLibraryGaps(
            libraries,
            adjacentDirectory: staged.deletingLastPathComponent(),
            fileExists: { [fileManager] path in
                fileManager.fileExists(atPath: path)
            }
        )
        if !gaps.isEmpty {
            let detail = gaps.map(\.installName).joined(separator: ", ")
            throw InstallError.missingRequiredLinkedLibrary(detail)
        }
    }

    /// Parse `otool -L` stdout into load commands. Header lines (`path:`) skipped.
    public static func parseOtoolL(_ output: String) -> [LinkedLibrary] {
        var libraries: [LinkedLibrary] = []
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasSuffix(":") { continue }
            guard let paren = line.firstIndex(of: "(") else { continue }
            let name = line[..<paren].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let meta = line[paren...]
            libraries.append(
                LinkedLibrary(installName: String(name), isWeak: meta.contains("weak"))
            )
        }
        return libraries
    }

    /// Required (non-weak) libraries that would not resolve after a single-file publish.
    public static func requiredLibraryGaps(
        _ libraries: [LinkedLibrary],
        adjacentDirectory: URL,
        fileExists: (String) -> Bool
    ) -> [LinkedLibrary] {
        libraries.filter { library in
            if library.isWeak { return false }
            if library.isSystem { return false }
            if let name = library.adjacentFileName {
                let adjacent = adjacentDirectory.appendingPathComponent(name)
                return !fileExists(adjacent.path)
            }
            if library.isRuntimeRelative {
                // `@rpath/subdir/lib.dylib` — we do not copy directory trees.
                return true
            }
            // Absolute non-system path: dyld can still load it if it exists.
            return !fileExists(library.installName)
        }
    }
}
