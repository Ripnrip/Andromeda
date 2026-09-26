import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// Fail-closed LaunchAgent install: rewrite Studio HOME template, write the
/// plist, optionally `bootstrap` (legacy `load` fallback). Kickstart is opt-in.
///
/// BIN-101 leftover · HAB-622 / HAB-632. Companion to `BinaryInstaller`
/// (HAB-618) and `AppBundleInstaller` (HAB-621). `scripts/install-and-sign.sh`
/// rendered `/Users/admin` → `$HOME` then `bootout`+`bootstrap` then
/// `kickstart -k`. launchd does **not** expand `$HOME`/`~`, so every path in
/// the plist must be absolute after rewrite.
///
/// This type keeps the rewrite + bootstrap contract and **does not** kickstart
/// unless `Spec.kickstart` is true. Heartbeat cron must never pass kickstart
/// (AGENTS.md: no invisible launchd jobs; do not kickstart live HUD).
///
/// Destination is caller-chosen. Tests and CLI never default to
/// `~/Library/LaunchAgents`. The previous dest plist is parked before
/// publish; a failed `bootstrap`+`load` restores that inode (or leaves dest
/// absent on a fresh install) so dest never keeps a new plist that launchd
/// refused (HAB-632, HAB-629 leftover). File-level restore only — cron does
/// not re-bootstrap the previous job.
///
/// `launchctl bootstrap` can return 0 even when Program/ProgramArguments[0]
/// is missing; launchd then exec-fails (KeepAlive hammers). HAB-632 does
/// not cover that — it only restores on bootstrap+load *command* failure.
/// When `Spec.bootstrap` is true, the rendered Program path must be an
/// absolute existing executable before dest is parked (HAB-676). If that
/// Program is a Mach-O, it must also pass `codesign --verify --strict`
/// (HAB-677): unsigned Mach-O is Taskgated SIGKILL (HAB-606) and KeepAlive
/// (mcp-hub) hammers. Required `@rpath` / `@loader_path` / `@executable_path`
/// dylibs (and nested adjacent names) must exist next to Program (HAB-678):
/// a signed Mach-O with a missing companion still dyld-fails after a
/// successful bootstrap. Those companions must themselves pass
/// `codesign --verify --strict` (HAB-680): an unsigned adjacent dylib still
/// library-validation / Taskgated-fails after bootstrap. Scripts/shebangs
/// are not Mach-O and stay allowed. Signature + `otool -L` use
/// `/usr/bin/codesign` and `/usr/bin/otool` directly — not the injected
/// `ShellExecuting` (that mock is for launchctl). If the rendered plist
/// has `WorkingDirectory`, that path must be an absolute existing
/// directory before dest is parked (HAB-681): bootstrap can still return 0
/// when chdir would fail, then KeepAlive (mcp-hub) hammers. Missing key
/// is allowed (launchd defaults to `/`). If `StandardOutPath` /
/// `StandardErrorPath` is present it must be absolute and must not be an
/// existing directory (HAB-682): bootstrap can return 0 when launchd
/// cannot open the log file (relative path — launchd does not expand
/// `$HOME`/`~` — or a directory). Missing keys allowed. If
/// `StandardInPath` is present it must be an absolute existing
/// non-directory file (HAB-692): bootstrap can return 0 when launchd
/// cannot open stdin (relative path — launchd does not expand
/// `$HOME`/`~` — missing file, or a directory). Missing key allowed. If
/// `EnvironmentVariables.HOME` is present it must be an absolute existing
/// directory (HAB-683): bootstrap can return 0 when HOME is relative
/// (launchd does not expand `$HOME`/`~`), missing, or a file; the job
/// then runs with a broken HOME and KeepAlive (mcp-hub) hammers. Missing
/// key allowed. If `EnvironmentVariables.PATH` is present, every
/// colon-separated component must be an absolute path (HAB-684): bootstrap
/// can return 0 when PATH contains relative, empty, `$HOME`, or `~`
/// components (launchd does not expand them); child lookups then fail and
/// KeepAlive (mcp-hub) hammers. Components are not required to exist
/// (Homebrew / isolated homes). Missing key allowed. `/usr/bin/open` is
/// refused on bootstrap (HAB-686): LaunchServices `open -a` can inherit
/// Aqua/agent-shell env (paid API keys). ops/*.plist forbid it; a signed
/// system `open` would otherwise pass HAB-676/677/678/680. `/usr/bin/osascript`
/// is refused on bootstrap (HAB-687): it is the same class of signed system
/// Mach-O (system dylibs only) and inherits Aqua/agent-shell env to run
/// AppleScript. Rewrite-only (`bootstrap` false) stays a dry-run and does
/// not require the binary, its dylibs, WorkingDirectory, log paths, HOME,
/// PATH, reject `open`/`osascript`, reject StandardInPath, or reject paid API keys. HAB-688 also refuses those
/// binaries in any ProgramArguments slot (and a separate Program key),
/// so `/usr/bin/arch` / `/usr/bin/env` trampolines cannot wrap them.
/// Paid provider API keys in EnvironmentVariables are refused on
/// bootstrap (HAB-689): `ops/com.andromeda.hud.plist` is local-only
/// (`OPENROUTER_*`, `ANTHROPIC_*`, paid keys). `launchctl bootstrap`
/// can return 0 while injecting those keys into the job env (spend +
/// leak). HOME/PATH/LANG stay allowed. `DYLD_*` EnvironmentVariables
/// are refused on bootstrap (HAB-690): ad-hoc signed Program /
/// companions (HAB-677/680) are not restricted, so
/// `DYLD_INSERT_LIBRARIES` / search-path keys hijack the image after
/// codesign passed. StandardInPath is checked on bootstrap (HAB-692).
/// If `RootDirectory` is present it must be an absolute existing
/// directory (HAB-693): bootstrap can return 0 when chroot would fail
/// (relative path — launchd does not expand `$HOME`/`~` — missing, or
/// a file). Missing key allowed (no chroot). If
/// `EnvironmentVariables.TMPDIR` is present it must be an absolute
/// existing directory (HAB-695): bootstrap can return 0 when TMPDIR is
/// relative (launchd does not expand `$HOME`/`~`), missing, or a file;
/// libc tempfile then fails and KeepAlive (mcp-hub) hammers. Missing
/// key allowed (OS default). If `WatchPaths` is present, each entry
/// must be an absolute existing path (HAB-702): bootstrap can return 0
/// when a watch path is relative (launchd does not expand `$HOME`/`~`)
/// or missing, so the job never fires on the intended path. Files and
/// directories are allowed. Missing key / empty array allowed. If
/// `QueueDirectories` is present, each entry must be an absolute
/// existing directory (HAB-702): bootstrap can return 0 when a queue
/// directory is relative, missing, or a file; launchd then never
/// drains the queue. Missing key / empty array allowed. Rewrite-only
/// unchanged.
public actor LaunchAgentInstaller {

    /// Studio SoT template home baked into `ops/*.plist`.
    public static let studioHomeTemplate = "/Users/admin"

    public struct Spec: Sendable {
        public var label: String?
        public var home: String
        public var uid: UInt32
        public var bootstrap: Bool
        public var kickstart: Bool

        public init(
            label: String? = nil,
            home: String,
            uid: UInt32,
            bootstrap: Bool = false,
            kickstart: Bool = false
        ) {
            self.label = label
            self.home = home
            self.uid = uid
            self.bootstrap = bootstrap
            self.kickstart = kickstart
        }
    }

    public struct Report: Sendable, CustomStringConvertible {
        public let source: String
        public let destination: String
        public let label: String
        public let domain: String
        public let home: String
        public let rewritten: Bool
        public let bootstrapped: Bool
        public let usedLegacyLoad: Bool
        public let kickstarted: Bool

        public var description: String {
            """
            install-launch-agent report
              source:       \(source)
              destination:  \(destination)
              label:        \(label)
              domain:       \(domain)
              home:         \(home)
              rewritten:    \(rewritten)
              bootstrapped: \(bootstrapped)
              legacy load:  \(usedLegacyLoad)
              kickstarted:  \(kickstarted)
            """
        }
    }

    public enum InstallError: Error, CustomStringConvertible, Sendable {
        case sourceMissing(String)
        case homeNotAbsolute(String)
        case templateMissing(studio: String, source: String)
        case plistUnreadable(String)
        case labelMissing
        case labelMismatch(expected: String, found: String)
        case destinationIsDirectory(String)
        case writeFailed(String)
        case logDirectoryFailed(String)
        case kickstartWithoutBootstrap
        case bootstrapFailed(String)
        case programMissing(String)
        case programNotAbsolute(String)
        case programNotExecutable(String)
        case programNotSigned(String)
        case programLibraryInspectionFailed(String)
        case programMissingLibraries(String)
        case programUnsignedLibraries(String)
        case workingDirectoryNotAbsolute(String)
        case workingDirectoryMissing(String)
        case workingDirectoryNotDirectory(String)
        case rootDirectoryNotAbsolute(String)
        case rootDirectoryMissing(String)
        case rootDirectoryNotDirectory(String)
        case logPathNotAbsolute(String)
        case logPathIsDirectory(String)
        case standardInPathNotAbsolute(String)
        case standardInPathMissing(String)
        case standardInPathIsDirectory(String)
        case environmentHomeNotAbsolute(String)
        case environmentHomeMissing(String)
        case environmentHomeNotDirectory(String)
        case environmentTmpdirNotAbsolute(String)
        case environmentTmpdirMissing(String)
        case environmentTmpdirNotDirectory(String)
        case watchPathNotAbsolute(String)
        case watchPathMissing(String)
        case queueDirectoryNotAbsolute(String)
        case queueDirectoryMissing(String)
        case queueDirectoryNotDirectory(String)
        case environmentPathNotAbsolute(String)
        case programUsesOpen(String)
        case programUsesOsascript(String)
        case environmentPaidApiKey(String)
        case environmentDyldInjection(String)

        public var description: String {
            switch self {
            case .sourceMissing(let path):
                "Source plist not found: \(path)"
            case .homeNotAbsolute(let home):
                "HOME must be an absolute path (launchd does not expand $HOME/~): \(home)"
            case .templateMissing(let studio, let source):
                "Plist missing studio HOME template \(studio): \(source)"
            case .plistUnreadable(let detail):
                "Could not parse rendered plist: \(detail)"
            case .labelMissing:
                "Rendered plist has no Label"
            case .labelMismatch(let expected, let found):
                "Plist Label \(found) does not match requested label \(expected)"
            case .destinationIsDirectory(let path):
                "Destination exists and is a directory: \(path)"
            case .writeFailed(let detail):
                "Failed to write rendered plist (destination restored): \(detail)"
            case .logDirectoryFailed(let detail):
                "Failed to create log directory: \(detail)"
            case .kickstartWithoutBootstrap:
                "kickstart requires bootstrap (refusing to kickstart an unregistered job)"
            case .bootstrapFailed(let detail):
                "launchctl bootstrap/load failed (destination restored): \(detail)"
            case .programMissing(let path):
                "LaunchAgent Program does not exist (destination untouched): \(path)"
            case .programNotAbsolute(let path):
                "LaunchAgent Program must be an absolute path (launchd does not expand $HOME/~): \(path)"
            case .programNotExecutable(let path):
                "LaunchAgent Program is not executable (destination untouched): \(path)"
            case .programNotSigned(let path):
                "LaunchAgent Program failed codesign --verify --strict (destination untouched): \(path)"
            case .programLibraryInspectionFailed(let detail):
                "Could not inspect LaunchAgent Program linked libraries (destination untouched): \(detail)"
            case .programMissingLibraries(let detail):
                "LaunchAgent Program is missing a required non-system dylib (destination untouched): \(detail)"
            case .programUnsignedLibraries(let detail):
                "LaunchAgent Program companion dylib failed codesign --verify --strict (destination untouched): \(detail)"
            case .workingDirectoryNotAbsolute(let path):
                "LaunchAgent WorkingDirectory must be an absolute path (launchd does not expand $HOME/~): \(path)"
            case .workingDirectoryMissing(let path):
                "LaunchAgent WorkingDirectory does not exist (destination untouched): \(path)"
            case .workingDirectoryNotDirectory(let path):
                "LaunchAgent WorkingDirectory is not a directory (destination untouched): \(path)"
            case .rootDirectoryNotAbsolute(let path):
                "LaunchAgent RootDirectory must be an absolute path (launchd does not expand $HOME/~): \(path)"
            case .rootDirectoryMissing(let path):
                "LaunchAgent RootDirectory does not exist (destination untouched): \(path)"
            case .rootDirectoryNotDirectory(let path):
                "LaunchAgent RootDirectory is not a directory (destination untouched): \(path)"
            case .logPathNotAbsolute(let path):
                "LaunchAgent StandardOutPath/StandardErrorPath must be an absolute path (launchd does not expand $HOME/~): \(path)"
            case .logPathIsDirectory(let path):
                "LaunchAgent StandardOutPath/StandardErrorPath is a directory (destination untouched): \(path)"
            case .standardInPathNotAbsolute(let path):
                "LaunchAgent StandardInPath must be an absolute path (launchd does not expand $HOME/~): \(path)"
            case .standardInPathMissing(let path):
                "LaunchAgent StandardInPath does not exist (destination untouched): \(path)"
            case .standardInPathIsDirectory(let path):
                "LaunchAgent StandardInPath is a directory (destination untouched): \(path)"
            case .environmentHomeNotAbsolute(let path):
                "LaunchAgent EnvironmentVariables.HOME must be an absolute path (launchd does not expand $HOME/~): \(path)"
            case .environmentHomeMissing(let path):
                "LaunchAgent EnvironmentVariables.HOME does not exist (destination untouched): \(path)"
            case .environmentHomeNotDirectory(let path):
                "LaunchAgent EnvironmentVariables.HOME is not a directory (destination untouched): \(path)"
            case .environmentTmpdirNotAbsolute(let path):
                "LaunchAgent EnvironmentVariables.TMPDIR must be an absolute path (launchd does not expand $HOME/~): \(path)"
            case .environmentTmpdirMissing(let path):
                "LaunchAgent EnvironmentVariables.TMPDIR does not exist (destination untouched): \(path)"
            case .environmentTmpdirNotDirectory(let path):
                "LaunchAgent EnvironmentVariables.TMPDIR is not a directory (destination untouched): \(path)"
            case .watchPathNotAbsolute(let path):
                "LaunchAgent WatchPaths entry must be an absolute path (launchd does not expand $HOME/~): \(path)"
            case .watchPathMissing(let path):
                "LaunchAgent WatchPaths entry does not exist (destination untouched): \(path)"
            case .queueDirectoryNotAbsolute(let path):
                "LaunchAgent QueueDirectories entry must be an absolute path (launchd does not expand $HOME/~): \(path)"
            case .queueDirectoryMissing(let path):
                "LaunchAgent QueueDirectories entry does not exist (destination untouched): \(path)"
            case .queueDirectoryNotDirectory(let path):
                "LaunchAgent QueueDirectories entry is not a directory (destination untouched): \(path)"
            case .environmentPathNotAbsolute(let path):
                "LaunchAgent EnvironmentVariables.PATH component must be an absolute path (launchd does not expand $HOME/~): \(path)"
            case .programUsesOpen(let path):
                "LaunchAgent Program/ProgramArguments must not include /usr/bin/open (LaunchServices open -a inherits Aqua/agent-shell env): \(path)"
            case .programUsesOsascript(let path):
                "LaunchAgent Program/ProgramArguments must not include /usr/bin/osascript (osascript inherits Aqua/agent-shell env): \(path)"
            case .environmentPaidApiKey(let keys):
                "LaunchAgent EnvironmentVariables must not include paid provider API keys (destination untouched): \(keys)"
            case .environmentDyldInjection(let keys):
                "LaunchAgent EnvironmentVariables must not include DYLD_* keys (destination untouched): \(keys)"
            }
        }
    }

    private let shell: any ShellExecuting
    private let fileManager: FileManager

    public init(
        shell: any ShellExecuting = LiveShell(),
        fileManager: FileManager = .default
    ) {
        self.shell = shell
        self.fileManager = fileManager
    }

    /// Render, write, and optionally bootstrap a LaunchAgent plist.
    public func install(source: URL, destination: URL, spec: Spec) async throws -> Report {
        guard spec.home.hasPrefix("/") else {
            throw InstallError.homeNotAbsolute(spec.home)
        }
        if spec.kickstart && !spec.bootstrap {
            throw InstallError.kickstartWithoutBootstrap
        }
        guard fileManager.fileExists(atPath: source.path) else {
            throw InstallError.sourceMissing(source.path)
        }
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw InstallError.destinationIsDirectory(destination.path)
        }

        let original: String
        do {
            original = try String(contentsOf: source, encoding: .utf8)
        } catch {
            throw InstallError.plistUnreadable(error.localizedDescription)
        }

        let studio = Self.studioHomeTemplate
        let rendered: String
        let rewritten: Bool
        if spec.home == studio {
            rendered = original
            rewritten = false
        } else {
            guard original.contains(studio) else {
                throw InstallError.templateMissing(studio: studio, source: source.path)
            }
            rendered = original.replacingOccurrences(of: studio, with: spec.home)
            rewritten = true
        }

        guard let plistData = rendered.data(using: .utf8) else {
            throw InstallError.plistUnreadable("utf-8 encode failed")
        }
        let plistObject: Any
        do {
            plistObject = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
        } catch {
            throw InstallError.plistUnreadable(error.localizedDescription)
        }
        guard let dict = plistObject as? [String: Any] else {
            throw InstallError.plistUnreadable("root is not a dictionary")
        }
        guard let plistLabel = dict["Label"] as? String, !plistLabel.isEmpty else {
            throw InstallError.labelMissing
        }
        if let expected = spec.label, expected != plistLabel {
            throw InstallError.labelMismatch(expected: expected, found: plistLabel)
        }

        // HAB-676/677/678/680/681/682/683/684/686/687/688/689/690/692/693/695/702: bootstrap
        // can succeed with a missing, unsigned, dylib-incomplete, or
        // unsigned-companion Mach-O Program, a WorkingDirectory that
        // cannot be chdir'd, a RootDirectory that cannot be chroot'd
        // (HAB-693), a log path launchd cannot open,
        // EnvironmentVariables.HOME that is relative/missing/not a
        // directory, TMPDIR that is relative/missing/not a directory
        // (HAB-695; libc tempfile then KeepAlive-hammers), PATH with
        // relative/empty/$HOME/~ components,
        // Program/ProgramArguments containing /usr/bin/open or
        // /usr/bin/osascript (LaunchServices/osascript inherit
        // Aqua/agent-shell env, including via arch/env trampolines),
        // paid provider API keys in EnvironmentVariables (HUD
        // local-only contract; KeepAlive then spend+leak), DYLD_*
        // keys that hijack an ad-hoc signed Program after HAB-677/680,
        // or a StandardInPath launchd cannot open (HAB-692).
        // Require the rendered exec path (not open/osascript in any
        // argv slot; signature + adjacent rpath dylibs + companion
        // signatures if Mach-O), WorkingDirectory (if present),
        // RootDirectory (if present), log
        // paths (if present), StandardInPath (if present), HOME (if
        // present), TMPDIR (if present), PATH (if present), WatchPaths
        // (if present), QueueDirectories (if present), no paid
        // API keys, and no DYLD_* keys before parking dest.
        // Rewrite-only dry-run skips.
        if spec.bootstrap {
            try Self.validateProgramNotOpen(dict)
            try Self.validateProgramNotOsascript(dict)
            try Self.validateProgram(dict, fileManager: fileManager)
            try Self.validateWorkingDirectory(dict, fileManager: fileManager)
            try Self.validateRootDirectory(dict, fileManager: fileManager)
            try Self.validateWatchPaths(dict, fileManager: fileManager)
            try Self.validateQueueDirectories(dict, fileManager: fileManager)
            try Self.validateLogPaths(dict, fileManager: fileManager)
            try Self.validateStandardInPath(dict, fileManager: fileManager)
            try Self.validateEnvironmentHome(dict, fileManager: fileManager)
            try Self.validateEnvironmentTmpdir(dict, fileManager: fileManager)
            try Self.validateEnvironmentPath(dict)
            try Self.validateEnvironmentPaidKeys(dict)
            try Self.validateEnvironmentDyldKeys(dict)
        }

        let destinationDirectory = destination.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } catch {
            throw InstallError.writeFailed(
                "could not create \(destinationDirectory.path): \(error.localizedDescription)"
            )
        }

        func ensureParentDirectory(of path: String) throws {
            // Relative log paths are not rewritten; mkdir would land in
            // the installer CWD. Bootstrap already fail-closed them
            // (HAB-682). Rewrite-only skips.
            guard path.hasPrefix("/") else { return }
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        if let outPath = dict["StandardOutPath"] as? String {
            do {
                try ensureParentDirectory(of: outPath)
            } catch {
                throw InstallError.logDirectoryFailed(error.localizedDescription)
            }
        }
        if let errPath = dict["StandardErrorPath"] as? String,
            errPath != (dict["StandardOutPath"] as? String)
        {
            do {
                try ensureParentDirectory(of: errPath)
            } catch {
                throw InstallError.logDirectoryFailed(error.localizedDescription)
            }
        }

        // Park previous dest, then publish staging. A failed bootstrap+load
        // restores the parked inode (HAB-632). Same-volume rename, matching
        // AppBundleInstaller HAB-630 / BinaryInstaller HAB-629.
        let stagingURL = destinationDirectory
            .appendingPathComponent(".\(destination.lastPathComponent).install-\(UUID().uuidString).tmp")
        do {
            try rendered.write(to: stagingURL, atomically: true, encoding: .utf8)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw InstallError.writeFailed(error.localizedDescription)
        }

        let replacedExisting = fileManager.fileExists(atPath: destination.path)
        let backupURL: URL?
        if replacedExisting {
            let parked = destinationDirectory
                .appendingPathComponent(".\(destination.lastPathComponent).rollback-\(UUID().uuidString).tmp")
            do {
                try fileManager.moveItem(at: destination, to: parked)
                backupURL = parked
            } catch {
                try? fileManager.removeItem(at: stagingURL)
                throw InstallError.writeFailed(
                    "park(\(destination.path) -> \(parked.path)): \(error.localizedDescription)"
                )
            }
        } else {
            backupURL = nil
        }

        func rollbackPublish() {
            if fileManager.fileExists(atPath: destination.path) {
                let orphan = destinationDirectory
                    .appendingPathComponent(".\(destination.lastPathComponent).orphan-\(UUID().uuidString).tmp")
                do {
                    try fileManager.moveItem(at: destination, to: orphan)
                    try? fileManager.removeItem(at: orphan)
                } catch {
                    try? fileManager.removeItem(at: destination)
                }
            }
            if let backupURL, fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.moveItem(at: backupURL, to: destination)
            }
            try? fileManager.removeItem(at: stagingURL)
        }

        do {
            try fileManager.moveItem(at: stagingURL, to: destination)
        } catch {
            rollbackPublish()
            throw InstallError.writeFailed(error.localizedDescription)
        }

        var bootstrapped = false
        var usedLegacyLoad = false
        var kickstarted = false
        let domain = "gui/\(spec.uid)"
        let target = "\(domain)/\(plistLabel)"

        if spec.bootstrap {
            _ = try? await shell.execute(["launchctl", "bootout", target])
            let boot = try await shell.execute(["launchctl", "bootstrap", domain, destination.path])
            if boot.success {
                bootstrapped = true
            } else {
                _ = try? await shell.execute(["launchctl", "unload", destination.path])
                let load = try await shell.execute(["launchctl", "load", destination.path])
                guard load.success else {
                    rollbackPublish()
                    throw InstallError.bootstrapFailed(
                        "bootstrap: \(boot.output); load: \(load.output)"
                    )
                }
                bootstrapped = true
                usedLegacyLoad = true
            }
            if spec.kickstart {
                let killed = try await shell.execute(["launchctl", "kickstart", "-k", target])
                if killed.success {
                    kickstarted = true
                } else {
                    let plain = try await shell.execute(["launchctl", "kickstart", target])
                    kickstarted = plain.success
                }
            }
        }
        if let backupURL {
            try? fileManager.removeItem(at: backupURL)
        }

        return Report(
            source: source.path,
            destination: destination.path,
            label: plistLabel,
            domain: domain,
            home: spec.home,
            rewritten: rewritten,
            bootstrapped: bootstrapped,
            usedLegacyLoad: usedLegacyLoad,
            kickstarted: kickstarted
        )
    }
    /// Program or ProgramArguments[0] after HOME rewrite.
    public static func programPath(from dict: [String: Any]) -> String? {
        if let program = dict["Program"] as? String {
            let trimmed = program.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let args = dict["ProgramArguments"] as? [String], let first = args.first {
            let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// Fail-closed Program check used only when bootstrapping (HAB-676 / HAB-677 / HAB-678 / HAB-680 / HAB-686).
    public static func validateProgram(
        _ dict: [String: Any],
        fileManager: FileManager
    ) throws {
        guard let path = programPath(from: dict) else {
            throw InstallError.programMissing("(no Program or ProgramArguments[0])")
        }
        guard path.hasPrefix("/") else {
            throw InstallError.programNotAbsolute(path)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw InstallError.programMissing(path)
        }
        guard fileManager.isExecutableFile(atPath: path) else {
            throw InstallError.programNotExecutable(path)
        }
        // HAB-677: unsigned Mach-O is Taskgated SIGKILL after a successful
        // bootstrap. Scripts/shebangs are not Mach-O — leave them alone.
        if isMachO(at: path) {
            try verifyCodeSignature(at: path)
            // HAB-678: signed Mach-O with a missing @loader_path dylib still
            // dyld-fails after bootstrap. Inspect Program + nested adjacent
            // companions; dest stays parked-until-valid (here: untouched).
            // HAB-680: those companions must also be signed.
            try verifyRequiredLibraries(at: path, fileManager: fileManager)
        }
    }

    /// Mach-O / fat magics in either endianness (on-disk bytes).
    public static func isMachO(at path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 4)
        guard data.count == 4 else { return false }
        let bytes = [UInt8](data)
        let magics: Set<[UInt8]> = [
            [0xFE, 0xED, 0xFA, 0xCE],
            [0xCE, 0xFA, 0xED, 0xFE],
            [0xFE, 0xED, 0xFA, 0xCF],
            [0xCF, 0xFA, 0xED, 0xFE],
            [0xCA, 0xFE, 0xBA, 0xBE],
            [0xBE, 0xBA, 0xFE, 0xCA],
            [0xCA, 0xFE, 0xBA, 0xBF],
            [0xBF, 0xBA, 0xFE, 0xCA],
        ]
        return magics.contains(bytes)
    }

    /// Live `/usr/bin/codesign --verify --strict` — not the injected shell.
    public static func verifyCodeSignature(at path: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--strict", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw InstallError.programNotSigned("\(path): \(error.localizedDescription)")
        }
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = output.isEmpty ? path : "\(path): \(output)"
            throw InstallError.programNotSigned(detail)
        }
    }

    /// Live `/usr/bin/otool -L` — not the injected shell (HAB-678).
    public static func loadLinkedLibraries(at path: String) throws -> [BinaryInstaller.LinkedLibrary] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        process.arguments = ["-L", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw InstallError.programLibraryInspectionFailed("\(path): \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = trimmed.isEmpty ? path : "\(path): \(trimmed)"
            throw InstallError.programLibraryInspectionFailed(detail)
        }
        return BinaryInstaller.parseOtoolL(output)
    }

    /// Walk Program-adjacent companions and union their load commands.
    public static func expandLinkedLibraries(
        at path: String,
        fileManager: FileManager
    ) throws -> [BinaryInstaller.LinkedLibrary] {
        var all = try loadLinkedLibraries(at: path)
        var seen: Set<String> = []
        var queue: [String] = []
        func enqueue(_ libraries: [BinaryInstaller.LinkedLibrary]) {
            for library in libraries {
                if library.isWeak { continue }
                guard let name = library.adjacentFileName else { continue }
                if seen.insert(name).inserted {
                    queue.append(name)
                }
            }
        }
        enqueue(all)
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        var index = 0
        while index < queue.count {
            let name = queue[index]
            index += 1
            let nestedURL = directory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: nestedURL.path) else { continue }
            let nested = try loadLinkedLibraries(at: nestedURL.path)
            all.append(contentsOf: nested)
            enqueue(nested)
        }
        return all
    }

    /// Fail-closed if a required non-system / runtime-relative dylib would
    /// not resolve next to Program (HAB-678).
    public static func verifyRequiredLibraries(at path: String, fileManager: FileManager) throws {
        let libraries = try expandLinkedLibraries(at: path, fileManager: fileManager)
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        let gaps = BinaryInstaller.requiredLibraryGaps(
            libraries,
            adjacentDirectory: directory,
            sourceDirectory: directory,
            fileExists: { fileManager.fileExists(atPath: $0) }
        )
        guard gaps.isEmpty else {
            let detail = gaps.map(\.installName).joined(separator: ", ")
            throw InstallError.programMissingLibraries("\(path): \(detail)")
        }
        try verifyCompanionSignatures(libraries, adjacentDirectory: directory)
    }

    /// Fail-closed if an adjacent required companion fails
    /// `codesign --verify --strict` (HAB-680).
    public static func verifyCompanionSignatures(
        _ libraries: [BinaryInstaller.LinkedLibrary],
        adjacentDirectory: URL
    ) throws {
        var seen: Set<String> = []
        var unsigned: [String] = []
        for library in libraries {
            if library.isWeak { continue }
            guard let name = library.adjacentFileName else { continue }
            guard seen.insert(name).inserted else { continue }
            let companion = adjacentDirectory.appendingPathComponent(name).path
            do {
                try verifyCodeSignature(at: companion)
            } catch {
                unsigned.append(name)
            }
        }
        guard unsigned.isEmpty else {
            throw InstallError.programUnsignedLibraries(unsigned.sorted().joined(separator: ", "))
        }
    }

    /// WorkingDirectory after HOME rewrite. Nil when the key is absent or blank.
    public static func workingDirectoryPath(from dict: [String: Any]) -> String? {
        guard let value = dict["WorkingDirectory"] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed
    }

    /// Fail-closed WorkingDirectory check used only when bootstrapping (HAB-681).
    /// Missing key is allowed (launchd defaults to `/`).
    public static func validateWorkingDirectory(
        _ dict: [String: Any],
        fileManager: FileManager
    ) throws {
        guard let path = workingDirectoryPath(from: dict) else { return }
        guard path.hasPrefix("/") else {
            throw InstallError.workingDirectoryNotAbsolute(path)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw InstallError.workingDirectoryMissing(path)
        }
        guard isDirectory.boolValue else {
            throw InstallError.workingDirectoryNotDirectory(path)
        }
    }

    /// RootDirectory after HOME rewrite. Nil when the key is absent or blank.
    public static func rootDirectoryPath(from dict: [String: Any]) -> String? {
        guard let value = dict["RootDirectory"] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed
    }

    /// Fail-closed RootDirectory check used only when bootstrapping (HAB-693).
    /// Missing key is allowed (launchd does not chroot). Relative paths,
    /// missing directories, and files fail before dest is parked.
    public static func validateRootDirectory(
        _ dict: [String: Any],
        fileManager: FileManager
    ) throws {
        guard let path = rootDirectoryPath(from: dict) else { return }
        guard path.hasPrefix("/") else {
            throw InstallError.rootDirectoryNotAbsolute(path)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw InstallError.rootDirectoryMissing(path)
        }
        guard isDirectory.boolValue else {
            throw InstallError.rootDirectoryNotDirectory(path)
        }
    }

    /// WatchPaths after HOME rewrite. Blank entries omitted.
    public static func watchPaths(from dict: [String: Any]) -> [String] {
        guard let values = dict["WatchPaths"] as? [Any] else { return [] }
        var paths: [String] = []
        var seen: Set<String> = []
        for value in values {
            guard let raw = value as? String else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if seen.insert(trimmed).inserted {
                paths.append(trimmed)
            }
        }
        return paths
    }

    /// Fail-closed WatchPaths check used only when bootstrapping (HAB-702).
    /// Missing key / empty array allowed. Relative paths and missing
    /// entries fail before dest is parked. Files and directories are OK.
    public static func validateWatchPaths(
        _ dict: [String: Any],
        fileManager: FileManager
    ) throws {
        for path in watchPaths(from: dict) {
            guard path.hasPrefix("/") else {
                throw InstallError.watchPathNotAbsolute(path)
            }
            guard fileManager.fileExists(atPath: path) else {
                throw InstallError.watchPathMissing(path)
            }
        }
    }

    /// QueueDirectories after HOME rewrite. Blank entries omitted.
    public static func queueDirectories(from dict: [String: Any]) -> [String] {
        guard let values = dict["QueueDirectories"] as? [Any] else { return [] }
        var paths: [String] = []
        var seen: Set<String> = []
        for value in values {
            guard let raw = value as? String else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if seen.insert(trimmed).inserted {
                paths.append(trimmed)
            }
        }
        return paths
    }

    /// Fail-closed QueueDirectories check used only when bootstrapping (HAB-702).
    /// Missing key / empty array allowed. Relative paths, missing
    /// directories, and files fail before dest is parked.
    public static func validateQueueDirectories(
        _ dict: [String: Any],
        fileManager: FileManager
    ) throws {
        for path in queueDirectories(from: dict) {
            guard path.hasPrefix("/") else {
                throw InstallError.queueDirectoryNotAbsolute(path)
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                throw InstallError.queueDirectoryMissing(path)
            }
            guard isDirectory.boolValue else {
                throw InstallError.queueDirectoryNotDirectory(path)
            }
        }
    }

    /// StandardOutPath / StandardErrorPath after HOME rewrite.
    /// Blank or missing keys are omitted (launchd inherits stdout/stderr).
    public static func logPaths(from dict: [String: Any]) -> [String] {
        var paths: [String] = []
        var seen: Set<String> = []
        for key in ["StandardOutPath", "StandardErrorPath"] {
            guard let value = dict[key] as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if seen.insert(trimmed).inserted {
                paths.append(trimmed)
            }
        }
        return paths
    }

    /// Fail-closed log path check used only when bootstrapping (HAB-682).
    /// Missing keys are allowed. Relative paths and existing directories
    /// fail before dest is parked.
    public static func validateLogPaths(
        _ dict: [String: Any],
        fileManager: FileManager
    ) throws {
        for path in logPaths(from: dict) {
            guard path.hasPrefix("/") else {
                throw InstallError.logPathNotAbsolute(path)
            }
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                throw InstallError.logPathIsDirectory(path)
            }
        }
    }

    /// StandardInPath after HOME rewrite. Nil when the key is absent or blank.
    public static func standardInPath(from dict: [String: Any]) -> String? {
        guard let value = dict["StandardInPath"] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed
    }

    /// Fail-closed StandardInPath check used only when bootstrapping (HAB-692).
    /// Missing key is allowed. Relative paths, missing files, and existing
    /// directories fail before dest is parked. Unlike stdout/stderr, launchd
    /// does not create stdin — the file must already exist.
    public static func validateStandardInPath(
        _ dict: [String: Any],
        fileManager: FileManager
    ) throws {
        guard let path = standardInPath(from: dict) else { return }
        guard path.hasPrefix("/") else {
            throw InstallError.standardInPathNotAbsolute(path)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw InstallError.standardInPathMissing(path)
        }
        guard !isDirectory.boolValue else {
            throw InstallError.standardInPathIsDirectory(path)
        }
    }

    /// EnvironmentVariables.HOME after HOME rewrite. Nil when the dict,
    /// key, or value is absent/blank.
    public static func environmentHomePath(from dict: [String: Any]) -> String? {
        guard let env = dict["EnvironmentVariables"] as? [String: Any] else { return nil }
        guard let value = env["HOME"] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed
    }

    /// Fail-closed EnvironmentVariables.HOME check used only when
    /// bootstrapping (HAB-683). Missing key is allowed.
    public static func validateEnvironmentHome(
        _ dict: [String: Any],
        fileManager: FileManager
    ) throws {
        guard let path = environmentHomePath(from: dict) else { return }
        guard path.hasPrefix("/") else {
            throw InstallError.environmentHomeNotAbsolute(path)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw InstallError.environmentHomeMissing(path)
        }
        guard isDirectory.boolValue else {
            throw InstallError.environmentHomeNotDirectory(path)
        }
    }

    /// EnvironmentVariables.TMPDIR after HOME rewrite. Nil when the dict,
    /// key, or value is absent/blank.
    public static func environmentTmpdirPath(from dict: [String: Any]) -> String? {
        guard let env = dict["EnvironmentVariables"] as? [String: Any] else { return nil }
        guard let value = env["TMPDIR"] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed
    }

    /// Fail-closed EnvironmentVariables.TMPDIR check used only when
    /// bootstrapping (HAB-695). Missing key is allowed (OS default).
    /// Relative paths, missing directories, and files fail before dest
    /// is parked — libc tempfile then KeepAlive-hammers.
    public static func validateEnvironmentTmpdir(
        _ dict: [String: Any],
        fileManager: FileManager
    ) throws {
        guard let path = environmentTmpdirPath(from: dict) else { return }
        guard path.hasPrefix("/") else {
            throw InstallError.environmentTmpdirNotAbsolute(path)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw InstallError.environmentTmpdirMissing(path)
        }
        guard isDirectory.boolValue else {
            throw InstallError.environmentTmpdirNotDirectory(path)
        }
    }

    /// EnvironmentVariables.PATH colon components after HOME rewrite.
    /// Nil when the dict, key, or value is absent/blank.
    public static func environmentPathComponents(from dict: [String: Any]) -> [String]? {
        guard let env = dict["EnvironmentVariables"] as? [String: Any] else { return nil }
        guard let value = env["PATH"] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed.split(separator: ":", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Fail-closed EnvironmentVariables.PATH check used only when
    /// bootstrapping (HAB-684). Missing key is allowed. Components are
    /// not required to exist.
    public static func validateEnvironmentPath(_ dict: [String: Any]) throws {
        guard let components = environmentPathComponents(from: dict) else { return }
        for component in components {
            if component.isEmpty || !component.hasPrefix("/") {
                throw InstallError.environmentPathNotAbsolute(
                    component.isEmpty ? "(empty)" : component
                )
            }
        }
    }

    /// Program key plus every ProgramArguments entry. launchd can exec
    /// `Program` while argv still contains wrappers' targets.
    public static func programInvocationPaths(from dict: [String: Any]) -> [String] {
        var paths: [String] = []
        if let program = dict["Program"] as? String {
            paths.append(program)
        }
        if let args = dict["ProgramArguments"] as? [String] {
            paths.append(contentsOf: args)
        }
        return paths
    }

    /// True when the path standardizes to LaunchServices `open`.
    public static func isLaunchServicesOpen(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path == "/usr/bin/open"
    }

    /// Fail-closed `/usr/bin/open` check used only when bootstrapping
    /// (HAB-686 / HAB-688). Scans Program and every ProgramArguments
    /// slot so `/usr/bin/arch -arm64 /usr/bin/open` cannot bypass
    /// argv[0]-only inspection. Missing Program is left to
    /// `validateProgram`.
    public static func validateProgramNotOpen(_ dict: [String: Any]) throws {
        for path in programInvocationPaths(from: dict) {
            if isLaunchServicesOpen(path) {
                throw InstallError.programUsesOpen(path)
            }
        }
    }

    /// True when the path standardizes to `/usr/bin/osascript`.
    public static func isOsascript(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path == "/usr/bin/osascript"
    }

    /// Fail-closed `/usr/bin/osascript` check used only when bootstrapping
    /// (HAB-687 / HAB-688). Same argv-wide scan as `validateProgramNotOpen`.
    public static func validateProgramNotOsascript(_ dict: [String: Any]) throws {
        for path in programInvocationPaths(from: dict) {
            if isOsascript(path) {
                throw InstallError.programUsesOsascript(path)
            }
        }
    }

    /// Prefixes refused in EnvironmentVariables on bootstrap (HAB-689).
    /// HUD plist: no OPENROUTER_*, ANTHROPIC_*, or paid API keys.
    public static let paidEnvironmentKeyPrefixes: [String] = [
        "OPENROUTER_",
        "ANTHROPIC_",
        "OPENAI_",
        "XAI_",
        "GROQ_",
    ]

    /// Exact keys refused in addition to prefixes (HAB-689).
    public static let paidEnvironmentExactKeys: Set<String> = [
        "GOOGLE_API_KEY",
        "GEMINI_API_KEY",
    ]

    /// True when an EnvironmentVariables key is a paid provider secret.
    public static func isPaidEnvironmentKey(_ key: String) -> Bool {
        let upper = key.uppercased()
        if Self.paidEnvironmentExactKeys.contains(upper) { return true }
        return Self.paidEnvironmentKeyPrefixes.contains { upper.hasPrefix($0) }
    }

    /// Paid-provider keys present in EnvironmentVariables after rewrite.
    public static func paidEnvironmentKeys(from dict: [String: Any]) -> [String] {
        guard let env = dict["EnvironmentVariables"] as? [String: Any] else { return [] }
        return env.keys.filter(isPaidEnvironmentKey).sorted()
    }

    /// Fail-closed paid API key check used only when bootstrapping (HAB-689).
    /// Missing EnvironmentVariables dict / HOME / PATH / LANG allowed.
    public static func validateEnvironmentPaidKeys(_ dict: [String: Any]) throws {
        let keys = paidEnvironmentKeys(from: dict)
        guard keys.isEmpty else {
            throw InstallError.environmentPaidApiKey(keys.joined(separator: ", "))
        }
    }

    /// True when an EnvironmentVariables key is a dyld injection / search-path
    /// override (HAB-690). Prefix match so DYLD_INSERT_LIBRARIES,
    /// DYLD_LIBRARY_PATH, DYLD_FRAMEWORK_PATH, fallbacks, and ROOT_PATH
    /// are all refused.
    public static func isDyldEnvironmentKey(_ key: String) -> Bool {
        key.uppercased().hasPrefix("DYLD_")
    }

    /// DYLD_* keys present in EnvironmentVariables after rewrite.
    public static func dyldEnvironmentKeys(from dict: [String: Any]) -> [String] {
        guard let env = dict["EnvironmentVariables"] as? [String: Any] else { return [] }
        return env.keys.filter(isDyldEnvironmentKey).sorted()
    }

    /// Fail-closed DYLD_* check used only when bootstrapping (HAB-690).
    /// Missing EnvironmentVariables dict / HOME / PATH / LANG allowed.
    public static func validateEnvironmentDyldKeys(_ dict: [String: Any]) throws {
        let keys = dyldEnvironmentKeys(from: dict)
        guard keys.isEmpty else {
            throw InstallError.environmentDyldInjection(keys.joined(separator: ", "))
        }
    }

}
