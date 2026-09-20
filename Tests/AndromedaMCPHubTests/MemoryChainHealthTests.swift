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
    private func proofPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-chain-proof-\(UUID().uuidString).json").path
    }

    /// Save → load round-trips legs, statuses, and dates.
    @Test("proof state round-trips through disk")
    func roundTrips() throws {
        let path = proofPath()
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
        let path = proofPath()
        let loaded = try MemoryChainProofStore.load(from: path)
        #expect(loaded == nil)
    }

    /// A future schema version must throw, not guess — the HUD shows an
    /// honest failure instead of misreading fields.
    @Test("newer schema version is rejected")
    func rejectsNewerVersion() throws {
        let path = proofPath()
        let future = """
        {"version": 99, "lastRun": null, "legs": []}
        """
        try future.write(toFile: path, atomically: true, encoding: .utf8)
        #expect(throws: MemoryChainProofStoreError.unsupportedVersion(99)) {
            _ = try MemoryChainProofStore.load(from: path)
        }
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
