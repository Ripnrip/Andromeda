/**
 * 🎭 MemoryKitConsoleView - Tabbed modern shell for all MemoryKit panels
 *
 * Hosts CommandCenter, LaunchEntity roster, MCP registry, ProjectState, and
 * FloatingPet under one capability-safe console. Designed to drop into
 * `AndromedaHUDView` as accessory content (or a standalone popover).
 */

import SwiftUI

/// Which MemoryKit panel is frontmost in the console shell.
public enum MemoryKitConsoleTab: String, CaseIterable, Identifiable, Sendable {
    case command
    case roster
    case mcp
    case projects
    case pet

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .command: return "Command"
        case .roster: return "Roster"
        case .mcp: return "MCP"
        case .projects: return "Projects"
        case .pet: return "Pet"
        }
    }

    public var systemImage: String {
        switch self {
        case .command: return "brain.head.profile"
        case .roster: return "list.bullet.rectangle.portrait"
        case .mcp: return "server.rack"
        case .projects: return "checklist"
        case .pet: return "moon.stars"
        }
    }
}

/// Observable shell state for the tabbed MemoryKit console.
@MainActor
@Observable
public final class MemoryKitConsoleModel {
    public var selectedTab: MemoryKitConsoleTab
    public var command: CommandCenterModel
    public var roster: LaunchEntityRosterModel
    public var mcp: MCPRegistryModel
    public var projects: ProjectStatePanelModel
    public var pet: FloatingPetModel

    public init(
        selectedTab: MemoryKitConsoleTab = .command,
        command: CommandCenterModel = CommandCenterModel(),
        roster: LaunchEntityRosterModel = LaunchEntityRosterModel(),
        mcp: MCPRegistryModel = MCPRegistryModel(),
        projects: ProjectStatePanelModel = ProjectStatePanelModel(),
        pet: FloatingPetModel = FloatingPetModel()
    ) {
        self.selectedTab = selectedTab
        self.command = command
        self.roster = roster
        self.mcp = mcp
        self.projects = projects
        self.pet = pet
    }

    /// Deterministic preview / snapshot fixture.
    public static func snapshotFixture() -> MemoryKitConsoleModel {
        MemoryKitConsoleModel(
            selectedTab: .command,
            command: CommandCenterModel(
                healthStatus: .healthy,
                syncStatus: .idle,
                activeVisibility: .private
            ),
            roster: LaunchEntityRosterFixtures.model(.hubFull, reduceMotion: true),
            mcp: {
                let model = MCPRegistryModel()
                model.clear()
                return model
            }(),
            projects: .snapshotFixture(),
            pet: FloatingPetModel(ambientState: .idle, reduceMotion: true)
        )
    }
}

/// Tabbed console composing every MemoryKit SwiftUI surface.
@MainActor
public struct MemoryKitConsoleView: View {
    @Bindable public var model: MemoryKitConsoleModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: MemoryKitConsoleModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Panel", selection: $model.selectedTab) {
                ForEach(MemoryKitConsoleTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("memoryKit.console.tabs")

            panel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(MemoryKitMotion.animation(reduceMotion: reduceMotion), value: model.selectedTab)
        }
        .padding(12)
        .frame(minWidth: 480, minHeight: 360)
        .memoryKitPanelChrome(cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("memoryKit.console.root")
    }

    @ViewBuilder
    private var panel: some View {
        switch model.selectedTab {
        case .command:
            CommandCenterView(model: model.command)
        case .roster:
            LaunchEntityRosterView(model: model.roster, honorSystemReduceMotion: false)
        case .mcp:
            MCPRegistryView(model: model.mcp)
        case .projects:
            ProjectStatePanel(model: model.projects)
        case .pet:
            HStack {
                Spacer()
                FloatingPetView(model: model.pet, honorSystemReduceMotion: false)
                Spacer()
            }
            .padding(.vertical, 24)
        }
    }
}

#if DEBUG
#Preview("MemoryKit Console · dark") {
    MemoryKitConsoleView(model: .snapshotFixture())
        .preferredColorScheme(.dark)
        .padding()
        .background(Color.black)
}
#endif
