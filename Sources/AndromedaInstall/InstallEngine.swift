import Foundation

/// Configuration for one `andromeda-install` invocation.
public struct InstallConfiguration: Sendable {
    public var target: InstallTarget
    public var paths: InstallPaths
    public var tools: AbsoluteToolPaths
    public var shortVersion: String
    public var buildVersion: String
    public var dryRun: Bool
    /// When true, skip `open -a` even for Home (useful in CI/agent shells).
    public var skipOpen: Bool

    public init(
        target: InstallTarget,
        paths: InstallPaths,
        tools: AbsoluteToolPaths = AbsoluteToolPaths(),
        shortVersion: String = ProcessInfo.processInfo.environment["CFBundleShortVersionString"] ?? "0.3",
        buildVersion: String = InstallConfiguration.defaultBuildVersion(),
        dryRun: Bool = false,
        skipOpen: Bool = false
    ) {
        self.target = target
        self.paths = paths
        self.tools = tools
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
        self.dryRun = dryRun
        self.skipOpen = skipOpen
    }

    /// Timestamp build id matching the former bash installer (`YYYYMMDDHHMM`).
    public static func defaultBuildVersion(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter.string(from: date)
    }
}

/// Executes build → stage → adhoc codesign → LaunchAgent mutate.
public struct InstallEngine: Sendable {
    private let runner: any ProcessRunning
    private let fileManager: FileManager

    public init(
        runner: any ProcessRunning = FoundationProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.runner = runner
        self.fileManager = fileManager
    }

    /// Returns the dry-run plan without mutating the system.
    public func plan(for configuration: InstallConfiguration) -> InstallPlan {
        InstallPlan.make(
            target: configuration.target,
            paths: configuration.paths,
            shortVersion: configuration.shortVersion,
            buildVersion: configuration.buildVersion
        )
    }

    /// Runs the install; dry-run only prints the plan via returned steps.
    public func run(_ configuration: InstallConfiguration) throws -> InstallPlan {
        let installPlan = plan(for: configuration)
        if configuration.dryRun {
            return installPlan
        }

        #if os(macOS)
        for product in configuration.target.products {
            try installProduct(product, configuration: configuration)
        }
        if configuration.target.installsHUDLaunchAgent {
            try installHUDLaunchAgent(configuration: configuration)
        }
        return installPlan
        #else
        throw InstallError.unsupportedPlatform(
            "andromeda-install mutate path is macOS-only; use --dry-run on this host"
        )
        #endif
    }

    /// Builds, stages, signs, and optionally opens one product app bundle.
    public func installProduct(
        _ product: InstallProduct,
        configuration: InstallConfiguration
    ) throws {
        let root = configuration.paths.repositoryRoot.path
        try runner.requireSuccess(
            executable: configuration.tools.swift,
            arguments: ["build", "-c", "release", "--product", product.rawValue],
            currentDirectory: root
        )

        let binary = configuration.paths.releaseBinary(for: product)
        guard fileManager.isExecutableFile(atPath: binary.path) else {
            throw InstallError.missingBinary(binary.path)
        }

        // Best-effort quit of a running instance before replacing the bundle.
        _ = try? runner.run(
            executable: configuration.tools.pkill,
            arguments: ["-x", product.rawValue],
            currentDirectory: nil
        )
        _ = try? runner.run(
            executable: configuration.tools.sleep,
            arguments: ["0.3"],
            currentDirectory: nil
        )

        let app = configuration.paths.appBundle(for: product)
        let macosDir = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let resourcesDir = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        if fileManager.fileExists(atPath: app.path) {
            try fileManager.removeItem(at: app)
        }
        try fileManager.createDirectory(at: macosDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

        let stagedBinary = macosDir.appendingPathComponent(product.rawValue)
        if fileManager.fileExists(atPath: stagedBinary.path) {
            try fileManager.removeItem(at: stagedBinary)
        }
        try fileManager.copyItem(at: binary, to: stagedBinary)
        try runner.requireSuccess(
            executable: configuration.tools.chmod,
            arguments: ["+x", stagedBinary.path]
        )

        let infoPlist = AppInfoPlist.xml(
            product: product,
            shortVersion: configuration.shortVersion,
            buildVersion: configuration.buildVersion
        )
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        try infoPlist.write(to: infoURL, atomically: true, encoding: .utf8)

        // Strip linker-signed SPM residue, then adhoc-sign the .app (PROOF 38).
        _ = try? runner.run(
            executable: configuration.tools.codesign,
            arguments: ["--remove-signature", stagedBinary.path],
            currentDirectory: nil
        )
        _ = try? runner.run(
            executable: configuration.tools.codesign,
            arguments: ["--remove-signature", app.path],
            currentDirectory: nil
        )
        try runner.requireSuccess(
            executable: configuration.tools.codesign,
            arguments: ["--force", "--deep", "--sign", "-", app.path]
        )
        try runner.requireSuccess(
            executable: configuration.tools.codesign,
            arguments: ["--verify", "--deep", "--strict", app.path]
        )

        if product.opensAfterInstall, !configuration.skipOpen {
            try runner.requireSuccess(
                executable: configuration.tools.open,
                arguments: ["-a", app.path]
            )
        }
    }

    /// Renders the HUD plist, bootstraps it, and fail-closed kickstarts under launchd.
    public func installHUDLaunchAgent(configuration: InstallConfiguration) throws {
        let template = configuration.paths.hudPlistTemplate
        let destination = configuration.paths.hudPlistDestination
        try LaunchAgentPlistRenderer.renderFile(
            source: template,
            destination: destination,
            homeDirectory: configuration.paths.homeDirectory.path,
            fileManager: fileManager
        )

        try fileManager.createDirectory(
            at: configuration.paths.multibrainLogsDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: configuration.paths.launchAgentsDirectory,
            withIntermediateDirectories: true
        )

        let uid = try resolveUserID(tools: configuration.tools)
        let domainTarget = "gui/\(uid)/\(HUDLaunchAgent.label)"

        // bootout is best-effort when the agent is not yet loaded.
        _ = try? runner.run(
            executable: configuration.tools.launchctl,
            arguments: ["bootout", domainTarget],
            currentDirectory: nil
        )

        let bootstrap = try runner.run(
            executable: configuration.tools.launchctl,
            arguments: ["bootstrap", "gui/\(uid)", destination.path],
            currentDirectory: nil
        )
        if !bootstrap.succeeded {
            _ = try? runner.run(
                executable: configuration.tools.launchctl,
                arguments: ["unload", destination.path],
                currentDirectory: nil
            )
            try runner.requireSuccess(
                executable: configuration.tools.launchctl,
                arguments: ["load", destination.path]
            )
        }

        // Fail-closed: HUD must start under launchd with a scrubbed env.
        let kickKill = try runner.run(
            executable: configuration.tools.launchctl,
            arguments: ["kickstart", "-k", domainTarget],
            currentDirectory: nil
        )
        if !kickKill.succeeded {
            let kick = try runner.run(
                executable: configuration.tools.launchctl,
                arguments: ["kickstart", domainTarget],
                currentDirectory: nil
            )
            if !kick.succeeded {
                throw InstallError.kickstartFailed(label: HUDLaunchAgent.label)
            }
        }
    }

    /// Reads the numeric uid via absolute `/usr/bin/id -u`.
    public func resolveUserID(tools: AbsoluteToolPaths) throws -> String {
        let result = try runner.run(
            executable: tools.id,
            arguments: ["-u"],
            currentDirectory: nil
        )
        guard result.succeeded else {
            throw InstallError.commandFailed(
                executable: tools.id,
                arguments: ["-u"],
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        let uid = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty, uid.allSatisfy(\.isNumber) else {
            throw InstallError.commandFailed(
                executable: tools.id,
                arguments: ["-u"],
                exitCode: result.exitCode,
                stderr: "unexpected uid output: \(result.stdout)"
            )
        }
        return uid
    }
}
