/**
 * Console shell rituals — tab selection + fixture wiring for modern MemoryKit UI.
 */

import Testing
@testable import MemoryKit

@Suite("MemoryKit console shell")
@MainActor
struct MemoryKitConsoleViewTests {
    @Test("Snapshot fixture wakes with healthy command + hub roster")
    func testSnapshotFixture() {
        let model = MemoryKitConsoleModel.snapshotFixture()
        #expect(model.selectedTab == .command)
        #expect(model.command.healthStatus == .healthy)
        #expect(model.roster.state == .hubFull)
        #expect(model.projects.selectedProject != nil)
        #expect(model.pet.ambientState == .idle)
    }

    @Test("Tab cases expose capability-safe titles")
    func testTabTitlesNeverMentionTrackers() {
        for tab in MemoryKitConsoleTab.allCases {
            let lower = tab.title.lowercased()
            #expect(!lower.contains("linear"))
            #expect(!lower.contains("multica"))
            #expect(!tab.systemImage.isEmpty)
        }
    }

    @Test("Selecting tabs updates shell state")
    func testSelectTab() {
        let model = MemoryKitConsoleModel.snapshotFixture()
        model.selectedTab = .mcp
        #expect(model.selectedTab == .mcp)
        model.selectedTab = .pet
        #expect(model.selectedTab == .pet)
    }
}
