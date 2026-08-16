import Foundation

public struct CLIError: Error, CustomStringConvertible {
    public init(description: String) { self.description = description }
    public let description: String
}

/// Parses `--flag value` pairs from a command-line tail.
public enum FlagParser {
    public static func require(_ name: String, arguments: [String]) throws -> String {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
            throw CLIError(description: "missing required flag \(name)")
        }
        return arguments[index + 1]
    }

    public static func optional(_ name: String, arguments: [String], default defaultValue: String) -> String {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
            return defaultValue
        }
        return arguments[index + 1]
    }
}

/// Resolves the durable tooling directory (the one holding `shot.mjs` /
/// `diff.mjs`). Lives OUTSIDE the repo checkout: the base capture step
/// rewrites the tree, which is exactly when the tooling must survive.
/// `executablePath` normally sits at `<tooling>/.build/{debug,release}/…`,
/// so the tooling root is three levels up — but only trusted when the
/// sibling scripts are actually there; otherwise use the fallback.
public enum Tooling {
    static let captureScript = "shot.mjs"

    public static func directory(executablePath: String, fallback: String) -> String {
        let dir = URL(fileURLWithPath: executablePath)
            .deletingLastPathComponent()  // .build/{debug,release}
            .deletingLastPathComponent()  // .build
            .deletingLastPathComponent()  // <tooling>
        let hasScripts = FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(captureScript).path
        )
        return hasScripts ? dir.path : fallback
    }
}
