/**
 * 🧪 Live Linear project.state integration — gated when LINEAR_API_KEY resolves
 *
 * "When the seeker leaves a key in dotenv or process env, GraphQL must wake.
 * Soft-skip only when truly unwired — never fake green."
 *
 * - The Theatrical Live Linear Virtuoso
 */

import Foundation
import Testing
@testable import MemoryKit

private enum LiveLinearGate {
    /// 🔮 True when process env or documented dotenv paths yield a non-empty LINEAR_API_KEY.
    static var isEnabled: Bool {
        let config = ProjectStateBridgeConfiguration.loadFromEnvironment()
        return !(config.linearAPIKey ?? "").isEmpty
    }
}

@Suite("🌐 Live Linear project.state ✨", .enabled(if: LiveLinearGate.isEnabled))
struct LiveLinearProjectStateTests {

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

        let data = try JSONEncoder().encode(project)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("HAB-"))
        #expect(!json.contains("BIN-"))
        #expect(!json.contains("linear.app"))
        #expect(!json.contains("provenance"))
        print("🎉 ✨ LIVE LINEAR LIST PASS items=\(project.items.count)")
    }
}
