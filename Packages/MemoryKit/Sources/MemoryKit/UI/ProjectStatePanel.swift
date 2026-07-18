/**
 * 🎭 The ProjectStatePanel - Client Board Without Tracker Neon
 *
 * Modern SwiftUI: ContentUnavailableView empty state, material chrome,
 * extracted rows, spring animations, capability IDs only.
 */

import Foundation
import SwiftUI

// MARK: - Model

@MainActor
@Observable
public final class ProjectStatePanelModel {
    public var projects: [ProjectState]
    public var selectedProjectID: ProjectStateID?
    public var lastMessage: String?
    public var isLoading: Bool

    public init(
        projects: [ProjectState] = [],
        selectedProjectID: ProjectStateID? = nil,
        lastMessage: String? = nil,
        isLoading: Bool = false
    ) {
        self.projects = projects
        self.selectedProjectID = selectedProjectID ?? projects.first?.id
        self.lastMessage = lastMessage
        self.isLoading = isLoading
    }

    public var selectedProject: ProjectState? {
        guard let selectedProjectID else { return projects.first }
        return projects.first(where: { $0.id == selectedProjectID })
    }

    public static func statusLabel(_ status: ProjectStateStatus) -> String {
        switch status {
        case .backlog: return "Backlog"
        case .active: return "Active"
        case .blocked: return "Blocked"
        case .done: return "Done"
        }
    }

    public func apply(projects: [ProjectState]) {
        self.projects = projects
        if selectedProjectID == nil || !projects.contains(where: { $0.id == selectedProjectID }) {
            selectedProjectID = projects.first?.id
        }
        isLoading = false
        lastMessage = "Loaded \(projects.count) project(s)"
    }

    public func refresh(using surface: any ProjectStateSurface) async {
        isLoading = true
        lastMessage = "Refreshing…"
        do {
            let listed = try await surface.listProjects()
            apply(projects: listed)
        } catch {
            isLoading = false
            lastMessage = "Refresh failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Panel

@MainActor
public struct ProjectStatePanel: View {
    @Bindable public var model: ProjectStatePanelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: ProjectStatePanelModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MemoryKitPanelHeader(
                title: "Projects",
                systemImage: "checklist",
                caption: "project.state",
                tint: .teal,
                accessibilityIdentifier: "projectState.header"
            )
            Divider().opacity(0.35)
            content
            if let message = model.lastMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("projectState.lastMessage")
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .topLeading)
        .memoryKitPanelChrome()
        .animation(MemoryKitMotion.animation(reduceMotion: reduceMotion), value: model.isLoading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectState.panel")
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView("Loading projects…")
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let project = model.selectedProject {
            ProjectStateHeaderView(project: project)
            ProjectStateItemList(items: project.items)
        } else {
            ContentUnavailableView {
                Label("No projects yet", systemImage: "tray")
            } description: {
                Text("Call project.state.list to populate this board.")
            }
            .accessibilityIdentifier("projectState.empty")
        }
    }
}

// MARK: - Subviews

private struct ProjectStateHeaderView: View {
    let project: ProjectState

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .font(.title3.weight(.semibold))
                Text(ProjectStatePanelModel.statusLabel(project.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(project.items.count)")
                .font(.caption.monospacedDigit())
                .memoryKitChipChrome(cornerRadius: 12)
                .accessibilityLabel("\(project.items.count) items")
        }
        .accessibilityIdentifier("projectState.projectHeader")
    }
}

private struct ProjectStateItemList: View {
    let items: [ProjectStateItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                ProjectStateItemRow(item: item)
            }
        }
    }
}

private struct ProjectStateItemRow: View {
    let item: ProjectStateItem

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(item.title)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(ProjectStatePanelModel.statusLabel(item.status))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .memoryKitChipChrome()
        .accessibilityIdentifier("projectState.item.\(item.id.rawValue)")
    }

    private var statusColor: Color {
        switch item.status {
        case .backlog: return .secondary
        case .active: return .teal
        case .blocked: return .orange
        case .done: return .green
        }
    }
}

// MARK: - Fixtures

extension ProjectStatePanelModel {
    public static func snapshotFixture() -> ProjectStatePanelModel {
        let items = [
            ProjectStateItem(
                id: ProjectStateItemID(rawValue: "item-1"),
                title: "Wire capability curtain",
                status: .active,
                notes: nil
            ),
            ProjectStateItem(
                id: ProjectStateItemID(rawValue: "item-2"),
                title: "Hide tracker brands from clients",
                status: .done,
                notes: nil
            ),
            ProjectStateItem(
                id: ProjectStateItemID(rawValue: "item-3"),
                title: "Operator bridge live APIs",
                status: .backlog,
                notes: nil
            ),
        ]
        let project = ProjectState(
            id: ProjectStateID(rawValue: "andromeda"),
            title: "Andromeda",
            status: .active,
            items: items,
            provenance: ProjectStateProvenance(linearIssueID: "BIN-HIDDEN", multicaIssueID: "HAB-HIDDEN")
        )
        return ProjectStatePanelModel(
            projects: [project],
            selectedProjectID: project.id,
            lastMessage: "Loaded 1 project(s)"
        )
    }
}

#if DEBUG
#Preview("ProjectState · light") {
    ProjectStatePanel(model: .snapshotFixture())
        .preferredColorScheme(.light)
}

#Preview("ProjectState · dark") {
    ProjectStatePanel(model: .snapshotFixture())
        .preferredColorScheme(.dark)
}
#endif
