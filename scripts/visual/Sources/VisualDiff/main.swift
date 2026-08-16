import Foundation
import VisualDiffCore

// visual-diff — Swift orchestrator for the Andromeda web visual-diff pipeline.
// Thin dispatch shell; all logic lives in VisualDiffCore.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("visual-diff: \(message)\n".utf8))
    exit(1)
}

func intFlag(_ name: String, _ flags: [String]) throws -> Int {
    guard let raw = try? FlagParser.require(name, arguments: flags), let value = Int(raw) else {
        throw CLIError(description: "expected an integer for \(name)")
    }
    return value
}

let arguments = Array(CommandLine.arguments.dropFirst())
let cwd = FileManager.default.currentDirectoryPath

guard let subcommand = arguments.first else {
    fail("usage: visual-diff <capture|diff|publish|comment> [--flags]")
}

let flags = Array(arguments.dropFirst())
let tooling = Tooling.directory(
    executablePath: CommandLine.arguments[0],
    fallback: FlagParser.optional("--tooling-dir", arguments: flags, default: cwd)
)

do {
    switch subcommand {
    case "capture":
        try Capture.run(
            Capture.Options(
                side: try FlagParser.require("--side", arguments: flags),
                sha: try FlagParser.require("--sha", arguments: flags),
                port: try intFlag("--port", flags),
                repoRoot: URL(fileURLWithPath: FlagParser.optional("--repo-root", arguments: flags, default: cwd)),
                toolingDir: URL(fileURLWithPath: FlagParser.optional("--tooling-dir", arguments: flags, default: tooling))
            )
        )

    case "diff":
        try Capture.diff(
            base: URL(fileURLWithPath: try FlagParser.require("--base", arguments: flags)),
            head: URL(fileURLWithPath: try FlagParser.require("--head", arguments: flags)),
            out: URL(fileURLWithPath: try FlagParser.require("--out", arguments: flags)),
            toolingDir: URL(fileURLWithPath: FlagParser.optional("--tooling-dir", arguments: flags, default: tooling))
        )

    case "publish":
        try Publish.publish(
            Publish.Options(
                pr: try intFlag("--pr", flags),
                repo: try FlagParser.require("--repo", arguments: flags),
                repoRoot: URL(fileURLWithPath: FlagParser.optional("--repo-root", arguments: flags, default: cwd))
            )
        )

    case "comment":
        try Publish.comment(
            Publish.Options(
                pr: try intFlag("--pr", flags),
                repo: try FlagParser.require("--repo", arguments: flags),
                repoRoot: URL(fileURLWithPath: FlagParser.optional("--repo-root", arguments: flags, default: cwd))
            )
        )

    default:
        fail("unknown subcommand: \(subcommand)")
    }
} catch {
    fail(String(describing: error))
}
