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
/// absolute existing executable before dest is parked (HAB-676). Rewrite-only
/// (`bootstrap` false) stays a dry-run and does not require the binary.
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

        // HAB-676: bootstrap can succeed with a missing Program. Require the
        // rendered exec path before parking dest. Rewrite-only dry-run skips.
        if spec.bootstrap {
            try Self.validateProgram(dict, fileManager: fileManager)
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

    /// Fail-closed Program check used only when bootstrapping (HAB-676).
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
    }

}
