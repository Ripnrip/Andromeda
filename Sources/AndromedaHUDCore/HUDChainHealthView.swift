import AndromedaMCPHub
import SwiftUI

/// 🩺 Capability `memory_health` panel — the operator view of the memory
/// chain (HAB-599 / BIN-287): hub socket census per server, upstream
/// pressure from the telemetry digest, recent hub events, and the
/// canonical-verbs proof state (ADR-0020).
///
/// Read-only surface: rows are informational, never selectable — arrow-key
/// selection stays with recall hits and project rows.
struct HUDChainHealthView: View {
    let report: MemoryChainHealthReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header

                if report.servers.isEmpty {
                    Text(report.headline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .accessibilityLabel("Memory chain unavailable: \(report.headline)")
                } else {
                    ForEach(report.servers) { server in
                        HUDChainServerRow(
                            server: server,
                            digest: report.digest
                        )
                    }
                }

                proofRow

                if !report.recentEvents.isEmpty {
                    eventsSection
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
        .frame(
            minHeight: HUDResultsLayout.visibleMinHeight,
            maxHeight: HUDResultsLayout.contentMaxHeight
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Memory chain health: \(report.headline)")
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("Memory chain")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Text(report.headline)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Memory chain \(report.overall.rawValue): \(report.headline)")
        .accessibilityAddTraits(.isHeader)
    }

    private var proofRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: proofIcon)
                .font(.caption)
                .foregroundStyle(proofColor)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(proofTitle)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let when = proofWhen {
                    Text(when)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.andromedaHover)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Proof: \(proofTitle)")
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent hub events")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(report.recentEvents.suffix(3).enumerated()), id: \.offset) { _, event in
                HStack(spacing: 6) {
                    Text(event.kind)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(Self.relativeAge(event.timestamp, from: report.generatedAt) + " ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Hub event \(event.kind), \(Self.relativeAge(event.timestamp, from: report.generatedAt)) ago")
            }
        }
    }

    // MARK: - Status mapping

    private var statusColor: Color {
        switch report.overall {
        case .green: return .andromedaLive
        case .yellow: return .orange
        case .red: return .andromedaAlert
        case .unknown: return .andromedaMuted
        }
    }

    private var proofIcon: String {
        switch report.proof {
        case .passed: return "checkmark.seal.fill"
        case .failed: return "xmark.seal.fill"
        case .partial: return "clock.badge.exclamationmark"
        case .notRecorded: return "clock"
        }
    }

    private var proofColor: Color {
        switch report.proof {
        case .passed: return .andromedaLive
        case .failed: return .andromedaAlert
        case .partial, .notRecorded: return .andromedaMuted
        }
    }

    private var proofTitle: String {
        switch report.proof {
        case let .passed(count, _):
            "Full-chain proof passed (\(count) legs)"
        case let .failed(legs, _):
            "Proof failed: \(legs.joined(separator: ", "))"
        case let .partial(legs, _):
            "Proof pending: \(legs.joined(separator: ", "))"
        case .notRecorded:
            "No full-chain proof recorded yet 🚧"
        }
    }

    private var proofWhen: String? {
        let lastRun: Date?
        switch report.proof {
        case let .passed(_, date), let .failed(_, date), let .partial(_, date):
            lastRun = date
        case .notRecorded:
            lastRun = nil
        }
        guard let lastRun else { return nil }
        return "last run \(Self.relativeAge(lastRun, from: report.generatedAt)) ago"
    }

    /// Coarse relative age — deterministic for snapshots (no DateFormatter).
    static func relativeAge(_ date: Date, from now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }
}

/// One hosted server row: probe dot, id, placement, live detail line.
struct HUDChainServerRow: View {
    let server: MemoryChainServerRow
    let digest: HubUpstreamDigest

    private var connections: Int {
        digest.connectionsByServer[server.id] ?? 0
    }

    private var restarts: Int {
        digest.restartsByServer[server.id] ?? 0
    }

    private var spawnFailures: Int {
        digest.spawnFailuresByServer[server.id] ?? 0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(server.probe.isListening ? Color.andromedaLive : Color.andromedaAlert)
                .frame(width: 8, height: 8)
                .padding(.top, 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(server.id)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Text("· \(server.placement.rawValue)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Text(server.probe.isListening ? "listening" : "no hub")
                        .font(.caption2)
                        .foregroundStyle(server.probe.isListening ? Color.andromedaLive : Color.andromedaAlert)
                }
                Text(detailLine)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLine)
    }

    /// Second line: refusal errno when down, upstream pressure when up.
    private var detailLine: String {
        var parts: [String] = []
        if !server.probe.isListening, let refusal = server.probe.refusalReason {
            parts.append(refusal)
        } else {
            parts.append("\(connections) shim\(connections == 1 ? "" : "s") connected")
            if restarts > 0 { parts.append("\(restarts) restart\(restarts == 1 ? "" : "s")") }
            if spawnFailures > 0 { parts.append("\(spawnFailures) spawn fail\(spawnFailures == 1 ? "" : "s")") }
        }
        if !server.executableResolves {
            parts.append("executable missing")
        }
        if digest.exhaustedServers.contains(server.id) {
            parts.append("restart budget exhausted")
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityLine: String {
        (server.probe.isListening ? "\(server.id), listening. " : "\(server.id), no hub. \(server.probe.refusalReason ?? ""). ")
            + detailLine
    }
}

// MARK: - Previews

#Preview("Chain health · green · proof passed") {
    let report = MemoryChainHealth.build(
        configuration: MCPHubConfiguration(
            socketDirectory: "~/.andromeda/mcp-hub/sockets",
            servers: [
                HubServerConfig(
                    id: "filesystem",
                    packageName: "@modelcontextprotocol/server-filesystem",
                    command: "/usr/local/bin/andromeda-mcpd-filesystem.js",
                    arguments: ["/Users/admin"],
                    duplicateGroup: "filesystem"
                ),
                HubServerConfig(
                    id: "memory",
                    packageName: "@modelcontextprotocol/server-memory",
                    command: "/usr/local/bin/andromeda-mcpd-memory.js",
                    duplicateGroup: "memory"
                ),
            ]
        ),
        probe: { _ in .listening },
        telemetryRecords: [
            HubTelemetryRecord(
                timestamp: Date(timeIntervalSinceNow: -42),
                kind: "shim.connected",
                fields: ["server": "filesystem", "connection": "claude-1"]
            ),
        ],
        proof: MemoryChainProofState(
            lastRun: Date(timeIntervalSinceNow: -3_600),
            legs: [
                MemoryChainProofLeg(
                    id: "agent-to-agent",
                    status: .pass,
                    at: Date(timeIntervalSinceNow: -3_600),
                    detail: "store from Claude recalled by Codex"
                ),
                MemoryChainProofLeg(
                    id: "letta-ingress",
                    status: .pass,
                    at: Date(timeIntervalSinceNow: -3_600),
                    detail: "ingress commit counted in-context"
                ),
            ]
        )
    )
    return HUDChainHealthView(report: report)
        .padding()
        .frame(width: 378)
        .background(Color.gray.opacity(0.2))
}

#Preview("Chain health · red · server down · proof partial") {
    let report = MemoryChainHealth.build(
        configuration: MCPHubConfiguration(
            servers: [
                HubServerConfig(
                    id: "filesystem",
                    packageName: "@modelcontextprotocol/server-filesystem",
                    command: "/bin/ls",
                    arguments: ["/Users/admin"],
                    duplicateGroup: "filesystem"
                ),
                HubServerConfig(
                    id: "memory",
                    packageName: "@modelcontextprotocol/server-memory",
                    command: "/bin/ls",
                    duplicateGroup: "memory"
                ),
            ]
        ),
        probe: { path in path.contains("memory") ? .connectFailed(errno: 61) : .listening },
        telemetryRecords: [
            HubTelemetryRecord(
                timestamp: Date(timeIntervalSinceNow: -300),
                kind: "upstream.exited",
                fields: ["server": "memory", "restarts": "2"]
            ),
            HubTelemetryRecord(
                timestamp: Date(timeIntervalSinceNow: -240),
                kind: "upstream.exhausted",
                fields: ["server": "memory", "restarts": "5"]
            ),
        ],
        proof: MemoryChainProofState(
            lastRun: Date(timeIntervalSinceNow: -7_200),
            legs: [
                MemoryChainProofLeg(id: "agent-to-agent", status: .pass),
                MemoryChainProofLeg(id: "letta-ingress", status: .pending),
            ]
        )
    )
    return HUDChainHealthView(report: report)
        .padding()
        .frame(width: 378)
        .background(Color.gray.opacity(0.2))
}

#Preview("Chain health · unknown · no config") {
    let report = MemoryChainHealth.build(
        configuration: nil,
        probe: { _ in .listening },
        telemetryRecords: [],
        proof: nil
    )
    return HUDChainHealthView(report: report)
        .padding()
        .frame(width: 378)
        .background(Color.gray.opacity(0.2))
}
