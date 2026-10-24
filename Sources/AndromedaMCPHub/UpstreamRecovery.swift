import Foundation

// MARK: - Diagnostic scrub

/// Last stderr line kept in telemetry. Credential-shaped lines are replaced
/// wholesale so a child that prints an env dump cannot land in the jsonl.
public enum DiagnosticScrub {
    private static let markers = [
        "api_key", "api-key", "apikey", "token", "secret", "password",
        "authorization", "bearer",
    ]

    /// The last line of `data`, clipped, with credential-shaped text removed.
    public static func tail(_ data: Data, limit: Int = 180) -> String {
        let text = String(decoding: data, as: UTF8.self)
        let line = text.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        let clipped = String(line.prefix(limit))
        return redact(clipped)
    }

    /// Complete stderr lines from one pipe read. A chunk that ends mid-line
    /// stays in `assembler` — scrubbing each `availableData` slice on its
    /// own leaks the second half of a split credential (Codex P2).
    public static func completedLines(_ data: Data, assembler: LineAssembler) -> [String] {
        assembler.append(data).map { tail($0) }
    }

    static func redact(_ line: String) -> String {
        let lower = line.lowercased()
        if markers.contains(where: { lower.contains($0) }) {
            return "<redacted>"
        }
        return line
    }
}

// MARK: - Census

/// What the jsonl says each upstream last did. `mcp-hub status` is a
/// different process from the daemon, so it cannot read the supervisor's
/// memory — the log is the contract.
public enum UpstreamCensus {
    public enum Phase: String, Equatable, Sendable {
        case unknown
        case up
        case exited
        case exhausted
        case rearmed
    }

    /// Last lifecycle kind per server id. Non-lifecycle lines are ignored.
    public static func phases(in jsonl: String) -> [String: Phase] {
        var phases: [String: Phase] = [:]
        for line in jsonl.split(whereSeparator: \.isNewline) {
            guard let event = Event(line: String(line)) else { continue }
            phases[event.server] = event.phase
        }
        return phases
    }

    private struct Event {
        let server: String
        let phase: Phase

        init?(line: String) {
            guard let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let kind = object["kind"] as? String,
                let server = object["f_server"] as? String,
                let phase = Self.phase(for: kind)
            else {
                return nil
            }
            self.server = server
            self.phase = phase
        }

        private static func phase(for kind: String) -> Phase? {
            switch kind {
            case "upstream.spawned": .up
            case "upstream.exited", "upstream.spawn_failed": .exited
            case "upstream.exhausted": .exhausted
            case "upstream.rearmed": .rearmed
            default: nil
            }
        }
    }
}
