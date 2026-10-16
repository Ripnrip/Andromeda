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
/// Scope: single-file executables plus **adjacent** required rpath dylibs.
/// System libraries (`/usr/lib`, `/System`, `/Library/Apple`) and **weak**
/// loads are allowed to be missing (the live `andromeda` CLI weakly links
/// `@rpath/libswiftCompatibilitySpan.dylib`). Required runtime-relative
/// dylibs (`@rpath` / `@loader_path` / `@executable_path`) must exist next to
/// the source *or* already next to the destination — otherwise the
/// transaction fails closed (HAB-625). Companion dylibs are themselves
/// `otool -L`'d (HAB-674): a nested required adjacent name is staged too,
/// and a missing nested required dylib fails closed before publish.
/// Companions are staged, ad-hoc re-signed, strictly verified, then
/// published into a per-install generation directory
/// `.<execname>.companions.<generation-id>/` beside the destination, and
/// the executable's load commands are rewritten (`install_name_tool`) to
/// `@rpath/<name>` with a single added rpath pointing at that directory
/// (PR #88). The generation directory is fully populated and verified
/// BEFORE the executable's atomic rename — the one instant that switches
/// generations — so no consumer can ever observe old-executable +
/// new-companion-generation or the reverse. Previous generations are
/// swept only after post-publish verify succeeds; any earlier failure
/// removes the fresh generation and leaves dest untouched. Installs with
/// no companions keep the flat single-file layout. Images that require
/// `@rpath` loads must declare only adjacent rpaths — `@executable_path` /
/// `@loader_path` — anything else fails closed rather than flattening
/// (PR #88). Bundles that ship a tree
/// of rpath dylibs use `codesign --deep` on the `.app` (`AppBundleInstaller`).
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
        /// Adjacent required dylibs copied+signed into the destination directory.
        public let companionDylibs: [String]
        /// Directory the companions were published into
        /// (`.<execname>.companions.<generation>`), when any exist. The
        /// executable's `LC_RPATH` points here, so each install generation
        /// resolves only its own companions — cross-generation mixes are
        /// structurally impossible (PR #88).
        public let companionDirectory: String?

        public var description: String {
            let previous = previousDestinationInode.map(String.init) ?? "none (fresh install)"
            let companions =
                companionDylibs.isEmpty ? "(none)" : companionDylibs.joined(separator: ", ")
            let companionDir = companionDirectory ?? "(flat: no companions)"
            return """
            install-cli report
              source:          \(source)
              destination:     \(destination)
              signed inode:    \(signedInode)
              previous inode:  \(previous)
              published inode: \(publishedInode)  (atomic rename, fresh inode)
              size:            \(bytes) bytes
              companions:      \(companions)
              companion dir:   \(companionDir)
            """
        }
    }

    /// Every failure mode of the transaction leaves dest + companions as
    /// they were before this call. Companion dylibs are published *before*
    /// the executable; a binary-rename failure restores parked companion
    /// inodes so dest never keeps new dylibs beside the old binary
    /// (HAB-628). The previous dest inode is parked before the executable
    /// rename, and backups stay until post-publish verify succeeds on dest
    /// and each companion so a failed dest or companion verify can restore
    /// dest + companions (HAB-629 / HAB-631).
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
        case rpathUnsupported(detail: String, rpath: String)
        case companionRewriteFailed(String)

        public var description: String {
            switch self {
            case let .sourceMissing(path):
                "Source executable not found: \(path)"
            case let .sourceNotExecutable(path):
                "Source is not an executable file: \(path)"
            case let .destinationIsDirectory(path):
                "Destination exists and is a directory: \(path)"
            case let .stagingFailed(detail):
                "Failed to stage fresh copy: \(detail)"
            case let .chmodFailed(detail):
                "Failed to make staged copy executable: \(detail)"
            case let .signingFailed(detail):
                "Ad-hoc signing of staged copy failed (destination untouched): \(detail)"
            case let .verificationFailed(detail):
                "Strict signature verification of staged copy failed (destination untouched): \(detail)"
            case let .publishFailed(detail):
                "Atomic rename into destination failed (destination untouched): \(detail)"
            case let .postPublishVerificationFailed(detail):
                "Published artifact failed post-publish verification (destination restored): \(detail)"
            case let .linkedLibraryInspectionFailed(detail):
                "Could not inspect staged linked libraries (destination untouched): \(detail)"
            case let .missingRequiredLinkedLibrary(detail):
                "Staged copy is missing a required non-system dylib (destination untouched): \(detail)"
            case let .rpathUnsupported(detail, rpath):
                "Required @rpath load cannot be reproduced by this install layout "
                    + "(adjacent-name flattening would silently change where dyld finds it): "
                    + "\(detail) — rpath: \(rpath)"
            case let .companionRewriteFailed(detail):
                "Rewriting the staged executable to load companions from its own "
                    + "generation directory failed (destination untouched): \(detail)"
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
                if rest.isEmpty || rest.contains("/") {
                    return nil
                }
                return rest
            }
            return nil
        }
    }

    private struct PlannedCompanion {
        let fileName: String
        let sourceURL: URL
        let stagingURL: URL
        let destinationURL: URL
    }

    /// Layout of one companion generation.
    ///
    /// PR #88 (Codex thread, BinaryInstaller:334): companions used to be
    /// renamed into the destination directory *before* the executable's
    /// own `parkDestination` + `rename` switch. In that window a consumer
    /// could observe the OLD executable with NEW-generation dylibs beside
    /// it (or, after the switch, a NEW executable resolving OLD-generation
    /// files). Each generation instead gets its own hidden directory,
    /// `.<execname>.companions.<generation>/`, fully populated and verified
    /// BEFORE the single executable rename that switches generations. A new
    /// launch of the old executable keeps resolving the old generation's
    /// bytes at the old generation's paths — cross-generation mixes are
    /// structurally impossible, not merely unlikely.
    private struct CompanionGeneration {
        /// Short unique generation id (8 hex chars) — directory name only.
        let id: String
        /// `@loader_path/.<execname>.companions.<id>` — injected into the
        /// staged executable so it resolves companions relative to itself.
        let rpath: String
        /// Absolute host path of the generation directory.
        let directoryURL: URL

        init?(destinationDirectory: URL, executableName: String) {
            let raw = UUID().uuidString
            let id = String(raw.prefix(8))
            guard raw.prefix(8) == id, id.count == 8 else { return nil }
            self.id = id
            let directoryName = ".\(executableName).companions.\(id)"
            rpath = "@loader_path/\(directoryName)"
            directoryURL = destinationDirectory.appendingPathComponent(directoryName)
        }
    }

    private let shell: any ShellExecuting
    private let fileManager: FileManager
    /// Injected `rename(2)` so tests can fail the executable publish after
    /// companions have already been renamed into the destination directory.
    private let renamePaths: @Sendable (String, String) -> Int32

    public init(
        shell: (any ShellExecuting)? = LiveShell(),
        fileManager: FileManager = .default,
        renamePaths: (@Sendable (String, String) -> Int32)? = nil
    ) {
        self.shell = shell ?? LiveShell()
        self.fileManager = fileManager
        self.renamePaths = renamePaths ?? { old, new in rename(old, new) }
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

        var stagedURLs: [URL] = [stagingURL]
        /// Fail-closed helper: never leak staging files.
        func cleanupAndThrow(_ error: InstallError) -> InstallError {
            for url in stagedURLs.reversed() {
                try? fileManager.removeItem(at: url)
            }
            return error
        }

        // 3. Executable bit (copyItem preserves source mode; enforce anyway).
        do {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagingURL.path)
        } catch {
            throw cleanupAndThrow(.chmodFailed(error.localizedDescription))
        }

        // 4. Inspect linked libraries. Required adjacent dylibs must exist
        //    next to the source or already next to the destination (HAB-625).
        //    Source-adjacent companions are staged+signed+published (HAB-626).
        //    Companions are inspected too — nested required adjacent names
        //    join the same fail-closed + stage set (HAB-674). Every image
        //    with an @rpath load must declare only adjacent rpaths (PR #88).
        let sourceDirectory = source.deletingLastPathComponent()
        let libraries: [LinkedLibrary]
        let initialExecutableLibraries: [LinkedLibrary]
        do {
            let initial = try await loadLinkedLibraries(at: stagingURL)
            initialExecutableLibraries = initial
            libraries = try await expandLinkedLibraries(
                initial: initial,
                sourceDirectory: sourceDirectory,
                executableURL: stagingURL
            )
        } catch let error as InstallError {
            throw cleanupAndThrow(error)
        } catch {
            throw cleanupAndThrow(.linkedLibraryInspectionFailed(error.localizedDescription))
        }

        // PR #88: companions of previous installs live either in a previous
        // generation directory (new layout) or flat beside the destination
        // (pre-#88 layout). Resolve the previous generation, if any, from the
        // live executable's declared rpaths — before anything replaces it.
        let previousGenerationDirectory: URL?
        do {
            if fileManager.fileExists(atPath: destination.path) {
                let destRpaths = try await loadRpaths(at: destination)
                previousGenerationDirectory = Self.generationDirectory(
                    from: destRpaths,
                    destinationDirectory: destinationDirectory,
                    fileExists: { [fileManager] path in
                        fileManager.fileExists(atPath: path)
                    }
                )
            } else {
                previousGenerationDirectory = nil
            }
        } catch let error as InstallError {
            throw cleanupAndThrow(error)
        } catch {
            throw cleanupAndThrow(.linkedLibraryInspectionFailed(error.localizedDescription))
        }

        // Required adjacent names must resolve somewhere this transaction can
        // stage them from: the source directory, the previous generation
        // directory, or the legacy flat destination layout.
        do {
            let flatGaps = Self.requiredLibraryGaps(
                libraries,
                adjacentDirectory: destinationDirectory,
                sourceDirectory: sourceDirectory,
                fileExists: { [fileManager] path in
                    fileManager.fileExists(atPath: path)
                }
            )
            let unresolved: [LinkedLibrary]
            if let previousGenerationDirectory {
                let generationGaps = Self.requiredLibraryGaps(
                    libraries,
                    adjacentDirectory: previousGenerationDirectory,
                    sourceDirectory: sourceDirectory,
                    fileExists: { [fileManager] path in
                        fileManager.fileExists(atPath: path)
                    }
                )
                // Missing from BOTH layouts (and the source) is a real gap.
                unresolved = generationGaps.filter { gap in
                    flatGaps.contains { $0.installName == gap.installName }
                }
            } else {
                unresolved = flatGaps
            }
            if !unresolved.isEmpty {
                let detail = unresolved.map(\.installName).joined(separator: ", ")
                throw cleanupAndThrow(.missingRequiredLinkedLibrary(detail))
            }
        } catch let error as InstallError {
            throw cleanupAndThrow(error)
        } catch {
            throw cleanupAndThrow(.linkedLibraryInspectionFailed(error.localizedDescription))
        }

        do {
            try await verifyReusedDestinationCompanions(
                libraries: libraries,
                sourceDirectory: sourceDirectory,
                destinationDirectory: destinationDirectory,
                previousGenerationDirectory: previousGenerationDirectory
            )
        } catch let error as InstallError {
            throw cleanupAndThrow(error)
        } catch {
            throw cleanupAndThrow(.verificationFailed(error.localizedDescription))
        }

        // PR #88: stage companions into their own generation directory so no
        // consumer can ever observe old-executable + new-companion (or the
        // reverse). Fresh installs without companions keep the flat layout
        // untouched — no directory, no rpath surgery.
        let companionNames = Self.requiredCompanionNames(libraries)
        let generation: CompanionGeneration?
        let companions: [PlannedCompanion]
        do {
            if companionNames.isEmpty {
                generation = nil
                companions = []
            } else {
                guard let gen = CompanionGeneration(
                    destinationDirectory: destinationDirectory,
                    executableName: destination.lastPathComponent
                ) else {
                    throw InstallError.stagingFailed("could not derive companion generation id")
                }
                generation = gen
                try fileManager.createDirectory(at: gen.directoryURL, withIntermediateDirectories: true)
                companions = try await stageCompanions(
                    names: companionNames,
                    sourceDirectory: sourceDirectory,
                    destinationDirectory: destinationDirectory,
                    previousGenerationDirectory: previousGenerationDirectory,
                    generation: gen,
                    stagedURLs: &stagedURLs
                )
            }
        } catch let error as InstallError {
            throw cleanupAndThrow(error)
        } catch {
            throw cleanupAndThrow(.stagingFailed(error.localizedDescription))
        }
        // stagedURLs cleanup covers the generation directory itself once
        // companions are staged inside it.
        if let generation {
            stagedURLs.append(generation.directoryURL)
        }

        // Every required adjacent name must now be present inside the
        // generation directory — this is the fail-closed gaps moment for
        // the new layout (source- and reuse-staged files both land there).
        if let generation {
            let genGaps = Self.requiredLibraryGaps(
                libraries,
                adjacentDirectory: generation.directoryURL,
                fileExists: { [fileManager] path in
                    fileManager.fileExists(atPath: path)
                }
            )
            if !genGaps.isEmpty {
                let detail = genGaps.map(\.installName).joined(separator: ", ")
                throw cleanupAndThrow(.missingRequiredLinkedLibrary(detail))
            }
        }

        // 5. Ad-hoc re-sign companions, then the staged executable.
        for companion in companions {
            let signResult = try await shell.execute([
                "codesign", "--force", "--sign", "-", companion.stagingURL.path,
            ])
            guard signResult.success else {
                throw cleanupAndThrow(.signingFailed("\(companion.fileName): \(signResult.output)"))
            }
            let verifyResult = try await shell.execute([
                "codesign", "--verify", "--strict", companion.stagingURL.path,
            ])
            guard verifyResult.success else {
                throw cleanupAndThrow(.verificationFailed("\(companion.fileName): \(verifyResult.output)"))
            }
        }

        // 5b. PR #88: point the staged executable at its own companion
        // generation. Companions now live in `.gen/`, but the executable
        // sits in the destination directory — `@loader_path` /
        // `@executable_path` load commands would resolve beside the
        // executable, where the files no longer are. On the STAGED copy,
        // before any publish (the live destination binary is untouched):
        //   • every staged adjacent load becomes `@rpath/<name>`,
        //   • every declared rpath is deleted (a stale `@loader_path`
        //     could otherwise resolve a leftover flat dylib at dest ahead
        //     of the generation directory — the cross-generation mix this
        //     fix exists to make impossible), and
        //   • exactly one rpath is added: `@loader_path/<gen-dir>`.
        // `install_name_tool` invalidates any existing signature, so the
        // re-sign in 5c is mandatory, not cosmetic. Companions keep their
        // own load commands: their `@loader_path` is the generation
        // directory, where their nested peers already live.
        if let generation {
            var rewritten: Set<String> = []
            for library in initialExecutableLibraries where !library.isWeak {
                guard let name = library.adjacentFileName, rewritten.insert(name).inserted else { continue }
                let changeResult = try await shell.execute([
                    "/usr/bin/install_name_tool",
                    "-change", library.installName,
                    "@rpath/\(name)",
                    stagingURL.path,
                ])
                guard changeResult.success else {
                    throw cleanupAndThrow(
                        .companionRewriteFailed(
                            "install_name_tool -change \(library.installName) -> @rpath/\(name): \(changeResult.output)"
                        )
                    )
                }
            }
            for entry in try await loadRpaths(at: stagingURL) {
                let deleteResult = try await shell.execute([
                    "/usr/bin/install_name_tool", "-delete_rpath", entry.path, stagingURL.path,
                ])
                guard deleteResult.success else {
                    throw cleanupAndThrow(
                        .companionRewriteFailed("install_name_tool -delete_rpath \(entry.path): \(deleteResult.output)")
                    )
                }
            }
            let addRpath = try await shell.execute([
                "/usr/bin/install_name_tool", "-add_rpath", generation.rpath, stagingURL.path,
            ])
            guard addRpath.success else {
                throw cleanupAndThrow(
                    .companionRewriteFailed("install_name_tool -add_rpath \(generation.rpath): \(addRpath.output)")
                )
            }
        }

        // 5c. Re-sign the staged executable after the rewrite.
        let resignResult = try await shell.execute(["codesign", "--force", "--sign", "-", stagingURL.path])
        guard resignResult.success else {
            throw cleanupAndThrow(.signingFailed(resignResult.output))
        }

        // 6. Strict verification before anything is published.
        let verifyResult = try await shell.execute(["codesign", "--verify", "--strict", stagingURL.path])
        guard verifyResult.success else {
            throw cleanupAndThrow(.verificationFailed(verifyResult.output))
        }
        // The rewrite must actually be present in the staged binary.
        if let generation {
            let stagedRpaths = try await loadRpaths(at: stagingURL)
            guard stagedRpaths.map(\.path).contains(generation.rpath) else {
                throw cleanupAndThrow(
                    .companionRewriteFailed("staged executable does not declare \(generation.rpath)")
                )
            }
        }
        // codesign --force replaces the file it signs (fresh inode); capture
        // the signed inode here — it is what the rename below publishes.
        let signedInode = inodeNumber(at: stagingURL)

        // 7. Atomic publish. Companions rename WITHIN the generation
        //    directory (invisible at dest until the executable switch);
        //    previous dest inode is hard-linked aside so the live path
        //    never disappears. `rename(2)` onto the existing path is the
        //    single generation switch (PR #88 / HAB-628 / HAB-629).
        let publishedCompanions: [PublishedCompanion]
        do {
            publishedCompanions = try publishCompanions(companions, stagedURLs: &stagedURLs)
        } catch let error as InstallError {
            throw cleanupAndThrow(error)
        } catch {
            throw cleanupAndThrow(.publishFailed(error.localizedDescription))
        }

        let previousInode = inodeNumber(at: destination)
        let parkedDestination: PublishedCompanion
        do {
            parkedDestination = try parkDestination(destination)
        } catch let error as InstallError {
            rollbackPublishedCompanions(publishedCompanions)
            throw cleanupAndThrow(error)
        } catch {
            rollbackPublishedCompanions(publishedCompanions)
            throw cleanupAndThrow(.publishFailed(error.localizedDescription))
        }

        let renameResult = renamePaths(stagingURL.path, destination.path)
        guard renameResult == 0 else {
            let detail = String(cString: strerror(errno))
            rollbackPublishedCompanions(publishedCompanions + [parkedDestination])
            throw cleanupAndThrow(.publishFailed("rename(\(stagingURL.path) -> \(destination.path)): \(detail)"))
        }
        stagedURLs.removeAll { $0 == stagingURL }
        let publishedInode = inodeNumber(at: destination)
        let bytes = ((try? fileManager.attributesOfItem(atPath: destination.path))?[.size] as? Int) ?? 0

        // 8. Post-publish verification. Backups stay until dest AND each
        //    published companion verify so a failed dest or companion
        //    check can restore dest + companions (HAB-629 / HAB-631).
        let postVerify = try await shell.execute(["codesign", "--verify", "--strict", destination.path])
        guard postVerify.success, publishedInode == signedInode else {
            rollbackPublishedCompanions(publishedCompanions + [parkedDestination])
            throw cleanupAndThrow(
                .postPublishVerificationFailed(
                    "publish sanity failed (verify.success=\(postVerify.success), " +
                        "published=\(publishedInode.map(String.init) ?? "nil") signed=\(signedInode.map(String.init) ?? "nil")): \(postVerify.output)"
                )
            )
        }
        for companion in publishedCompanions {
            let companionVerify = try await shell.execute([
                "codesign", "--verify", "--strict", companion.destinationURL.path,
            ])
            guard companionVerify.success else {
                rollbackPublishedCompanions(publishedCompanions + [parkedDestination])
                throw cleanupAndThrow(
                    .postPublishVerificationFailed(
                        "\(companion.fileName): \(companionVerify.output)"
                    )
                )
            }
        }
        // The published executable must carry the generation rpath — the
        // switch is only meaningful if it actually points at the gen dir.
        if let generation {
            let destRpaths = try await loadRpaths(at: destination)
            guard destRpaths.map(\.path).contains(generation.rpath) else {
                rollbackPublishedCompanions(publishedCompanions + [parkedDestination])
                throw cleanupAndThrow(
                    .postPublishVerificationFailed(
                        "published executable lost its \(generation.rpath) entry"
                    )
                )
            }
        }
        dropCompanionBackups(publishedCompanions + [parkedDestination])

        // 9. Success: previous generations are dead. The old executable is
        //    gone from dest, so nothing can resolve into them. Remove the
        //    old generation directories (best-effort — an orphaned hidden
        //    dir is inert, never observable as a mixed generation).
        if let generation {
            sweepStaleGenerationDirectories(
                around: destination,
                keeping: generation.directoryURL
            )
        }

        return Report(
            source: source.path,
            destination: destination.path,
            signedInode: signedInode ?? 0,
            previousDestinationInode: previousInode,
            publishedInode: publishedInode ?? 0,
            bytes: bytes,
            companionDylibs: companions.map(\.fileName),
            companionDirectory: generation?.directoryURL.lastPathComponent
        )
    }

    /// Remove other `.<execname>.companions.*` directories beside the
    /// destination. Only called after the new generation is live and
    /// verified — old generations are unreachable by then.
    private func sweepStaleGenerationDirectories(around destination: URL, keeping current: URL) {
        let destinationDirectory = destination.deletingLastPathComponent()
        let prefix = ".\(destination.lastPathComponent).companions."
        let currentName = current.lastPathComponent
        let candidates = (try? fileManager.contentsOfDirectory(atPath: destinationDirectory.path)) ?? []
        for name in candidates where name.hasPrefix(prefix) {
            guard name != currentName else { continue }
            try? fileManager.removeItem(at: destinationDirectory.appendingPathComponent(name))
        }
    }

    private func inodeNumber(at url: URL) -> UInt64? {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.systemFileNumber] as? Int).map(UInt64.init)
    }

    private func loadLinkedLibraries(at staged: URL) async throws -> [LinkedLibrary] {
        let result = try await shell.execute(["/usr/bin/otool", "-L", staged.path])
        guard result.success else {
            throw InstallError.linkedLibraryInspectionFailed(result.output)
        }
        return Self.parseOtoolL(result.output)
    }

    /// Declared `LC_RPATH` entries of a Mach-O (`otool -l`).
    private func loadRpaths(at url: URL) async throws -> [RpathEntry] {
        try await Self.loadRpaths(at: url, shell: shell)
    }

    /// Declared `LC_RPATH` entries of a Mach-O via `otool -l` (shared with
    /// `AppBundleInstaller`, which stages the same companion set).
    public static func loadRpaths(
        at url: URL,
        shell: any ShellExecuting
    ) async throws -> [RpathEntry] {
        let result = try await shell.execute(["/usr/bin/otool", "-l", url.path])
        guard result.success else {
            throw InstallError.linkedLibraryInspectionFailed(result.output)
        }
        return Self.parseOtoolRpaths(result.output)
    }

    /// PR #88 (Codex thread, BinaryInstaller:158): `@rpath/<name>` loads used
    /// to be flattened into "copy the dylib beside the executable" without
    /// ever reading the declared `LC_RPATH` entries. When the real rpath
    /// points anywhere but beside the executable (`@executable_path/../lib`,
    /// an absolute path, …), dyld resolves the load somewhere this layout
    /// never puts the file — either the launch fails or a *different*
    /// dylib is loaded than the source layout shipped. Fail closed, naming
    /// the rpath, instead of silently flattening.
    ///
    /// Only images that actually require an `@rpath` load are constrained:
    /// `@loader_path/…` / `@executable_path/…` loads never consult rpaths.
    /// Every declared entry must be adjacent — honoring a subset would be
    /// the same silent flattening in disguise.
    public static func validateAdjacentRpaths(
        of libraries: [LinkedLibrary],
        at url: URL,
        fileName: String,
        shell: any ShellExecuting
    ) async throws {
        let ownName = url.lastPathComponent
        let requiresRpath = libraries.contains { library in
            guard !library.isWeak, library.installName.hasPrefix("@rpath/") else { return false }
            // `otool -L` echoes a dylib's own install name (LC_ID_DYLIB) as
            // an entry. dyld never resolves an image's own ID — that entry
            // describes the image itself — so it imposes no rpath
            // requirement. Only genuine loads of OTHER images do.
            return library.adjacentFileName != ownName
        }
        guard requiresRpath else { return }
        let rpaths = try await loadRpaths(at: url, shell: shell)
        guard !rpaths.isEmpty else {
            throw InstallError.rpathUnsupported(
                detail: "\(fileName) requires an @rpath load but declares no LC_RPATH",
                rpath: "(none declared)"
            )
        }
        for entry in rpaths where !isAdjacentRpath(entry.path) {
            throw InstallError.rpathUnsupported(
                detail:
                "\(fileName) requires @rpath loads; honoring \(entry.path) would place the dylib somewhere other than beside the executable",
                rpath: entry.path
            )
        }
    }

    private func validateAdjacentRpaths(
        of libraries: [LinkedLibrary],
        at url: URL,
        fileName: String
    ) async throws {
        try await Self.validateAdjacentRpaths(
            of: libraries,
            at: url,
            fileName: fileName,
            shell: shell
        )
    }

    /// Walk source-adjacent companions and union their load commands.
    ///
    /// HAB-625 only inspected the staged executable. A dylib that itself
    /// requires `@loader_path/libnested.dylib` would then publish without
    /// the nested file (or succeed when the nested file is missing). BFS
    /// over adjacent names, skipping missing source files (dest-adjacent
    /// leftovers still satisfy `requiredLibraryGaps`).
    private func expandLinkedLibraries(
        initial: [LinkedLibrary],
        sourceDirectory: URL,
        executableURL: URL
    ) async throws -> [LinkedLibrary] {
        var all = initial
        var seen: Set<String> = []
        var queue: [String] = []
        func enqueue(_ libraries: [LinkedLibrary]) {
            for library in libraries {
                if library.isWeak {
                    continue
                }
                guard let name = library.adjacentFileName else { continue }
                if seen.insert(name).inserted {
                    queue.append(name)
                }
            }
        }
        enqueue(initial)
        // The staged executable itself must satisfy the rpath law (PR #88).
        try await validateAdjacentRpaths(
            of: initial,
            at: executableURL,
            fileName: executableURL.lastPathComponent
        )
        var index = 0
        while index < queue.count {
            let name = queue[index]
            index += 1
            let sourceURL = sourceDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            let nested = try await loadLinkedLibraries(at: sourceURL)
            // Every source-adjacent image that joins the set must satisfy
            // the same law (PR #88).
            try await validateAdjacentRpaths(of: nested, at: sourceURL, fileName: name)
            all.append(contentsOf: nested)
            enqueue(nested)
        }
        return all
    }

    /// All distinct non-weak adjacent companion names a set of loads
    /// requires, in first-observation order.
    static func requiredCompanionNames(_ libraries: [LinkedLibrary]) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for library in libraries {
            if library.isWeak {
                continue
            }
            guard let name = library.adjacentFileName else { continue }
            if seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names
    }

    /// Stage every required companion into the generation directory.
    ///
    /// Each name resolves from the first location that has it: the source
    /// directory (this build ships it), the previous generation directory,
    /// or the legacy flat destination layout (pre-#88 installs). Reused
    /// files are strict-verified before being copied — a name existing is
    /// not a signature (HAB-631 law, carried into generations).
    private func stageCompanions(
        names: [String],
        sourceDirectory: URL,
        destinationDirectory: URL,
        previousGenerationDirectory: URL?,
        generation: CompanionGeneration,
        stagedURLs: inout [URL]
    ) async throws -> [PlannedCompanion] {
        var planned: [PlannedCompanion] = []
        for name in names {
            let sourceURL = sourceDirectory.appendingPathComponent(name)
            let previousGenURL = previousGenerationDirectory?.appendingPathComponent(name)
            let legacyDestURL = destinationDirectory.appendingPathComponent(name)
            let resolvedSource: URL?
            if fileManager.fileExists(atPath: sourceURL.path) {
                resolvedSource = sourceURL
            } else if let previousGenURL, fileManager.fileExists(atPath: previousGenURL.path) {
                resolvedSource = previousGenURL
            } else if fileManager.fileExists(atPath: legacyDestURL.path) {
                resolvedSource = legacyDestURL
            } else {
                continue
            }
            let resolved = resolvedSource!
            // Directly to the FINAL name inside the generation directory.
            // The directory itself is hidden and freshly created — nothing
            // outside this transaction can observe these files, and the
            // whole generation switches atomically with the executable
            // rename. No publish/park dance needed inside it.
            let destinationInGeneration = generation.directoryURL.appendingPathComponent(name)
            do {
                try fileManager.copyItem(at: resolved, to: destinationInGeneration)
            } catch {
                throw InstallError.stagingFailed("\(name): \(error.localizedDescription)")
            }
            do {
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationInGeneration.path)
            } catch {
                throw InstallError.chmodFailed("\(name): \(error.localizedDescription)")
            }
            planned.append(
                PlannedCompanion(
                    fileName: name,
                    sourceURL: resolved,
                    stagingURL: destinationInGeneration,
                    destinationURL: destinationInGeneration
                )
            )
        }
        return planned
    }

    private struct PublishedCompanion {
        let fileName: String
        let destinationURL: URL
        let backupURL: URL?
    }

    /// PR #88: companions are staged at their FINAL names inside the fresh
    /// hidden generation directory, so publishing is just recording them —
    /// no parking, no per-file renames. The directory as a whole becomes
    /// reachable only when the executable rename switches generations.
    /// Kept as a seam so post-publish verification has a uniform record.
    private func publishCompanions(
        _ companions: [PlannedCompanion],
        stagedURLs: inout [URL]
    ) throws -> [PublishedCompanion] {
        _ = stagedURLs
        return companions.map { companion in
            PublishedCompanion(
                fileName: companion.fileName,
                destinationURL: companion.destinationURL,
                backupURL: nil
            )
        }
    }

    /// Park the previous dest executable so a failed binary rename or
    /// post-publish verify can restore it (HAB-629).
    private func parkDestination(_ destination: URL) throws -> PublishedCompanion {
        let backupURL = try parkExistingCompanion(
            destination,
            fileName: destination.lastPathComponent
        )
        return PublishedCompanion(
            fileName: destination.lastPathComponent,
            destinationURL: destination,
            backupURL: backupURL
        )
    }

    /// Hard-link the live file aside. `rename(2)` of the live path would make
    /// the installed command vanish until the later publish rename (ENOENT).
    /// The extra link keeps that inode at the destination the whole time.
    private func parkExistingCompanion(_ destinationURL: URL, fileName: String) throws -> URL? {
        guard fileManager.fileExists(atPath: destinationURL.path) else { return nil }
        let backupURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileName).rollback-\(UUID().uuidString).tmp")
        let result = link(destinationURL.path, backupURL.path)
        guard result == 0 else {
            let detail = String(cString: strerror(errno))
            throw InstallError.publishFailed(
                "link(\(destinationURL.path) -> \(backupURL.path)): \(detail)"
            )
        }
        return backupURL
    }

    /// Restore a previous inode without unlinking the live path first.
    /// Same-inode backup means publish never replaced dest — drop the extra link.
    private func rollbackPublishedCompanions(_ published: [PublishedCompanion]) {
        for item in published.reversed() {
            guard let backup = item.backupURL, fileManager.fileExists(atPath: backup.path) else {
                if fileManager.fileExists(atPath: item.destinationURL.path) {
                    try? fileManager.removeItem(at: item.destinationURL)
                }
                continue
            }
            let destInode = inodeNumber(at: item.destinationURL)
            let backupInode = inodeNumber(at: backup)
            if destInode != nil, destInode == backupInode {
                try? fileManager.removeItem(at: backup)
                continue
            }
            if renamePaths(backup.path, item.destinationURL.path) != 0 {
                try? fileManager.removeItem(at: item.destinationURL)
                _ = renamePaths(backup.path, item.destinationURL.path)
            }
        }
    }

    /// After post-publish verify succeeds, parked previous dest + companions
    /// are no longer needed.
    private func dropCompanionBackups(_ published: [PublishedCompanion]) {
        for item in published {
            if let backup = item.backupURL {
                try? fileManager.removeItem(at: backup)
            }
        }
    }

    /// Parse `otool -L` stdout into load commands. Header lines (`path:`) skipped.
    public static func parseOtoolL(_ output: String) -> [LinkedLibrary] {
        var libraries: [LinkedLibrary] = []
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                continue
            }
            if line.hasSuffix(":") {
                continue
            }
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

    /// One `LC_RPATH` load command from `otool -l` stdout.
    public struct RpathEntry: Sendable, Equatable {
        public let path: String
    }

    /// Parse `otool -l` stdout into its `LC_RPATH` path strings, preserving
    /// declaration order. Each entry looks like:
    ///
    ///     Load command N
    ///       cmd LC_RPATH
    ///       cmdsize 32
    ///       path @executable_path/../lib (offset 12)
    public static func parseOtoolRpaths(_ output: String) -> [RpathEntry] {
        var rpaths: [RpathEntry] = []
        var pendingIsRpath = false
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "cmd LC_RPATH" {
                pendingIsRpath = true
                continue
            }
            guard pendingIsRpath, line.hasPrefix("path ") else { continue }
            // "path @executable_path/../lib (offset 12)"
            let rest = line.dropFirst("path ".count)
            let paren = rest.firstIndex(of: "(")
            let value = (paren.map { rest[..<$0] } ?? rest)
                .trimmingCharacters(in: .whitespaces)
            pendingIsRpath = false
            guard !value.isEmpty else { continue }
            rpaths.append(RpathEntry(path: value))
        }
        return rpaths
    }

    /// An rpath this installer can reproduce: bare `@executable_path` /
    /// `@loader_path` resolve beside the executable, exactly where
    /// companions are published. Anything else — a `../` climb, another
    /// prefix, an absolute path — would place the dylib somewhere this
    /// layout does not put it, so honoring the real rpath is impossible
    /// and flattening it to "beside the executable" would lie to dyld
    /// about where the library lives.
    public static func isAdjacentRpath(_ rpath: String) -> Bool {
        rpath == "@executable_path" || rpath == "@loader_path"
    }

    /// A dest-adjacent dylib that the source does not ship is still part of the
    /// published generation. Existence is not a signature. Verify it, and walk
    /// its nested required loads, before publish.
    ///
    /// PR #88: reused files live in the previous generation directory (new
    /// layout) or flat beside the destination (pre-#88 layout). Either way
    /// they are strict-verified in place; the new generation stages copies.
    private func verifyReusedDestinationCompanions(
        libraries: [LinkedLibrary],
        sourceDirectory: URL,
        destinationDirectory: URL,
        previousGenerationDirectory: URL?
    ) async throws {
        /// First existing host path for a required adjacent name outside the
        /// source directory — previous generation first, legacy flat second.
        func reusedURL(for name: String) -> URL? {
            if let previousGenerationDirectory {
                let url = previousGenerationDirectory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: url.path) {
                    return url
                }
            }
            let flat = destinationDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: flat.path) {
                return flat
            }
            return nil
        }

        var seen: Set<String> = []
        var queue: [String] = []
        func enqueueReused(_ libraries: [LinkedLibrary]) {
            for library in libraries where !library.isWeak {
                guard let name = library.adjacentFileName else { continue }
                let sourceURL = sourceDirectory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: sourceURL.path) {
                    continue
                }
                guard reusedURL(for: name) != nil else { continue }
                if seen.insert(name).inserted {
                    queue.append(name)
                }
            }
        }
        enqueueReused(libraries)
        var index = 0
        while index < queue.count {
            let name = queue[index]
            index += 1
            guard let reused = reusedURL(for: name) else { continue }
            let verify = try await shell.execute(["codesign", "--verify", "--strict", reused.path])
            guard verify.success else {
                throw InstallError.verificationFailed("reused \(name): \(verify.output)")
            }
            let nested = try await loadLinkedLibraries(at: reused)
            // A reused dest companion with @rpath loads must satisfy the
            // same adjacent-rpath law (PR #88) — it joins the published set.
            try await validateAdjacentRpaths(of: nested, at: reused, fileName: "reused \(name)")
            for library in nested where !library.isWeak {
                guard let nestedName = library.adjacentFileName else { continue }
                let nestedSource = sourceDirectory.appendingPathComponent(nestedName)
                let nestedReuse = reusedURL(for: nestedName)
                guard fileManager.fileExists(atPath: nestedSource.path) || nestedReuse != nil else {
                    throw InstallError.missingRequiredLinkedLibrary(
                        "reused \(name) requires \(library.installName)"
                    )
                }
                if nestedReuse != nil, !fileManager.fileExists(atPath: nestedSource.path),
                   seen.insert(nestedName).inserted
                {
                    queue.append(nestedName)
                }
            }
        }
    }

    /// The generation directory a set of declared rpaths points at, if any
    /// (`@loader_path/.<execname>.companions.<gen>` where the directory
    /// exists). Pure — the otool call lives in the actor. The old
    /// executable keeps resolving its own generation after the switch;
    /// this is where its companions actually live.
    static func generationDirectory(
        from rpaths: [RpathEntry],
        destinationDirectory: URL,
        fileExists: (String) -> Bool
    ) -> URL? {
        for entry in rpaths {
            guard entry.path.hasPrefix("@loader_path/") else { continue }
            let relative = String(entry.path.dropFirst("@loader_path/".count))
            let directory = destinationDirectory.appendingPathComponent(relative)
            if fileExists(directory.path) {
                return directory
            }
        }
        return nil
    }

    /// Required (non-weak) libraries that would not resolve after publish.
    /// Adjacent names may be satisfied by the source directory (copied in
    /// HAB-626) or by an already-installed companion next to the destination.
    public static func requiredLibraryGaps(
        _ libraries: [LinkedLibrary],
        adjacentDirectory: URL,
        sourceDirectory: URL? = nil,
        fileExists: (String) -> Bool
    ) -> [LinkedLibrary] {
        libraries.filter { library in
            if library.isWeak {
                return false
            }
            if library.isSystem {
                return false
            }
            if let name = library.adjacentFileName {
                if let sourceDirectory {
                    let sourceAdjacent = sourceDirectory.appendingPathComponent(name)
                    if fileExists(sourceAdjacent.path) {
                        return false
                    }
                }
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
