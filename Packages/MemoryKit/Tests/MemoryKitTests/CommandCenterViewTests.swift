/**
 * 🧪 The CommandCenterViewTests - Quality Rituals for the Utility Popover
 *
 * "We do not snapshot the footlights — we prove the stage directions:
 * badges speak truth, and every stub lever writes its intent in the scroll
 * without summoning a single LaunchAgent from the wings."
 *
 * - The Theatrical Quality Virtuoso of MemoryKit UI
 */

import Foundation
import Testing
@testable import MemoryKit

@Suite("🎭 CommandCenter Utility Panel Rituals ✨")
@MainActor
struct CommandCenterViewTests {

    // MARK: - 🧪 Ritual 1: Default stage dressing

    @Test("🌙 Default model wakes idle, unknown health, private cloak, empty intent scroll")
    func testDefaultInitialState() {
        let model = CommandCenterModel()

        #expect(model.healthStatus == .unknown)
        #expect(model.syncStatus == .idle)
        #expect(model.activeVisibility == .private)
        #expect(model.recordedIntents.isEmpty)
        #expect(model.lastMessage == nil)

        #expect(model.healthBadgeLabel == "Health: unknown")
        #expect(model.syncBadgeLabel == "Sync: idle")
        #expect(model.visibilityBadgeLabel == "Visibility: private")

        print("🎉 ✨ DEFAULT STAGE DRESSING VERIFIED!")
    }

    // MARK: - 🧪 Ritual 2: Badge label alchemy

    @Test("💚 Health badge reflects healthy and unhealthy reasons")
    func testHealthBadgeLabels() {
        #expect(CommandCenterBadgeLabels.health(.healthy) == "Health: green")
        #expect(CommandCenterBadgeLabels.health(.unknown) == "Health: unknown")
        #expect(
            CommandCenterBadgeLabels.health(.unhealthy("Letta"))
                == "Health: red · Letta"
        )

        let model = CommandCenterModel()
        model.applyHealth(.healthy)
        #expect(model.healthBadgeLabel == "Health: green")
        model.applyHealth(.unhealthy("Qdrant"))
        #expect(model.healthBadgeLabel == "Health: red · Qdrant")

        print("🎉 ✨ HEALTH BADGE ALCHEMY COMPLETE!")
    }

    @Test("☁️ Sync badge reflects idle, syncing, success, and failure")
    func testSyncBadgeLabels() {
        #expect(CommandCenterBadgeLabels.sync(.idle) == "Sync: idle")
        #expect(CommandCenterBadgeLabels.sync(.syncing) == "Sync: synchronizing…")

        let stamp = Date(timeIntervalSince1970: 1_784_000_000)
        let successLabel = CommandCenterBadgeLabels.sync(.success(stamp))
        #expect(successLabel.hasPrefix("Sync: ok · "))
        #expect(successLabel.contains("2026"))

        let failLabel = CommandCenterBadgeLabels.sync(
            .failed(.cloudKitError("offline constellation"))
        )
        #expect(failLabel.hasPrefix("Sync: failed · "))
        #expect(failLabel.contains("offline constellation"))

        let model = CommandCenterModel()
        model.applySync(.syncing)
        #expect(model.syncBadgeLabel == "Sync: synchronizing…")

        print("🎉 ✨ SYNC BADGE ALCHEMY COMPLETE!")
    }

    @Test("💅 Visibility badge mirrors every cloak level")
    func testVisibilityBadgeLabels() {
        for level in VisibilityLevel.allCases {
            #expect(
                CommandCenterBadgeLabels.visibility(level)
                    == "Visibility: \(level.rawValue)"
            )
        }

        let model = CommandCenterModel(activeVisibility: .internal)
        #expect(model.visibilityBadgeLabel == "Visibility: internal")
        model.setVisibility(.friends)
        #expect(model.activeVisibility == .friends)
        #expect(model.visibilityBadgeLabel == "Visibility: friends")

        print("🎉 ✨ VISIBILITY CLOAK BADGES ALIGNED!")
    }

    // MARK: - 🧪 Ritual 3: Stub action intent ledger

    @Test("📂 Open Vault records intent without side-effect machinery")
    func testOpenVaultRecordsIntent() {
        let model = CommandCenterModel()
        model.openVault()

        #expect(model.recordedIntents == [.openVault])
        #expect(model.lastMessage == "Recorded intent: Open Vault")
        // 🌙 Stub contract: sync/health unchanged by vault intent
        #expect(model.syncStatus == .idle)
        #expect(model.healthStatus == .unknown)

        print("🎉 ✨ OPEN VAULT INTENT SCROLL VERIFIED!")
    }

    @Test("☁️ Sync stub records intent and does not flip syncStatus to syncing")
    func testSyncNowRecordsIntentOnly() {
        let model = CommandCenterModel(syncStatus: .idle)
        model.syncNow()

        #expect(model.recordedIntents == [.sync])
        #expect(model.lastMessage == "Recorded intent: Sync")
        // ✨ Proof stub: no CloudKit / LaunchAgent — status stays idle until wired
        #expect(model.syncStatus == .idle)

        print("🎉 ✨ SYNC INTENT STUB HOLDS THE LINE!")
    }

    @Test("🌙 Consolidate stub records intent only")
    func testConsolidateRecordsIntent() {
        let model = CommandCenterModel()
        model.consolidate()

        #expect(model.recordedIntents == [.consolidate])
        #expect(model.lastMessage == "Recorded intent: Consolidate")

        print("🎉 ✨ CONSOLIDATE INTENT STUB VERIFIED!")
    }

    @Test("📜 Multiple stub actions append intents in order")
    func testIntentLedgerAppendsInOrder() {
        let model = CommandCenterModel()
        model.openVault()
        model.syncNow()
        model.consolidate()
        model.openVault()

        #expect(
            model.recordedIntents == [
                .openVault,
                .sync,
                .consolidate,
                .openVault,
            ]
        )

        model.clearRecordedIntents()
        #expect(model.recordedIntents.isEmpty)
        #expect(model.lastMessage == nil)

        print("🎉 ✨ INTENT SCROLL ORDER + CLEAR MASTERPIECE COMPLETE!")
    }

    @Test("🎫 Action intent titles and symbols are stable for UI wiring")
    func testActionIntentPresentation() {
        #expect(CommandCenterActionIntent.openVault.title == "Open Vault")
        #expect(CommandCenterActionIntent.sync.title == "Sync")
        #expect(CommandCenterActionIntent.consolidate.title == "Consolidate")

        #expect(CommandCenterActionIntent.openVault.systemImage == "folder")
        #expect(CommandCenterActionIntent.sync.systemImage == "arrow.triangle.2.circlepath")
        #expect(CommandCenterActionIntent.consolidate.systemImage == "moon.zzz")
        #expect(CommandCenterActionIntent.allCases.count == 3)

        print("🎉 ✨ ACTION INTENT TITLES STABLE!")
    }

    // MARK: - 🧪 Ritual 4: View construction (smoke — not snapshots)

    @Test("🎪 CommandCenterView constructs on MainActor with bound model")
    func testViewConstructionSmoke() {
        let model = CommandCenterModel(
            healthStatus: .healthy,
            syncStatus: .syncing,
            activeVisibility: .public
        )
        // 🌟 Smoke: building the view must not trap; body is evaluated lazily
        let view = CommandCenterView(model: model)
        #expect(view.model.healthBadgeLabel == "Health: green")
        #expect(view.model.syncBadgeLabel == "Sync: synchronizing…")
        #expect(view.model.visibilityBadgeLabel == "Visibility: public")

        view.model.consolidate()
        #expect(view.model.recordedIntents == [.consolidate])

        print("🎉 ✨ COMMAND CENTER VIEW SMOKE COMPLETE!")
    }
}
