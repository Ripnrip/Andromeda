/**
 * 🧪 Live Linear project.state integration — gated by LINEAR_LIVE=1
 *
 * "GraphQL must answer list without leaking BIN-* into client JSON.
 * Dotenv loads ~/Developer/multibrain/.env silently — keys never printed.
 * Create smokes stay manual: LINEAR_LIVE=1 alone is enough to list; don't
 * spawn probe tickets on every accidental filter run."
 *
 * - The Theatrical Live Linear Virtuoso
 */

import Foundation
import Testing
@testable import MemoryKit

private let linearLiveEnabled: Bool = {
    guard ProcessInfo.processInfo.environment["LINEAR_LIVE"] == "1" else { return false }
    return ProjectStateBridgeConfiguration.linearKeyPresentFromEnvironment()
}()

@Suite(
    "🌐 Live Linear project.state ✨",
    .enabled(if: linearLiveEnabled)
)
struct LiveLinearProjectStateTests {

    /// 📜 List merges Linear issues into brand-neutral project.state items.
    /// ✨ Curtain check: no BIN/HAB/provenance strings in client JSON — the velvet stays drawn.
    @Test("📜 Studio Linear list merges into brand-neutral project.state items")
    func liveListIncludesLinear() async throws {
        let config = ProjectStateBridgeConfiguration.loadFromEnvironment()
        #expect(!(config.linearAPIKey ?? "").isEmpty)
        print("🔑 Linear key present (len=\(config.linearAPIKey?.count ?? 0), value cloaked)")

        let bridge = ProjectStateBridgeFactory.makeStudioBridge(configuration: config)
        let projects = try await bridge.listProjects()
        #expect(!projects.isEmpty)
        let project = projects[0]
        #expect(project.id.rawValue == "andromeda")
        #expect(!project.items.isEmpty)

        let data = try JSONEncoder().encode(project)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("HAB-"))
        #expect(!json.contains("BIN-"))
        #expect(!json.contains("linear.app"))
        #expect(!json.contains("multica"))
        #expect(!json.contains("provenance"))
        print("🎉 ✨ LIVE LINEAR LIST PASS items=\(project.items.count)")
    }
}
