/**
 * 🩺 HUD memory_health — capability wiring for the chain census (HAB-599/BIN-287)
 */

import AndromedaMCPHub
import Foundation
import MemoryKit
import Testing
@testable import AndromedaHUDCore

@Suite("HUD memory_health")
@MainActor
struct HUDChainHealthTests {
    private func fixtureReport(overall: MemoryChainOverallStatus = .green) -> MemoryChainHealthReport {
        MemoryChainHealth.build(
            configuration: MCPHubConfiguration(
                servers: [
                    HubServerConfig(id: "filesystem", packageName: "server-filesystem", command: "/bin/ls", duplicateGroup: "fs"),
                    HubServerConfig(id: "memory", packageName: "server-memory", command: "/bin/ls", duplicateGroup: "mem"),
                ]
            ),
            probe: { _ in .listening },
            telemetryRecords: [],
            proof: MemoryChainProofState(legs: [MemoryChainProofLeg(id: "agent-to-agent", status: .pass)])
        )
    }

    @Test("memory_health submit renders the chain report outcome")
    func healthSubmitShowsReport() async {
        let report = fixtureReport()
        let model = HUDModel(
            chainHealthProvider: { report },
            memorySessionReady: true
        )

        await model.submitQuery("memory_health")

        guard case .chainHealth(let rendered) = model.lastOutcome else {
            Issue.record("Expected .chainHealth, got \(model.lastOutcome)")
            return
        }
        #expect(rendered == report)
        #expect(rendered.overall == .green)
    }

    /// The bare operator verb `health` routes to the same capability.
    @Test("bare health verb routes to the census")
    func bareHealthVerbRoutes() async {
        let report = fixtureReport()
        let model = HUDModel(
            chainHealthProvider: { report },
            memorySessionReady: true
        )

        await model.submitQuery("health")

        guard case .chainHealth = model.lastOutcome else {
            Issue.record("Expected .chainHealth, got \(model.lastOutcome)")
            return
        }
    }

    /// Missing hub config fails honestly with the ADR pointer — never a fake
    /// all-green census.
    @Test("missing hub config fails with ADR pointer")
    func missingConfigFailsHonestly() async {
        let model = HUDModel(
            chainHealthProvider: { throw ChainHealthError.hubConfigMissing(path: "~/.andromeda/mcp-hub/servers.json") },
            memorySessionReady: true
        )

        await model.submitQuery("memory_health")

        guard case .failed(let message) = model.lastOutcome else {
            Issue.record("Expected .failed, got \(model.lastOutcome)")
            return
        }
        #expect(message.contains("ADR-0019"))
    }

    /// A throwing provider surfaces the error copy on the glass.
    @Test("provider error surfaces as failed outcome")
    func providerErrorSurfaces() async {
        let model = HUDModel(
            chainHealthProvider: { throw ChainHealthError.hubConfigMissing(path: "/nowhere") },
            memorySessionReady: true
        )

        await model.submitQuery("memory_health")

        guard case .failed(let message) = model.lastOutcome else {
            Issue.record("Expected .failed, got \(model.lastOutcome)")
            return
        }
        #expect(message.contains("/nowhere"))
    }

    /// The chain report shows the results panel like every other outcome.
    @Test("chain health outcome shows the results panel")
    func chainHealthShowsPanel() {
        let outcome = HUDOutcome.chainHealth(fixtureReport())
        #expect(outcome.showsResultsPanel)
    }

    /// Chain rows are informational — never keyboard-selectable (arrow keys
    /// stay with recall hits and project rows).
    @Test("chain health rows are not selectable")
    func chainHealthNotSelectable() {
        let count = HUDSelectionNavigation.selectableCount(
            outcome: .chainHealth(fixtureReport()),
            showRecentQueries: false,
            recentQueryCount: 0
        )
        #expect(count == 0)
    }

    /// relativeAge buckets are deterministic — snapshot-stable strings.
    @Test("relative age buckets are stable")
    func relativeAgeBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(HUDChainHealthView.relativeAge(now.addingTimeInterval(-5), from: now) == "5s")
        #expect(HUDChainHealthView.relativeAge(now.addingTimeInterval(-125), from: now) == "2m")
        #expect(HUDChainHealthView.relativeAge(now.addingTimeInterval(-7_200), from: now) == "2h")
        #expect(HUDChainHealthView.relativeAge(now.addingTimeInterval(-172_800), from: now) == "2d")
    }
}
