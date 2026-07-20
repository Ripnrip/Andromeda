import Foundation

/// Absolute paths for mutate tooling — never bare `codesign` / `launchctl` on PATH.
public struct AbsoluteToolPaths: Sendable, Equatable {
    public var swift: String
    public var codesign: String
    public var launchctl: String
    public var open: String
    public var pkill: String
    public var id: String
    public var mkdir: String
    public var rm: String
    public var cp: String
    public var chmod: String
    public var sleep: String

    public init(
        swift: String = AbsoluteToolPaths.resolveSwift(),
        codesign: String = "/usr/bin/codesign",
        launchctl: String = "/bin/launchctl",
        open: String = "/usr/bin/open",
        pkill: String = "/usr/bin/pkill",
        id: String = "/usr/bin/id",
        mkdir: String = "/bin/mkdir",
        rm: String = "/bin/rm",
        cp: String = "/bin/cp",
        chmod: String = "/bin/chmod",
        sleep: String = "/bin/sleep"
    ) {
        self.swift = swift
        self.codesign = codesign
        self.launchctl = launchctl
        self.open = open
        self.pkill = pkill
        self.id = id
        self.mkdir = mkdir
        self.rm = rm
        self.cp = cp
        self.chmod = chmod
        self.sleep = sleep
    }

    /// Resolves Swift from `ANDROMEDA_SWIFT`, then `/usr/bin/swift`.
    public static func resolveSwift() -> String {
        if let override = ProcessInfo.processInfo.environment["ANDROMEDA_SWIFT"],
           !override.isEmpty {
            return override
        }
        return "/usr/bin/swift"
    }
}

/// Studio SoT home baked into `ops/*.plist` templates.
public enum StudioHomeTemplate {
    public static let path = "/Users/admin"
}

/// HUD LaunchAgent label installed under `gui/<uid>/`.
public enum HUDLaunchAgent {
    public static let label = "com.andromeda.hud"
    public static let relativeTemplatePath = "ops/com.andromeda.hud.plist"
}
