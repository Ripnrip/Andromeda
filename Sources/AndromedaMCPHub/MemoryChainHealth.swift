import Foundation

// MARK: - Telemetry record

/// One decoded line of the hub telemetry JSONL (`HubTelemetry.encode` format:
/// `{"ts": ..., "kind": ..., "f_<field>": ...}`).
public struct HubTelemetryRecord: Sendable, Equatable {
    /// Parsed `ts` (ISO-8601, UTC, no fractional seconds — the encoder's format).
    public let timestamp: Date
    /// Stable event kind (`hub.started`, `upstream.spawn_failed`, …).
    public let kind: String
    /// Decoded `f_*` fields with the prefix stripped.
    public let fields: [String: String]

    public init(timestamp: Date, kind: String, fields: [String: String] = [:]) {
        self.timestamp = timestamp
        self.kind = kind
        self.fields = fields
    }

    /// Server id this record is about, when the event carries one.
    public var serverID: String? {
        fields["server"]
    }
}

// MARK: - Telemetry reader

/// Reads the tail of the hub telemetry JSONL. Missing file is an empty tail
/// (a hub that never ran yet is "no events", not an error); a malformed line
/// is counted, never silently dropped.
public enum HubTelemetryReader {
    /// Backward-scan chunk size — memory bound per iteration, not a line bound.
    private static let chunkBytes = 64 * 1024
    /// A telemetry line longer than this is treated as one undecodable record
    /// (`skippedLines`), never buffered whole (Cursor security review on #84:
    /// an unterminated multi-MB blob must not become a multi-MB allocation).
    private static let maxLineBytes = 1024 * 1024

    /// Decodes the last `limit` records from `path`.
    /// - Returns: records in file order plus how many trailing lines failed to decode.
    public static func tail(path: String, limit: Int = 50) throws -> (records: [HubTelemetryRecord], skippedLines: Int) {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            return ([], 0)
        }
        let lines = try lastCompleteLines(at: expanded, limit: max(0, limit))

        let formatter = ISO8601DateFormatter()
        var records: [HubTelemetryRecord] = []
        var skipped = 0
        for line in lines {
            guard let line,
                  let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let kind = object["kind"] as? String,
                  let ts = object["ts"] as? String,
                  let date = formatter.date(from: ts)
            else {
                skipped += 1
                continue
            }
            var fields: [String: String] = [:]
            for (key, value) in object where key.hasPrefix("f_") {
                if let string = value as? String {
                    fields[String(key.dropFirst(2))] = string
                }
            }
            records.append(HubTelemetryRecord(timestamp: date, kind: kind, fields: fields))
        }
        return (records, skipped)
    }

    /// Collects the newest `limit` complete non-empty lines by seeking to
    /// end-of-file and scanning backward in fixed chunks. The telemetry log
    /// grows without bound over the hub's lifetime, so the reader must never
    /// load it whole — only `chunkBytes` + one line are ever in memory.
    /// A `nil` element is a line that exceeded `maxLineBytes` (counted, not
    /// decoded). Returned in file order.
    private static func lastCompleteLines(at path: String, limit: Int) throws -> [Data?] {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        let size = Int(try handle.seekToEnd())
        guard size > 0, limit > 0 else { return [] }

        var newestFirst: [Data?] = []   // newest → oldest
        var pending = Data()            // tail of a line whose head lies in an earlier chunk
        var position = size

        while position > 0 {
            if pending.count > maxLineBytes {
                // Pathological unterminated blob: stop walking older history,
                // report it as one skipped line. Older real lines past the
                // blob are unreachable without buffering it — not worth it.
                newestFirst.append(nil)
                break
            }
            let readSize = min(chunkBytes, position)
            position -= readSize
            try handle.seek(toOffset: UInt64(position))
            var data = try handle.read(upToCount: readSize) ?? Data()
            data.append(pending)
            pending = Data()

            // data spans [position, scannedEnd): its first segment may be an
            // incomplete line head; every later segment is newline-terminated.
            var segments: [Data] = []
            var start = data.startIndex
            while let newline = data[start...].firstIndex(of: UInt8(ascii: "\n")) {
                segments.append(data[start ..< newline])
                start = data.index(after: newline)
            }
            segments.append(data[start...])  // tail after the final newline (may be empty)
            pending = segments.removeFirst()
            for segment in segments.reversed() where !segment.isEmpty {
                newestFirst.append(segment)
                if newestFirst.count == limit {
                    return newestFirst.reversed()
                }
            }
        }
        // position == 0: whatever is still pending is the file's first line.
        if !pending.isEmpty, pending.count <= maxLineBytes, newestFirst.count < limit {
            newestFirst.append(pending)
        }
        return newestFirst.reversed()
    }
}

// MARK: - Upstream digest

/// Typed rollup of the telemetry tail: what the operator needs to know about
/// upstream daemons and shim connections without reading raw log lines.
public struct HubUpstreamDigest: Sendable, Equatable {
    /// Live shim connections per server (`shim.connected` minus `shim.disconnected`).
    public let connectionsByServer: [String: Int]
    /// Upstream exits per server — restart pressure.
    public let restartsByServer: [String: Int]
    /// Spawn failures per server.
    public let spawnFailuresByServer: [String: Int]
    /// Servers whose restart budget is exhausted (hub answers shims itself).
    public let exhaustedServers: Set<String>

    /// Folds records oldest → newest into per-server counters.
    public static func digest(_ records: [HubTelemetryRecord]) -> HubUpstreamDigest {
        var connections: [String: Int] = [:]
        var restarts: [String: Int] = [:]
        var failures: [String: Int] = [:]
        var exhausted: Set<String> = []
        for record in records {
            guard let server = record.serverID else { continue }
            switch record.kind {
            case "shim.connected":
                connections[server, default: 0] += 1
            case "shim.disconnected":
                connections[server, default: 0] -= 1
            case "upstream.exited":
                restarts[server, default: 0] += 1
            case "upstream.spawn_failed":
                failures[server, default: 0] += 1
            case "upstream.exhausted":
                exhausted.insert(server)
            default:
                break
            }
        }
        // A hub restart replays nothing (JSONL persists), but clamp negatives
        // in case a disconnected tail was rotated away.
        let clamped = connections.mapValues { max(0, $0) }
        return HubUpstreamDigest(
            connectionsByServer: clamped,
            restartsByServer: restarts,
            spawnFailuresByServer: failures,
            exhaustedServers: exhausted
        )
    }
}

// MARK: - Proof state (ADR-0020)

/// One leg of the canonical-verbs full-chain proof (HAB-602 / BIN-197 lane
/// writes these; the HUD reads them).
public struct MemoryChainProofLeg: Sendable, Equatable, Codable {
    /// Stable leg id (`agent-to-agent`, `letta-ingress`, …).
    public let id: String
    /// pass / fail / pending — a leg without a result is `pending`, not absent.
    public let status: Status
    /// When this leg last ran, if ever.
    public let at: Date?
    /// Operator-facing one-liner (what was proven, how).
    public let detail: String

    public enum Status: String, Sendable, Codable {
        case pass
        case fail
        case pending
    }

    public init(id: String, status: Status, at: Date? = nil, detail: String = "") {
        self.id = id
        self.status = status
        self.at = at
        self.detail = detail
    }
}

/// Versioned document at `~/.andromeda/proofs/memory-chain.json` (ADR-0020).
public struct MemoryChainProofState: Sendable, Equatable, Codable {
    public let version: Int
    /// When the whole proof last ran (max leg `at`, or explicit).
    public let lastRun: Date?
    public let legs: [MemoryChainProofLeg]

    public init(version: Int = MemoryChainProofStore.version, lastRun: Date? = nil, legs: [MemoryChainProofLeg]) {
        self.version = version
        self.lastRun = lastRun
        self.legs = legs
    }
}

public enum MemoryChainProofStoreError: Error, Equatable {
    /// Future schema — the reader must not guess at fields it does not know.
    case unsupportedVersion(Int)
    /// Writes are confined to the canonical proofs directory (ADR-0020):
    /// the store never creates directory trees or files elsewhere.
    case pathOutsideSandbox(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "proof-state schema version \(version) is newer than this reader (ADR-0020)"
        case let .pathOutsideSandbox(path):
            "refusing to write proof state outside ~/.andromeda/proofs: \(path)"
        }
    }
}

/// Loads/stores the proof-state document. Absent file is `nil` (proof not
/// run yet — honest 🚧, not an error); a version mismatch throws.
public enum MemoryChainProofStore {
    public static let version = 1
    public static let defaultPath = "~/.andromeda/proofs/memory-chain.json"

    /// Canonical write boundary (ADR-0020): every write lands inside
    /// `~/.andromeda/proofs/` — resolved, standardized, symlink-free prefix.
    public static var sandboxDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".andromeda/proofs")
            .standardizedFileURL
    }

    /// True when `path` resolves to the sandbox directory or something inside it.
    public static func isInsideSandbox(_ path: String) -> Bool {
        let resolved = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL.path
        let sandbox = sandboxDirectory.path
        return resolved == sandbox || resolved.hasPrefix(sandbox + "/")
    }

    public static func load(from path: String) throws -> MemoryChainProofState? {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        let url = URL(fileURLWithPath: expanded)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(MemoryChainProofState.self, from: data)
        guard state.version <= version else {
            throw MemoryChainProofStoreError.unsupportedVersion(state.version)
        }
        return state
    }

    public static func save(_ state: MemoryChainProofState, to path: String) throws {
        guard isInsideSandbox(path) else {
            throw MemoryChainProofStoreError.pathOutsideSandbox(
                URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
            )
        }
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url)
    }
}

// MARK: - Health report

/// Per-server probe + config truth for one hosted MCP server.
public struct MemoryChainServerRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let placement: HubPlacement
    /// Socket census result — listening means a hub accepted the connection.
    public let probe: ProbeOutcome
    /// Whether the resolved executable exists (spawn would fail otherwise).
    public let executableResolves: Bool

    public init(id: String, placement: HubPlacement, probe: ProbeOutcome, executableResolves: Bool) {
        self.id = id
        self.placement = placement
        self.probe = probe
        self.executableResolves = executableResolves
    }
}

/// Headline proof rollup for the HUD line.
public enum MemoryChainProofSummary: Sendable, Equatable {
    /// Every leg passed.
    case passed(legCount: Int, lastRun: Date?)
    /// At least one leg failed — chain is not proven.
    case failed(failedLegs: [String], lastRun: Date?)
    /// No failures, but legs still pending (or the file is absent entirely
    /// with legs never recorded — `legs: []`).
    case partial(pendingLegs: [String], lastRun: Date?)
    /// No proof document on disk.
    case notRecorded
}

public enum MemoryChainOverallStatus: String, Sendable, Equatable {
    case green
    case yellow
    case red
    case unknown
}

/// The operator-facing memory-chain snapshot the HUD `memory_health`
/// capability renders (HAB-599 / BIN-287).
public struct MemoryChainHealthReport: Sendable, Equatable {
    public let overall: MemoryChainOverallStatus
    public let headline: String
    public let servers: [MemoryChainServerRow]
    public let digest: HubUpstreamDigest
    /// Tail of notable telemetry, newest last (already trimmed by the builder).
    public let recentEvents: [HubTelemetryRecord]
    public let proof: MemoryChainProofSummary
    public let generatedAt: Date
}

/// Assembles a `MemoryChainHealthReport` from config + live probe + telemetry
/// tail + proof state. Pure function of its inputs — no IO — so tests fixture
/// everything.
public enum MemoryChainHealth {
    /// How many trailing telemetry records ride along in the report.
    public static let recentEventLimit = 6

    public static func build(
        configuration: MCPHubConfiguration?,
        probe: @Sendable (String) -> ProbeOutcome,
        telemetryRecords: [HubTelemetryRecord],
        proof: MemoryChainProofState?,
        now: Date = Date()
    ) -> MemoryChainHealthReport {
        guard let configuration, !configuration.servers.isEmpty else {
            return MemoryChainHealthReport(
                overall: .unknown,
                headline: "No hub config — memory chain not deployed (ADR-0019)",
                servers: [],
                digest: .init(
                    connectionsByServer: [:], restartsByServer: [:],
                    spawnFailuresByServer: [:], exhaustedServers: []
                ),
                recentEvents: [],
                proof: summarize(proof: proof),
                generatedAt: now
            )
        }

        var rows: [MemoryChainServerRow] = []
        for server in configuration.servers {
            let outcome = probe(configuration.socketPath(for: server.id))
            let resolves = FileManager.default.isExecutableFile(
                atPath: (server.command as NSString).expandingTildeInPath
            )
            rows.append(
                MemoryChainServerRow(
                    id: server.id,
                    placement: server.placement,
                    probe: outcome,
                    executableResolves: resolves
                )
            )
        }

        let digest = HubUpstreamDigest.digest(telemetryRecords)
        let proofSummary = summarize(proof: proof)
        let recent = Array(telemetryRecords.suffix(recentEventLimit))

        return MemoryChainHealthReport(
            overall: overall(rows: rows, digest: digest, proof: proofSummary),
            headline: headline(rows: rows, digest: digest, proof: proofSummary),
            servers: rows,
            digest: digest,
            recentEvents: recent,
            proof: proofSummary,
            generatedAt: now
        )
    }

    // MARK: Derivations

    private static func summarize(proof: MemoryChainProofState?) -> MemoryChainProofSummary {
        guard let proof, !proof.legs.isEmpty else { return .notRecorded }
        let failed = proof.legs.filter { $0.status == .fail }.map(\.id)
        let pending = proof.legs.filter { $0.status == .pending }.map(\.id)
        if !failed.isEmpty {
            return .failed(failedLegs: failed, lastRun: proof.lastRun)
        }
        if !pending.isEmpty {
            return .partial(pendingLegs: pending, lastRun: proof.lastRun)
        }
        return .passed(legCount: proof.legs.count, lastRun: proof.lastRun)
    }

    private static func overall(
        rows: [MemoryChainServerRow],
        digest: HubUpstreamDigest,
        proof: MemoryChainProofSummary
    ) -> MemoryChainOverallStatus {
        if rows.contains(where: { !$0.probe.isListening })
            || !digest.exhaustedServers.isEmpty
        {
            return .red
        }
        if case .failed = proof {
            return .red
        }
        if digest.spawnFailuresByServer.values.contains(where: { $0 > 0 })
            || digest.restartsByServer.values.contains(where: { $0 > 0 })
        {
            return .yellow
        }
        if case .partial = proof {
            return .yellow
        }
        if case .notRecorded = proof {
            return .yellow
        }
        return .green
    }

    private static func headline(
        rows: [MemoryChainServerRow],
        digest: HubUpstreamDigest,
        proof: MemoryChainProofSummary
    ) -> String {
        let listening = rows.filter { $0.probe.isListening }.count
        let census = "\(listening)/\(rows.count) servers listening"
        let proofLine: String
        switch proof {
        case let .passed(count, _):
            proofLine = "proof pass \(count)/\(count)"
        case let .failed(failed, _):
            proofLine = "proof FAIL: \(failed.joined(separator: ", "))"
        case let .partial(pending, _):
            proofLine = "proof pending: \(pending.joined(separator: ", "))"
        case .notRecorded:
            proofLine = "proof not recorded 🚧"
        }
        var extras: [String] = []
        if !digest.exhaustedServers.isEmpty {
            extras.append("exhausted: \(digest.exhaustedServers.sorted().joined(separator: ", "))")
        }
        let suffix = extras.isEmpty ? "" : " — " + extras.joined(separator: ", ")
        return "Chain · \(census) · \(proofLine)\(suffix)"
    }
}
