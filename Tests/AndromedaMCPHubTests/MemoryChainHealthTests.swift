@testable import AndromedaMCPHub
import Foundation
import Testing

// MARK: - HubTelemetryReader (tail decode of the JSONL telemetry stream)

struct HubTelemetryReaderTests {
    /// Writes lines in the encoder's exact wire format, then reads the tail.
    private func writeFixture(_ lines: [String]) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub-telemetry-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// Verifies the reader round-trips what `HubTelemetry.encode` writes:
    /// ts, kind, and f_-prefixed fields with the prefix stripped.
    @Test("tail decodes encoder-format lines in file order")
    func roundTripsEncoderFormat() throws {
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        let lines = [
            HubTelemetry.encode(
                event: .hubStarted(socketDirectory: "/tmp/sockets", servers: 2), at: base
            ),
            HubTelemetry.encode(
                event: .shimConnected(serverID: "memory", connection: "codex-7"), at: base.addingTimeInterval(1)
            ),
        ]
        let path = try writeFixture(lines)
        let (records, skipped) = try HubTelemetryReader.tail(path: path)

        #expect(skipped == 0)
        #expect(records.count == 2)
        #expect(records[0].kind == "hub.started")
        #expect(records[0].fields["socket_directory"] == "/tmp/sockets")
        #expect(records[0].fields["servers"] == "2")
        #expect(records[1].kind == "shim.connected")
        #expect(records[1].serverID == "memory")
        #expect(records[1].timestamp == base.addingTimeInterval(1))
    }

    /// Tail limit honors the suffix only — the HUD wants recent events, not a re-read of history.
    @Test("tail respects the limit with the newest suffix")
    func tailLimitKeepsSuffix() throws {
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        let lines = (0..<5).map { offset in
            HubTelemetry.encode(
                event: .shimConnected(serverID: "s\(offset)", connection: "c"), at: base.addingTimeInterval(Double(offset))
            )
        }
        let path = try writeFixture(lines)
        let (records, skipped) = try HubTelemetryReader.tail(path: path, limit: 2)

        #expect(skipped == 0)
        #expect(records.map(\.kind) == ["shim.connected", "shim.connected"])
        #expect(records.map { $0.fields["server"] } == ["s3", "s4"])
    }

    /// A malformed trailing line is counted, never silently dropped — the
    /// operator sees the skip in the unified log (HUDModel liveChainHealth).
    @Test("malformed lines are counted as skipped")
    func malformedLinesAreCounted() throws {
        let path = try writeFixture(["{not json", "{\"ts\":\"2026-09-20T00:00:00Z\",\"kind\":\"hub.started\"}"])
        let (records, skipped) = try HubTelemetryReader.tail(path: path)

        #expect(skipped == 1)
        #expect(records.count == 1)
        #expect(records[0].kind == "hub.started")
    }

    /// A hub that never ran has no telemetry file — that is an empty tail, not an error.
    @Test("missing telemetry file reads as empty tail")
    func missingFileIsEmptyTail() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).jsonl").path
        let (records, skipped) = try HubTelemetryReader.tail(path: missing)
        #expect(records.isEmpty)
        #expect(skipped == 0)
    }

    /// The reader scans backward in chunks — a large history must still yield
    /// the newest records (Cursor security review on #84: unbounded read).
    @Test("tail is bounded on a large history")
    func tailBoundedOnLargeHistory() throws {
        // ~200k small lines: far past one 64 KB chunk, cheap to write.
        let stamp = "2026-09-20T08:00:00Z"
        let lines = (0 ..< 200_000).map { "{\"ts\":\"\(stamp)\",\"kind\":\"upstream.heartbeat\",\"f_server\":\"s\($0 % 4)\"}" }
        let path = try writeFixture(lines)

        let (records, skipped) = try HubTelemetryReader.tail(path: path, limit: 10)
        #expect(records.count == 10)
        #expect(skipped == 0)
        // exact suffix: window is lines 199_990...199_999 → s2...s3.
        #expect(records.last?.fields["server"] == "s3")
        #expect(records.first?.fields["server"] == "s2")
        try? FileManager.default.removeItem(atPath: path)
    }

    /// A pathological unterminated blob is one skipped line, not a whole-file
    /// allocation — and the newest real records still come through when the
    /// blob is older than the requested window.
    @Test("unterminated blob is skipped, not buffered")
    func unterminatedBlobIsSkippedNotBuffered() throws {
        let stamp = "2026-09-20T08:00:00Z"
        let good = "{\"ts\":\"\(stamp)\",\"kind\":\"shim.connected\",\"f_server\":\"memory\"}"
        let blob = String(repeating: "x", count: 2 * 1024 * 1024)  // 2 MiB, no newline
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub-telemetry-\(UUID().uuidString).jsonl")
        try ([blob, good, good].joined(separator: "\n") as String)
            .write(to: url, atomically: true, encoding: .utf8)

        let (records, skipped) = try HubTelemetryReader.tail(path: url.path, limit: 10)
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.kind == "shim.connected" })
        #expect(skipped == 1)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - HubUpstreamDigest (telemetry fold)

struct HubUpstreamDigestTests {
    private func record(_ kind: String, server: String) -> HubTelemetryRecord {
        HubTelemetryRecord(timestamp: Date(), kind: kind, fields: ["server": server])
    }

    /// Connection math, restart pressure, and exhaustion fold correctly
    /// across one server's stream.
    @Test("digest folds connections, restarts, failures, exhaustion")
    func foldsCounters() {
        let digest = HubUpstreamDigest.digest([
            record("shim.connected", server: "filesystem"),
            record("shim.connected", server: "filesystem"),
            record("shim.disconnected", server: "filesystem"),
            record("shim.connected", server: "memory"),
            record("upstream.exited", server: "memory"),
            record("upstream.exited", server: "memory"),
            record("upstream.spawn_failed", server: "memory"),
            record("upstream.exhausted", server: "memory"),
        ])

        #expect(digest.connectionsByServer["filesystem"] == 1)
        #expect(digest.connectionsByServer["memory"] == 1)
        #expect(digest.restartsByServer["memory"] == 2)
        #expect(digest.spawnFailuresByServer["memory"] == 1)
        #expect(digest.exhaustedServers == ["memory"])
    }

    /// A rotated-away `shim.disconnected` must not produce a negative count.
    @Test("negative connection counts clamp to zero")
    func clampsNegativeConnections() {
        let digest = HubUpstreamDigest.digest([
            record("shim.disconnected", server: "memory"),
        ])
        #expect(digest.connectionsByServer["memory"] == 0)
    }
}

// MARK: - MemoryChainProofStore (ADR-0020 document)

struct MemoryChainProofStoreTests {
    /// Test path INSIDE the canonical sandbox (writes are confined there,
    /// per ADR-0020 + Cursor security review on #84). Cleaned up after.
    private func sandboxedProofPath() -> String {
        MemoryChainProofStore.sandboxDirectory
            .appendingPathComponent("test-\(UUID().uuidString).json").path
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Every test that writes (directly or via save) must be self-sufficient:
    /// the sandbox directory may not exist on a fresh machine (CI runner),
    /// and swift-testing's parallel ordering means no other test can be
    /// relied on to have created it (post-#84 main-run lesson).
    private func ensureSandboxExists() throws {
        try FileManager.default.createDirectory(
            at: MemoryChainProofStore.sandboxDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Save → load round-trips legs, statuses, and dates.
    @Test("proof state round-trips through disk")
    func roundTrips() throws {
        let path = sandboxedProofPath()
        defer { cleanup(path) }
        let when = Date(timeIntervalSince1970: 1_760_000_000)
        let state = MemoryChainProofState(
            lastRun: when,
            legs: [
                MemoryChainProofLeg(id: "agent-to-agent", status: .pass, at: when, detail: "store→recall across agents"),
                MemoryChainProofLeg(id: "letta-ingress", status: .pending),
            ]
        )
        try MemoryChainProofStore.save(state, to: path)
        let loaded = try MemoryChainProofStore.load(from: path)

        #expect(loaded == state)
    }

    /// No document yet means the proof has not been run — nil, not an error.
    @Test("absent proof document loads as nil")
    func absentFileIsNil() throws {
        let path = sandboxedProofPath()
        defer { cleanup(path) }
        let loaded = try MemoryChainProofStore.load(from: path)
        #expect(loaded == nil)
    }

    /// A future schema version must throw, not guess — the HUD shows an
    /// honest failure instead of misreading fields.
    @Test("newer schema version is rejected")
    func rejectsNewerVersion() throws {
        let path = sandboxedProofPath()
        defer { cleanup(path) }
        try ensureSandboxExists()  // atomically: writes need an existing parent
        let future = """
        {"version": 99, "lastRun": null, "legs": []}
        """
        try future.write(toFile: path, atomically: true, encoding: .utf8)
        #expect(throws: MemoryChainProofStoreError.unsupportedVersion(99)) {
            _ = try MemoryChainProofStore.load(from: path)
        }
    }

    /// The write side is confined to `~/.andromeda/proofs/` — a path outside
    /// throws before any directory is created (filesystem_workspace_boundary,
    /// Cursor security review on #84).
    @Test("save outside the proofs sandbox is refused")
    func saveOutsideSandboxRefused() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("escape-\(UUID().uuidString)")
            .appendingPathComponent("memory-chain.json").path
        defer { try? FileManager.default.removeItem(atPath: outside) }

        #expect(throws: MemoryChainProofStoreError.pathOutsideSandbox(outside)) {
            try MemoryChainProofStore.save(
                MemoryChainProofState(legs: [MemoryChainProofLeg(id: "x", status: .pass)]),
                to: outside
            )
        }
        #expect(!FileManager.default.fileExists(atPath: outside))
    }

    /// The prefix check must not be fooled by sibling directories that share
    /// a prefix (`~/.andromeda/proofs-not/` is outside).
    @Test("sandbox prefix check rejects sibling directory names")
    func prefixCheckRejectsSiblings() {
        let sibling = MemoryChainProofStore.sandboxDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("proofs-not")
            .appendingPathComponent("memory-chain.json").path
        #expect(!MemoryChainProofStore.isInsideSandbox(sibling))
        #expect(MemoryChainProofStore.isInsideSandbox(MemoryChainProofStore.defaultPath))
    }

    /// A symlink planted inside the sandbox cannot redirect a write outside
    /// it — ancestor symlinks are resolved on both sides of the comparison
    /// (Cursor security review on #84).
    @Test("symlinked directory inside the sandbox is resolved away")
    func symlinkEscapeIsRefused() throws {
        let escapedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("escape-target-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: escapedRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: escapedRoot) }

        // The sandbox directory may not exist yet (fresh CI runner) — this
        // test must not depend on another test having created it (post-merge
        // main run after #84: createSymbolicLink failed on a missing parent).
        try ensureSandboxExists()
        let linkPath = MemoryChainProofStore.sandboxDirectory
            .appendingPathComponent("link-\(UUID().uuidString)").path
        try FileManager.default.createSymbolicLink(
            atPath: linkPath, withDestinationPath: escapedRoot.path
        )
        defer { try? FileManager.default.removeItem(atPath: linkPath) }

        let throughLink = (linkPath as NSString)
            .appendingPathComponent("memory-chain.json")

        #expect(!MemoryChainProofStore.isInsideSandbox(throughLink))
        #expect(throws: MemoryChainProofStoreError.self) {
            try MemoryChainProofStore.save(
                MemoryChainProofState(legs: [MemoryChainProofLeg(id: "x", status: .pass)]),
                to: throughLink
            )
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: escapedRoot.appendingPathComponent("memory-chain.json").path
            )
        )
    }
}

// MARK: - MemoryChainHealth.build (report assembly)

struct MemoryChainHealthBuildTests {
    private func fixtureConfig() -> MCPHubConfiguration {
        MCPHubConfiguration(
            servers: [
                HubServerConfig(id: "filesystem", packageName: "server-filesystem", command: "/bin/ls", duplicateGroup: "fs"),
                HubServerConfig(id: "memory", packageName: "server-memory", command: "/bin/ls", duplicateGroup: "mem"),
            ]
        )
    }

    /// All listening + proof passed + clean telemetry = green, headline
    /// carries census and proof.
    @Test("all green when listening and proof passed")
    func greenWhenHealthy() {
        let report = MemoryChainHealth.build(
            configuration: fixtureConfig(),
            probe: { _ in .listening },
            telemetryRecords: [],
            proof: MemoryChainProofState(
                legs: [
                    MemoryChainProofLeg(id: "agent-to-agent", status: .pass),
                    MemoryChainProofLeg(id: "letta-ingress", status: .pass),
                ]
            )
        )

        #expect(report.overall == .green)
        #expect(report.servers.allSatisfy { $0.executableResolves })
        #expect(report.proof == .passed(legCount: 2, lastRun: nil))
        #expect(report.headline == "Chain · 2/2 servers listening · proof pass 2/2")
    }

    /// One socket down = red, and the headline names nobody — the rows carry
    /// the per-server refusal detail instead.
    @Test("down server is red")
    func redWhenServerDown() {
        let report = MemoryChainHealth.build(
            configuration: fixtureConfig(),
            probe: { path in path.contains("memory") ? .connectFailed(errno: 61) : .listening },
            telemetryRecords: [],
            proof: nil
        )

        #expect(report.overall == .red)
        #expect(report.servers.first { $0.id == "memory" }?.probe.isListening == false)
        #expect(report.headline.contains("1/2 servers listening"))
    }

    /// Missing proof document is honest yellow 🚧, not fake green — the
    /// chain may work but is not proven (HAB-602 gate).
    @Test("missing proof is yellow")
    func yellowWhenProofMissing() {
        let report = MemoryChainHealth.build(
            configuration: fixtureConfig(),
            probe: { _ in .listening },
            telemetryRecords: [],
            proof: nil
        )

        #expect(report.overall == .yellow)
        #expect(report.proof == .notRecorded)
        #expect(report.headline.contains("proof not recorded"))
    }

    /// Failed proof leg outranks everything else — red.
    @Test("failed proof leg is red")
    func redWhenProofFailed() {
        let report = MemoryChainHealth.build(
            configuration: fixtureConfig(),
            probe: { _ in .listening },
            telemetryRecords: [],
            proof: MemoryChainProofState(
                legs: [
                    MemoryChainProofLeg(id: "agent-to-agent", status: .pass),
                    MemoryChainProofLeg(id: "letta-ingress", status: .fail),
                ]
            )
        )

        #expect(report.overall == .red)
        guard case let .failed(legs, _) = report.proof else {
            Issue.record("expected failed summary")
            return
        }
        #expect(legs == ["letta-ingress"])
    }

    /// Restart pressure without a down socket degrades to yellow.
    @Test("upstream restarts degrade to yellow")
    func yellowUnderRestartPressure() {
        let report = MemoryChainHealth.build(
            configuration: fixtureConfig(),
            probe: { _ in .listening },
            telemetryRecords: [
                HubTelemetryRecord(timestamp: Date(), kind: "upstream.exited", fields: ["server": "memory"]),
            ],
            proof: MemoryChainProofState(legs: [MemoryChainProofLeg(id: "agent-to-agent", status: .pass)])
        )

        #expect(report.overall == .yellow)
        #expect(report.digest.restartsByServer["memory"] == 1)
    }

    /// No config at all: unknown status with the ADR pointer — never a
    /// zero-server "green".
    @Test("missing config is unknown with ADR pointer")
    func unknownWithoutConfig() {
        let report = MemoryChainHealth.build(
            configuration: nil,
            probe: { _ in .listening },
            telemetryRecords: [],
            proof: nil
        )

        #expect(report.overall == .unknown)
        #expect(report.servers.isEmpty)
        #expect(report.headline.contains("ADR-0019"))
    }

    /// An unresolvable executable is surfaced per-row (spawn would fail)
    /// without flipping the socket census.
    @Test("unresolved executable is surfaced on the row")
    func unresolvedExecutableFlagged() {
        let config = MCPHubConfiguration(
            servers: [
                HubServerConfig(id: "memory", packageName: "server-memory", command: "/nonexistent/definitely-missing", duplicateGroup: "mem"),
            ]
        )
        let report = MemoryChainHealth.build(
            configuration: config,
            probe: { _ in .listening },
            telemetryRecords: [],
            proof: nil
        )

        #expect(report.servers.first { $0.id == "memory" }?.executableResolves == false)
    }

    /// The report carries only the newest `recentEventLimit` records.
    @Test("recent events are trimmed to the limit")
    func recentEventsTrimmed() {
        let records = (0..<10).map { offset in
            HubTelemetryRecord(
                timestamp: Date(timeIntervalSince1970: Double(offset)),
                kind: "shim.connected",
                fields: ["server": "s\(offset)"]
            )
        }
        let report = MemoryChainHealth.build(
            configuration: fixtureConfig(),
            probe: { _ in .listening },
            telemetryRecords: records,
            proof: nil
        )

        #expect(report.recentEvents.count == MemoryChainHealth.recentEventLimit)
        #expect(report.recentEvents.last?.fields["server"] == "s9")
    }
}
