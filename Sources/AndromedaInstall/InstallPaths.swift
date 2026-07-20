import Foundation

/// Resolved filesystem locations for one install run.
public struct InstallPaths: Sendable, Equatable {
    public var repositoryRoot: URL
    public var homeDirectory: URL
    public var applicationsDirectory: URL
    public var launchAgentsDirectory: URL
    public var multibrainLogsDirectory: URL
    public var releaseBuildDirectory: URL

    public init(
        repositoryRoot: URL,
        homeDirectory: URL,
        applicationsDirectory: URL? = nil,
        launchAgentsDirectory: URL? = nil,
        multibrainLogsDirectory: URL? = nil,
        releaseBuildDirectory: URL? = nil
    ) {
        self.repositoryRoot = repositoryRoot
        self.homeDirectory = homeDirectory
        self.applicationsDirectory =
            applicationsDirectory ?? homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        self.launchAgentsDirectory =
            launchAgentsDirectory
            ?? homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
        self.multibrainLogsDirectory =
            multibrainLogsDirectory
            ?? homeDirectory
            .appendingPathComponent(".multibrain", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        self.releaseBuildDirectory =
            releaseBuildDirectory
            ?? repositoryRoot
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
    }

    /// Discovers the package root by walking up from `start` until `Package.swift` appears.
    public static func discoverRepositoryRoot(
        startingAt start: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        fileManager: FileManager = .default
    ) throws -> URL {
        var current = start.standardizedFileURL
        for _ in 0..<24 {
            let marker = current.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: marker.path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        throw InstallError.missingRepositoryRoot
    }

    /// Builds paths from environment `HOME` and the discovered repo root.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> InstallPaths {
        guard let home = environment["HOME"], !home.isEmpty else {
            throw InstallError.missingHome
        }
        let root = try discoverRepositoryRoot(fileManager: fileManager)
        return InstallPaths(
            repositoryRoot: root,
            homeDirectory: URL(fileURLWithPath: home, isDirectory: true)
        )
    }

    /// App bundle URL for a product under `~/Applications`.
    public func appBundle(for product: InstallProduct) -> URL {
        applicationsDirectory.appendingPathComponent("\(product.rawValue).app", isDirectory: true)
    }

    /// Release binary produced by `swift build -c release --product …`.
    public func releaseBinary(for product: InstallProduct) -> URL {
        releaseBuildDirectory.appendingPathComponent(product.rawValue)
    }

    /// Repo template for the HUD LaunchAgent.
    public var hudPlistTemplate: URL {
        repositoryRoot.appendingPathComponent(HUDLaunchAgent.relativeTemplatePath)
    }

    /// Installed LaunchAgent destination for the HUD label.
    public var hudPlistDestination: URL {
        launchAgentsDirectory.appendingPathComponent("\(HUDLaunchAgent.label).plist")
    }
}
