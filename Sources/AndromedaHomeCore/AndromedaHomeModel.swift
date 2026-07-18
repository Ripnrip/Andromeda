/**
 * 🎭 AndromedaHomeModel — product-home brain (HAB-74)
 *
 * Fleet pulse (FleetObserveComposer headline) + CommandCenter + live memory.*
 * + live project.state.* panel. Tracker brands stay operator-only.
 * LaunchEntity roster stays in FleetObserveBar — home chrome is headline only.
 */

import AppKit
import Foundation
import MemoryKit
import Observation

@MainActor
@Observable
public final class AndromedaHomeModel {
    public var commandCenter = CommandCenterModel(
        healthStatus: .unknown,
        syncStatus: .idle,
        activeVisibility: .private
    )
    /// 🌐 Live `project.state` board — starts idle until `project.state.list`.
    public var projectState = ProjectStatePanelModel(
        projects: [],
        lastMessage: "project.state.list idle"
    )
    public var memory = AndromedaMemorySession()
    public var memoryQuery: String = ""
    public var fleetStatus: FleetHealthStatus = .unknown
    /// 🎯 FleetObserveComposer headline (or healthy summary) — chrome only, no roster.
    public var fleetDetail: String = "health.json not loaded"
    public var fleetAttentionCount: Int = 0
    /// 🕰️ Frozen for snapshots; live app updates on refresh.
    public var lastRefresh = Date(timeIntervalSince1970: 1_752_700_000)

    /// 🔮 Capability surface for `project.state.*` — live Studio bridge by default.
    public private(set) var projectSurface: any ProjectStateSurface

    public init(projectSurface: (any ProjectStateSurface)? = nil) {
        self.projectSurface = projectSurface ?? ProjectStateBridgeFactory.makeStudioBridge()
    }

    public func bootstrap() async {
        await memory.start()
        refreshFleet()
        await refreshProjectState()
    }

    /// 📡 Fleet pulse + async `project.state.list` (footer Refresh).
    public func refresh() {
        refreshFleet()
        Task { await refreshProjectState() }
    }

    /// 👁️ Live health.json × launchctl × :8286 via FleetObserveComposer.
    /// Headline only — LaunchEntity roster stays in FleetObserveBar.
    public func refreshFleet() {
        let report = FleetObserveComposer.observeLive(observingHostRole: .hub)
        apply(report: report)
        commandCenter.setVisibility(memory.activeVisibility)
        lastRefresh = Date()
        print("🌐 ✨ ANDROMEDA HOME FLEET PULSE — status=\(fleetStatus.rawValue) attentions=\(fleetAttentionCount)")
    }

    /// 🎨 Map a composed Observe report into home chrome (no roster state).
    public func apply(report: FleetObserveReport) {
        fleetStatus = Self.menuStatus(from: report)
        fleetAttentionCount = report.attentionRows.count
        if let why = report.headlineWhy {
            fleetDetail = why
        } else {
            fleetDetail = "Fleet pulse \(report.health.status.rawValue) · \(fleetAttentionCount) attention(s)"
        }
        switch fleetStatus {
        case .green:
            commandCenter.applyHealth(.healthy)
        case .unknown:
            commandCenter.applyHealth(.unknown)
        case .yellow, .red:
            commandCenter.applyHealth(.unhealthy(report.headlineWhy ?? fleetStatus.rawValue))
        }
    }

    /// 🟢 Joined attentions + health headline (same lantern as FleetObserveBar).
    public static func menuStatus(from report: FleetObserveReport) -> FleetHealthStatus {
        if report.attentionRows.contains(where: { $0.attention == .critical }) {
            return .red
        }
        if !report.attentionRows.isEmpty {
            return .yellow
        }
        return report.health.status
    }

    /// 🌐 Capability: `project.state.list`
    public func refreshProjectState() async {
        await projectState.refresh(using: projectSurface)
    }

    /// ✨ Capability: `project.state.create`
    public func createProjectItem() async {
        await projectState.createDraft(using: projectSurface)
    }

    public func runMemoryCommand() async {
        guard let command = AndromedaMemoryCommand.parse(memoryQuery) else {
            memory.lastOutcome = .empty(
                message: "Type recall / store / journal … (\(AndromedaMemoryCapability.recall.rawValue))"
            )
            return
        }
        await memory.execute(command)
        commandCenter.setVisibility(memory.activeVisibility)
        switch memory.lastOutcome {
        case .stored, .journaled:
            commandCenter.applySync(.success(Date()))
        case .failed:
            commandCenter.applySync(.failed(.cloudKitError("memory command failed")))
        default:
            break
        }
    }

    public func openMultibrainBar() {
        let path = ("~/Applications/MultibrainBar.app" as NSString).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    public func openFleetObserve() {
        let path = ("~/Applications/FleetObserveBar.app" as NSString).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    public func openVault() {
        let path = ("~/Developer/SecondBrain" as NSString).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        commandCenter.openVault()
    }
}

/// 🌟 Deterministic fixtures for previews + SnapshotTesting (no live I/O).
@MainActor
public enum AndromedaHomeFixtures {
    public static func healthyHome() -> AndromedaHomeModel {
        let model = AndromedaHomeModel(projectSurface: InMemoryProjectStateStore())
        model.fleetStatus = .green
        model.fleetDetail = "Fleet pulse green · 0 attention(s)"
        model.fleetAttentionCount = 0
        model.commandCenter = CommandCenterModel(
            healthStatus: .healthy,
            syncStatus: .idle,
            activeVisibility: .private
        )
        model.projectState = .snapshotFixture()
        model.memory.lastOutcome = .idle
        model.memoryQuery = ""
        model.lastRefresh = Date(timeIntervalSince1970: 1_752_700_000)
        return model
    }

    public static func recalledHome() -> AndromedaHomeModel {
        let model = healthyHome()
        model.memoryQuery = "recall andromeda"
        model.memory.lastOutcome = .recalled(
            hits: [
                AndromedaMemoryHit(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    title: "Studio hosts the hive mind; Book recalls as a satellite.",
                    subtitle: "multibrain · ~/Developer/SecondBrain/01-Projects/Andromeda.md",
                    sourceLabel: "hot",
                    visibility: "private"
                ),
                AndromedaMemoryHit(
                    id: UUID(uuidString: "FFFFFFFF-0000-1111-2222-333333333333")!,
                    title: "Nightly is consolidate; Letta is the Librarian.",
                    subtitle: "~/Developer/SecondBrain/07-Sessions/note.md",
                    sourceLabel: "vault",
                    visibility: "friends"
                ),
            ],
            degraded: false,
            note: nil
        )
        return model
    }

    public static func degradedHome() -> AndromedaHomeModel {
        let model = AndromedaHomeModel(projectSurface: InMemoryProjectStateStore())
        model.fleetStatus = .red
        model.fleetDetail = "job.nightly: dead_man — last success 165h ago"
        model.fleetAttentionCount = 1
        model.commandCenter = CommandCenterModel(
            healthStatus: .unhealthy("job.nightly: dead_man — last success 165h ago"),
            syncStatus: .failed(.cloudKitError("offline constellation")),
            activeVisibility: .friends
        )
        model.projectState = ProjectStatePanelModel(
            projects: [],
            lastMessage: "project.state.list failed: offline"
        )
        model.memory.lastOutcome = .failed(message: "Memory store unavailable")
        model.memoryQuery = "store hello"
        model.lastRefresh = Date(timeIntervalSince1970: 1_752_700_000)
        return model
    }

    public static func syncingHome() -> AndromedaHomeModel {
        let model = healthyHome()
        model.memoryQuery = "journal wrap-up"
        model.memory.lastOutcome = .syncing
        model.commandCenter.applySync(.syncing)
        return model
    }
}
