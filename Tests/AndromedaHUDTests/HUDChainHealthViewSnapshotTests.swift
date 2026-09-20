import AndromedaMCPHub
import SnapshotTesting
import SwiftUI
import Testing
@testable import AndromedaHUDCore

/// Pixel catalog for `HUDChainHealthView` (memory_health panel).
@Suite("HUDChainHealthView Snapshots")
@MainActor
struct HUDChainHealthViewSnapshotTests {

    private var recordMode: SnapshotTestingConfiguration.Record {
        (ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"].map { !$0.isEmpty } ?? false) ? .all : .missing
    }

    /// Fully healthy chain: both sockets listening, proof passed, one recent event.
    private func greenReport() -> MemoryChainHealthReport {
        MemoryChainHealth.build(
            configuration: MCPHubConfiguration(
                servers: [
                    HubServerConfig(id: "filesystem", packageName: "server-filesystem", command: "/bin/ls", duplicateGroup: "fs"),
                    HubServerConfig(id: "memory", packageName: "server-memory", command: "/bin/ls", duplicateGroup: "mem"),
                ]
            ),
            probe: { _ in .listening },
            telemetryRecords: [
                HubTelemetryRecord(
                    timestamp: Date(timeIntervalSinceNow: -42),
                    kind: "shim.connected",
                    fields: ["server": "memory", "connection": "codex-7"]
                ),
            ],
            proof: MemoryChainProofState(
                lastRun: Date(timeIntervalSinceNow: -3_600),
                legs: [
                    MemoryChainProofLeg(id: "agent-to-agent", status: .pass),
                    MemoryChainProofLeg(id: "letta-ingress", status: .pass),
                ]
            )
        )
    }

    /// Degraded chain: one server down with restart pressure, proof partial.
    private func redReport() -> MemoryChainHealthReport {
        MemoryChainHealth.build(
            configuration: MCPHubConfiguration(
                servers: [
                    HubServerConfig(id: "filesystem", packageName: "server-filesystem", command: "/bin/ls", duplicateGroup: "fs"),
                    HubServerConfig(id: "memory", packageName: "server-memory", command: "/bin/ls", duplicateGroup: "mem"),
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
    }

    @Test("green chain light/dark", arguments: [
        ("Light", true),
        ("Dark", false),
    ])
    func greenSnapshots(name: String, isLight: Bool) {
        withSnapshotTesting(record: recordMode) {
            let view = HUDChainHealthView(report: greenReport())
                .environment(\.colorScheme, isLight ? .light : .dark)

            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 378, height: 300)

            assertSnapshot(of: hosting, as: .image, named: "HUDChainHealthView.green.\(name.lowercased())")
        }
    }

    @Test("red chain dark")
    func redSnapshot() {
        withSnapshotTesting(record: recordMode) {
            let view = HUDChainHealthView(report: redReport())
                .environment(\.colorScheme, .dark)

            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 378, height: 300)

            assertSnapshot(of: hosting, as: .image, named: "HUDChainHealthView.red.dark")
        }
    }
}
