/**
 * 🧪 Live Multica project.state integration — gated by MULTICA_LIVE=1
 *
 * "Studio Habitat must answer project.state.list without whispering HAB-*
 * into client JSON. Skip politely when the hive isn't awake."
 *
 * - The Theatrical Live Fabric Virtuoso
 */

import Foundation
import Testing
@testable import MemoryKit

@Suite("🌐 Live Multica project.state ✨", .enabled(if: ProcessInfo.processInfo.environment["MULTICA_LIVE"] == "1"))
struct LiveMulticaProjectStateTests {

    @Test("📜 Studio Multica list merges into brand-neutral project.state items")
    func liveList() async throws {
        let bridge = ProjectStateBridgeFactory.makeStudioBridge()
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
        print("🎉 ✨ LIVE MULTICA LIST PASS items=\(project.items.count)")
    }

    @Test("✨ Studio Multica create via project.state.create (Linear soft-skip without key)")
    func liveCreate() async throws {
        let bridge = ProjectStateBridgeFactory.makeStudioBridge()
        let token = "ps-live-\(UUID().uuidString.prefix(6))"
        let item = try await bridge.createItem(
            ProjectStateDraft(
                projectID: ProjectStateID(rawValue: "andromeda"),
                title: "project.state live smoke \(token)",
                status: .backlog,
                notes: "Phase 2 live smoke — cancel after proof"
            )
        )
        #expect(item.title.contains(token))
        #expect(item.id.rawValue.hasPrefix("ps-"))
        let json = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        #expect(!json.contains("HAB-"))
        #expect(!json.contains("BIN-"))
        print("🎉 ✨ LIVE MULTICA CREATE PASS id=\(item.id.rawValue)")
        // Operator cleanup left to proof harness / human — title is unique smoke token
    }
}
