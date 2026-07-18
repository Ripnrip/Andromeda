/**
 * 🎭 The CommandCenterView - The Utility Popover Proscenium
 *
 * Modern SwiftUI (swiftui-expert-skill): `@Observable` / `@Bindable`,
 * `.animation(_:value:)`, extracted subviews, material chrome, spring motion.
 */

import Foundation
import SwiftUI

// MARK: - Action Intents (stubs — no LaunchAgent calls yet)

/// Recorded wishes from the utility panel (proof stub — no plist kickstart).
public enum CommandCenterActionIntent: String, CaseIterable, Equatable, Sendable, Codable {
    case openVault
    case sync
    case consolidate

    public var title: String {
        switch self {
        case .openVault: return "Open Vault"
        case .sync: return "Sync"
        case .consolidate: return "Consolidate"
        }
    }

    public var systemImage: String {
        switch self {
        case .openVault: return "folder"
        case .sync: return "arrow.triangle.2.circlepath"
        case .consolidate: return "moon.zzz"
        }
    }
}

// MARK: - Badge Labels

/// Pure string alchemy for status chrome (testable without SwiftUI).
public enum CommandCenterBadgeLabels: Sendable {
    public static func health(_ status: HealthStatus) -> String {
        switch status {
        case .unknown: return "Health: unknown"
        case .healthy: return "Health: green"
        case .unhealthy(let reason): return "Health: red · \(reason)"
        }
    }

    public static func sync(_ status: SyncStatus) -> String {
        switch status {
        case .idle: return "Sync: idle"
        case .syncing: return "Sync: synchronizing…"
        case .success(let date):
            let formatter = ISO8601DateFormatter()
            return "Sync: ok · \(formatter.string(from: date))"
        case .failed(let error):
            return "Sync: failed · \(error.localizedDescription)"
        }
    }

    public static func visibility(_ level: VisibilityLevel) -> String {
        "Visibility: \(level.rawValue)"
    }
}

// MARK: - Observable Model

/// Main-actor state for the MemoryKit utility panel.
@MainActor
@Observable
public final class CommandCenterModel {
    public var healthStatus: HealthStatus
    public var syncStatus: SyncStatus
    public var activeVisibility: VisibilityLevel
    public private(set) var recordedIntents: [CommandCenterActionIntent]
    public var lastMessage: String?

    public init(
        healthStatus: HealthStatus = .unknown,
        syncStatus: SyncStatus = .idle,
        activeVisibility: VisibilityLevel = .private,
        recordedIntents: [CommandCenterActionIntent] = []
    ) {
        self.healthStatus = healthStatus
        self.syncStatus = syncStatus
        self.activeVisibility = activeVisibility
        self.recordedIntents = recordedIntents
    }

    public var healthBadgeLabel: String { CommandCenterBadgeLabels.health(healthStatus) }
    public var syncBadgeLabel: String { CommandCenterBadgeLabels.sync(syncStatus) }
    public var visibilityBadgeLabel: String { CommandCenterBadgeLabels.visibility(activeVisibility) }

    public func openVault() {
        record(.openVault)
        lastMessage = "Recorded intent: Open Vault"
    }

    public func syncNow() {
        record(.sync)
        lastMessage = "Recorded intent: Sync"
    }

    public func consolidate() {
        record(.consolidate)
        lastMessage = "Recorded intent: Consolidate"
    }

    public func setVisibility(_ level: VisibilityLevel) {
        guard activeVisibility != level else { return }
        activeVisibility = level
    }

    public func applyHealth(_ status: HealthStatus) {
        guard healthStatus != status else { return }
        healthStatus = status
    }

    public func applySync(_ status: SyncStatus) {
        syncStatus = status
    }

    public func clearRecordedIntents() {
        recordedIntents.removeAll()
        lastMessage = nil
    }

    private func record(_ intent: CommandCenterActionIntent) {
        recordedIntents.append(intent)
    }
}

// MARK: - SwiftUI Panel

/// MemoryKit's macOS popover utility panel (modern material chrome).
@MainActor
public struct CommandCenterView: View {
    @Bindable public var model: CommandCenterModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: CommandCenterModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MemoryKitPanelHeader(
                title: "Andromeda · MemoryKit",
                systemImage: "brain.head.profile",
                caption: "stub",
                tint: .cyan,
                accessibilityIdentifier: "commandCenter.header"
            )
            Divider().opacity(0.35)
            badgeColumn
            Divider().opacity(0.35)
            actionRow
            if let message = model.lastMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("commandCenter.lastMessage")
                    .transition(.opacity)
            }
        }
        .padding(14)
        .frame(width: 340)
        .memoryKitPanelChrome()
        .animation(MemoryKitMotion.animation(reduceMotion: reduceMotion), value: model.healthStatus)
        .animation(MemoryKitMotion.animation(reduceMotion: reduceMotion), value: model.syncStatus)
        .animation(MemoryKitMotion.chip, value: model.lastMessage)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("commandCenter.panel")
    }

    private var badgeColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            CommandCenterBadgeChip(
                label: model.healthBadgeLabel,
                systemImage: "heart.text.square",
                identifier: "commandCenter.badge.health"
            )
            CommandCenterBadgeChip(
                label: model.syncBadgeLabel,
                systemImage: "icloud",
                identifier: "commandCenter.badge.sync"
            )
            CommandCenterBadgeChip(
                label: model.visibilityBadgeLabel,
                systemImage: "eye",
                identifier: "commandCenter.badge.visibility"
            )
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            CommandCenterActionButton(intent: .openVault, action: model.openVault)
            CommandCenterActionButton(intent: .sync, action: model.syncNow)
            CommandCenterActionButton(intent: .consolidate, action: model.consolidate)
        }
    }
}

// MARK: - Extracted subviews

private struct CommandCenterBadgeChip: View {
    let label: String
    let systemImage: String
    let identifier: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .symbolRenderingMode(.hierarchical)
            Text(label)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .memoryKitChipChrome()
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }
}

private struct CommandCenterActionButton: View {
    let intent: CommandCenterActionIntent
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(MemoryKitMotion.animation(reduceMotion: reduceMotion)) {
                action()
            }
        } label: {
            Label(intent.title, systemImage: intent.systemImage)
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("commandCenter.action.\(intent.rawValue)")
        .accessibilityLabel(intent.title)
    }
}

#if DEBUG
@MainActor
enum CommandCenterPreviewCatalog {
    static func healthy() -> CommandCenterModel {
        CommandCenterModel(healthStatus: .healthy, syncStatus: .idle, activeVisibility: .private)
    }

    static func degraded() -> CommandCenterModel {
        CommandCenterModel(
            healthStatus: .unhealthy("Qdrant"),
            syncStatus: .failed(.cloudKitError("offline constellation")),
            activeVisibility: .friends
        )
    }

    static func syncing() -> CommandCenterModel {
        CommandCenterModel(healthStatus: .healthy, syncStatus: .syncing, activeVisibility: .internal)
    }

    static func emptyIntents() -> CommandCenterModel {
        CommandCenterModel(healthStatus: .unknown, syncStatus: .idle, activeVisibility: .private)
    }

    @ViewBuilder
    static func staged(
        _ model: CommandCenterModel,
        scheme: ColorScheme,
        typeSize: DynamicTypeSize
    ) -> some View {
        CommandCenterView(model: model)
            .preferredColorScheme(scheme)
            .environment(\.dynamicTypeSize, typeSize)
            .padding()
            .background(scheme == .dark ? Color.black : Color.white)
    }
}

#Preview("CC · healthy · light · medium") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.healthy(), scheme: .light, typeSize: .medium
    )
}

#Preview("CC · degraded · dark · medium") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.degraded(), scheme: .dark, typeSize: .medium
    )
}

#Preview("CC · syncing · light · a11y2") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.syncing(), scheme: .light, typeSize: .accessibility2
    )
}
#endif
