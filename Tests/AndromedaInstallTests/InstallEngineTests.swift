import AndromedaInstall
import Foundation
import Testing

/// Recording process runner for dry-run / kickstart contract tests.
private final class RecordingRunner: ProcessRunning, @unchecked Sendable {
    struct Call: Equatable {
        var executable: String
        var arguments: [String]
    }

    var calls: [Call] = []
    var results: [String: ProcessResult] = [:]
    var defaultResult = ProcessResult(exitCode: 0)

    func run(
        executable: String,
        arguments: [String],
        currentDirectory: String?
    ) throws -> ProcessResult {
        calls.append(Call(executable: executable, arguments: arguments))
        let key = ([executable] + arguments).joined(separator: " ")
        return results[key] ?? defaultResult
    }
}

/// Engine behavior that is portable (dry-run + uid + fail-closed kickstart).
struct InstallEngineTests {
    @Test("dry-run returns plan without invoking tools")
    func dryRunSkipsTools() throws {
        let runner = RecordingRunner()
        let engine = InstallEngine(runner: runner)
        let paths = InstallPaths(
            repositoryRoot: URL(fileURLWithPath: "/repo"),
            homeDirectory: URL(fileURLWithPath: "/Users/demo")
        )
        let configuration = InstallConfiguration(
            target: .hud,
            paths: paths,
            dryRun: true
        )
        let plan = try engine.run(configuration)
        #expect(plan.steps.isEmpty == false)
        #expect(runner.calls.isEmpty)
    }

    @Test("resolveUserID uses absolute /usr/bin/id -u")
    func resolveUID() throws {
        let runner = RecordingRunner()
        runner.results["/usr/bin/id -u"] = ProcessResult(exitCode: 0, stdout: "501\n")
        let engine = InstallEngine(runner: runner)
        let uid = try engine.resolveUserID(tools: AbsoluteToolPaths())
        #expect(uid == "501")
        #expect(runner.calls == [.init(executable: "/usr/bin/id", arguments: ["-u"])])
    }

    @Test("kickstart fails closed when both kickstart forms fail")
    func kickstartFailClosed() throws {
        let runner = RecordingRunner()
        runner.results["/usr/bin/id -u"] = ProcessResult(exitCode: 0, stdout: "501\n")
        runner.defaultResult = ProcessResult(exitCode: 0)
        runner.results["/bin/launchctl kickstart -k gui/501/com.andromeda.hud"] =
            ProcessResult(exitCode: 1, stderr: "no such process")
        runner.results["/bin/launchctl kickstart gui/501/com.andromeda.hud"] =
            ProcessResult(exitCode: 1, stderr: "still failing")

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("andromeda-install-engine-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let repo = try InstallPaths.discoverRepositoryRoot()
        let paths = InstallPaths(
            repositoryRoot: repo,
            homeDirectory: tempRoot
        )
        let engine = InstallEngine(runner: runner)
        let configuration = InstallConfiguration(target: .hud, paths: paths, dryRun: false)

        #expect(throws: InstallError.self) {
            try engine.installHUDLaunchAgent(configuration: configuration)
        }
    }

    @Test("kickstart succeeds after -k failure via plain kickstart")
    func kickstartFallback() throws {
        let runner = RecordingRunner()
        runner.results["/usr/bin/id -u"] = ProcessResult(exitCode: 0, stdout: "501\n")
        runner.results["/bin/launchctl kickstart -k gui/501/com.andromeda.hud"] =
            ProcessResult(exitCode: 1, stderr: "busy")
        runner.results["/bin/launchctl kickstart gui/501/com.andromeda.hud"] =
            ProcessResult(exitCode: 0)

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("andromeda-install-engine-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let repo = try InstallPaths.discoverRepositoryRoot()
        let paths = InstallPaths(
            repositoryRoot: repo,
            homeDirectory: tempRoot
        )
        let engine = InstallEngine(runner: runner)
        let configuration = InstallConfiguration(target: .hud, paths: paths)

        try engine.installHUDLaunchAgent(configuration: configuration)

        let rendered = try String(contentsOf: paths.hudPlistDestination, encoding: .utf8)
        #expect(rendered.contains(tempRoot.path))
        #expect(!rendered.contains(StudioHomeTemplate.path) || tempRoot.path == StudioHomeTemplate.path)

        let kickCalls = runner.calls.filter { $0.executable == "/bin/launchctl" && $0.arguments.first == "kickstart" }
        #expect(kickCalls.count == 2)
    }
}
