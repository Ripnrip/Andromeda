@testable import AndromedaHostOps
import Foundation
import Testing

/// LettaChannelsHealthProbe tests.
///
/// Never touches live `launchctl` / `pgrep` / `com.binarybros.letta-channels`:
/// shell behavior is mocked (`ScriptedShell`) and the clock is injected,
/// mirroring the LaunchAgentInstallerTests mocking idioms. Log freshness
/// is exercised with real temp files so mtime parsing is honest.
@Suite
struct LettaChannelsHealthProbeTests {
    /// Shell mock that answers each exact invocation with a canned
    /// result — deterministic because the probe issues exactly two
    /// commands (launchctl print, pgrep).
    private struct ScriptedShell: ShellExecuting {
        let results: [String: ShellResult]

        /// Answers keyed by argv0 basename (launchctl / pgrep / env)
        /// plus a catch-all default so unknown probes fail loud, not
        /// silently green.
        func execute(_ arguments: [String]) async throws -> ShellResult {
            // Key by argv0 basename. Keying on the second token missed
            // `pgrep -f` (second token is `-f`) so every running mock
            // collapsed to false and the suite was a lie.
            let key = (arguments.first as? NSString)?.lastPathComponent ?? ""
            return results[key] ?? ShellResult(success: false, output: "unexpected: \(arguments)")
        }
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("letta-channels-probe-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeLog(_ dir: URL, mtime: Date) -> URL {
        let url = dir.appendingPathComponent("letta-channels.out.log")
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        try! FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
        return url
    }

    /// Loaded + running + fresh log → healthy, no stale flag. This is
    /// the zero-exit-code contract `andromeda fleet status` relies on.
    @Test
    func healthyWhenLoadedRunningAndLogFresh() async {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = writeLog(dir, mtime: Date(timeIntervalSinceNow: -60))
        let now = Date()

        let probe = LettaChannelsHealthProbe(
            uid: 501,
            logPath: log.path,
            shell: ScriptedShell(results: [
                "launchctl": ShellResult(success: true, output: ""),
                "pgrep": ShellResult(success: true, output: "4242"),
            ]),
            now: { now }
        )
        let report = await probe.probe()

        #expect(report.loaded)
        #expect(report.running)
        #expect(report.healthy)
        #expect(!report.logStale)
        #expect(report.logAge != nil)
    }

    /// Not loaded → unhealthy even though pgrep would pass: a stray
    /// hand-run daemon must not mask a missing launchd registration
    /// (the original 10-day incident was exactly an unloaded agent).
    @Test
    func unhealthyWhenAgentNotLoaded() async {
        let probe = LettaChannelsHealthProbe(
            uid: 501,
            shell: ScriptedShell(results: [
                "launchctl": ShellResult(success: false, output: "Could not find service"),
                "pgrep": ShellResult(success: true, output: "4242"),
            ]),
            now: { Date() }
        )
        let report = await probe.probe()

        #expect(!report.loaded)
        #expect(report.running)
        #expect(!report.healthy)
    }

    /// Loaded but process absent → unhealthy: launchd knows the job
    /// yet nothing is exec'ing it (exec-loop, crash-loop, or bootout
    /// residue) — the case where KeepAlive is hammering.
    @Test
    func unhealthyWhenProcessAbsent() async {
        let probe = LettaChannelsHealthProbe(
            uid: 501,
            shell: ScriptedShell(results: [
                "launchctl": ShellResult(success: true, output: ""),
                "pgrep": ShellResult(success: false, output: ""),
            ]),
            now: { Date() }
        )
        let report = await probe.probe()

        #expect(report.loaded)
        #expect(!report.running)
        #expect(!report.healthy)
    }

    /// Log older than the threshold → stale warning but still healthy:
    /// a live process with a quiet hour is suspicious, not proven-dead,
    /// so it must not fail the exit-code contract.
    @Test
    func staleLogWarnsWithoutFailingHealth() async {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let twoHoursAgo = Date(timeIntervalSinceNow: -7200)
        let log = writeLog(dir, mtime: twoHoursAgo)
        let now = Date()

        let probe = LettaChannelsHealthProbe(
            uid: 501,
            logPath: log.path,
            shell: ScriptedShell(results: [
                "launchctl": ShellResult(success: true, output: ""),
                "pgrep": ShellResult(success: true, output: "1"),
            ]),
            now: { now }
        )
        let report = await probe.probe()

        #expect(report.healthy)
        #expect(report.logStale)
        #expect(report.logAge ?? 0 > 3600)
    }

    /// Missing log → nil age, NOT stale: a freshly installed daemon
    /// has not written output yet and must not trip the staleness
    /// warning on its first probe.
    @Test
    func missingLogIsNotStale() async {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let probe = LettaChannelsHealthProbe(
            uid: 501,
            logPath: dir.appendingPathComponent("does-not-exist.log").path,
            shell: ScriptedShell(results: [
                "launchctl": ShellResult(success: true, output: ""),
                "pgrep": ShellResult(success: true, output: "1"),
            ]),
            now: { Date() }
        )
        let report = await probe.probe()

        #expect(report.logAge == nil)
        #expect(!report.logStale)
        #expect(report.healthy)
    }

    /// The probe must query the gui/<uid> domain of the injected uid —
    /// asserting the exact launchctl invocation guards against
    /// accidentally probing the system domain (where user agents never
    /// appear and everything would look unloaded).
    @Test
    func launchctlPrintTargetsGuiDomainOfInjectedUID() async {
        let shell = RecordingInvocationShell()
        let probe = LettaChannelsHealthProbe(
            uid: 1234,
            logPath: "/nonexistent",
            shell: shell,
            now: { Date() }
        )
        _ = await probe.probe()

        let launchctlCalls = await shell.launchctlCalls()
        #expect(launchctlCalls.contains(["/bin/launchctl", "print", "gui/1234/com.binarybros.letta-channels"]))
    }

    /// Empty tiers skip the catalog probe: no extra shell spawn, and
    /// `hasLiveTier` is false without failing `healthy`. Status must
    /// still be usable before anyone configures a cascade.
    @Test
    func emptyTiersSkipCatalogProbeAndDoNotFailHealth() async {
        let probe = LettaChannelsHealthProbe(
            uid: 501,
            tiers: [],
            shell: ScriptedShell(results: [
                "launchctl": ShellResult(success: true, output: ""),
                "pgrep": ShellResult(success: true, output: "1"),
            ]),
            now: { Date() }
        )
        let report = await probe.probe()
        #expect(report.healthy)
        #expect(report.tiers.isEmpty)
        #expect(!report.hasLiveTier)
    }

    /// A listed tier is live only when its handle appears in `letta
    /// model list` output. Substring match is the catalog contract —
    /// handles are unique namespaced strings.
    @Test
    func listedTierIsLiveWhenCatalogContainsHandle() async {
        let probe = LettaChannelsHealthProbe(
            uid: 501,
            tiers: [.glm53, .xaiGrok46],
            shell: ScriptedShell(results: [
                "launchctl": ShellResult(success: true, output: ""),
                "pgrep": ShellResult(success: true, output: "1"),
                "env": ShellResult(
                    success: true,
                    output: "openai-compatible/glm/glm-5.3\n"
                ),
            ]),
            now: { Date() }
        )
        let report = await probe.probe()
        #expect(report.tierStatus[.glm53] == true)
        #expect(report.tierStatus[.xaiGrok46] == false)
        #expect(report.hasLiveTier)
        #expect(report.healthy)
    }

    /// Nonempty cascade with zero live handles is unhealthy: the
    /// daemon cannot serve Slack even if launchd and the PID are up.
    @Test
    func allConfiguredTiersDeadFailsHealth() async {
        let probe = LettaChannelsHealthProbe(
            uid: 501,
            tiers: [.xaiGrok46],
            shell: ScriptedShell(results: [
                "launchctl": ShellResult(success: true, output: ""),
                "pgrep": ShellResult(success: true, output: "1"),
                "env": ShellResult(success: true, output: "openai-compatible/glm/glm-5.3\n"),
            ]),
            now: { Date() }
        )
        let report = await probe.probe()
        #expect(report.loaded)
        #expect(report.running)
        #expect(!report.hasLiveTier)
        #expect(!report.healthy)
    }

    /// Records every invocation so tests can assert exact commands.
    private actor RecordingInvocationShell: ShellExecuting {
        private var calls: [[String]] = []

        func execute(_ arguments: [String]) async throws -> ShellResult {
            calls.append(arguments)
            return ShellResult(success: false, output: "")
        }

        func launchctlCalls() -> [[String]] {
            calls.filter { $0.first == "/bin/launchctl" }
        }
    }
}
