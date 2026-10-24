@testable import AndromedaMCPHub
import Foundation
import Testing

// MARK: - Scrub

struct DiagnosticScrubTests {
    @Test("keeps an ordinary stderr line")
    func keepsOrdinaryLine() {
        let data = Data("Secure MCP Filesystem Server running on stdio\n".utf8)
        #expect(DiagnosticScrub.tail(data) == "Secure MCP Filesystem Server running on stdio")
    }

    @Test("replaces a credential-shaped line wholesale")
    func redactsCredentialLine() {
        let data = Data("boom api_key=super-secret-value\n".utf8)
        #expect(DiagnosticScrub.tail(data) == "<redacted>")
    }

    /// Codex P2: `API_KEY=` and `abc123\n` arrive as two pipe reads. The
    /// first slice must not be logged, and the completed line must redact.
    @Test("a credential split across pipe reads is one redacted line")
    func splitCredentialIsOneRedactedLine() {
        let assembler = BoundedDiagnosticAssembler()
        let first = DiagnosticScrub.completedLines(Data("API_KEY=".utf8), assembler: assembler)
        #expect(first.isEmpty)
        let second = DiagnosticScrub.completedLines(
            Data("abc123-example-value\n".utf8), assembler: assembler
        )
        #expect(second == ["<redacted>"])
        #expect(!second.joined().contains("abc123"))
    }

    @Test("an unterminated flood is dropped, not retained or emitted in pieces")
    func oversizedLineIsDroppedWhole() {
        let assembler = BoundedDiagnosticAssembler(limit: 8)
        let flood = DiagnosticScrub.completedLines(Data(repeating: 0x41, count: 64), assembler: assembler)
        #expect(flood.isEmpty)
        #expect(assembler.pendingByteCount <= 8)
        let closed = DiagnosticScrub.completedLines(Data("SECRET\n".utf8), assembler: assembler)
        #expect(closed == [BoundedDiagnosticAssembler.droppedMarker])
        #expect(!closed.joined().contains("SECRET"))
        #expect(!closed.joined().contains("AAAA"))
    }

    @Test("carriage-return progress does not accumulate")
    func carriageReturnEndsTheLine() {
        let assembler = BoundedDiagnosticAssembler(limit: 32)
        let lines = DiagnosticScrub.completedLines(Data("one\rtwo\r".utf8), assembler: assembler)
        #expect(lines == ["one", "two"])
        #expect(assembler.pendingByteCount == 0)
    }
}

// MARK: - Census

struct UpstreamCensusTests {
    @Test("last lifecycle kind wins, and a listening socket can still be exhausted")
    func lastKindWins() {
        let log = """
        {"kind":"upstream.spawned","f_server":"filesystem"}
        {"kind":"shim.connected","f_server":"filesystem"}
        {"kind":"upstream.exhausted","f_server":"filesystem"}
        {"kind":"upstream.spawned","f_server":"memory"}
        """
        let phases = UpstreamCensus.phases(in: log)
        #expect(phases["filesystem"] == .exhausted)
        #expect(phases["memory"] == .up)
    }

    @Test("a later spawn clears exhaustion")
    func spawnClearsExhaustion() {
        let log = """
        {"kind":"upstream.exhausted","f_server":"memory"}
        {"kind":"upstream.rearmed","f_server":"memory"}
        {"kind":"upstream.spawned","f_server":"memory"}
        """
        #expect(UpstreamCensus.phases(in: log)["memory"] == .up)
    }
}

// MARK: - Supervisor rearm

struct ReaderBindingTests {
    @Test("a second shim on the same stderr handle does not take the binding")
    func samePipeIsNotRebound() {
        let server = HostedServer(
            config: HubServerConfig(
                id: "filesystem",
                packageName: "example",
                command: "/usr/bin/true",
                duplicateGroup: "filesystem"
            ),
            host: CountingHost(),
            telemetry: HubTelemetry(jsonlPath: "/tmp/andromeda-mcp-hub-bind-test.jsonl")
        )
        let pipe = Pipe()
        #expect(server.claimReaderBinding(stderr: pipe.fileHandleForReading))
        #expect(!server.claimReaderBinding(stderr: pipe.fileHandleForReading))
        let respawned = Pipe()
        #expect(server.claimReaderBinding(stderr: respawned.fileHandleForReading))
    }
}

struct UpstreamSupervisorRearmTests {
    @Test("budget sticks until the cooldown, then a launch is allowed again")
    func rearmAfterCooldown() {
        let host = CountingHost()
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let supervisor = UpstreamSupervisor(
            config: HubServerConfig(
                id: "filesystem",
                packageName: "example",
                command: "/usr/bin/true",
                duplicateGroup: "filesystem"
            ),
            host: host,
            telemetry: HubTelemetry(jsonlPath: "/tmp/andromeda-mcp-hub-rearm-test.jsonl"),
            maxRestarts: 2,
            rearmInterval: 60,
            now: { clock.now() }
        )
        defer { supervisor.forgetForTeardown() }

        #expect(supervisor.ensureRunning() != nil)
        supervisor.upstreamExited()
        clock.advance(31)
        #expect(supervisor.ensureRunning() != nil)
        supervisor.upstreamExited()
        clock.advance(31)
        // count is now 2 — the next call is the exhausted refusal
        #expect(supervisor.ensureRunning() == nil)
        clock.advance(59)
        #expect(supervisor.ensureRunning() == nil)
        clock.advance(2)
        #expect(supervisor.ensureRunning() != nil)
        #expect(host.launches == 3)
    }
}

/// Protocol stand-in. Tests never spawn a real process.
/// `@unchecked Sendable`: `lock` guards `launches`. No other mutable state.
private final class CountingHost: UpstreamProcessHosting, @unchecked Sendable {
    private let lock = NSLock()
    private var _launches = 0

    var launches: Int {
        lock.lock()
        defer { lock.unlock() }
        return _launches
    }

    func launch(command: String, arguments: [String], environment: [String: String]) -> UpstreamPipes? {
        lock.lock()
        _launches += 1
        lock.unlock()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        return UpstreamPipes(
            stdin: stdin.fileHandleForWriting,
            stdout: stdout.fileHandleForReading,
            stderr: stderr.fileHandleForReading
        )
    }
}

/// `@unchecked Sendable`: `lock` guards `date`. The supervisor reads it from
/// a `@Sendable` clock closure, so the box has to cross that boundary.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        date.addTimeInterval(seconds)
        lock.unlock()
    }
}
