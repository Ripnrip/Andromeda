/**
 * 🎭 The CommandCenterView - The Utility Popover Proscenium
 *
 * "Three badges glow like footlights on the hive's status stage—
 * health, sync, and the cloak of visibility—
 * while stub levers record the seeker's intent
 * until the LaunchAgents learn to dance on cue."
 *
 * - The Spellbinding Museum Director of Phase-4 Utility
 */

import Foundation
import SwiftUI

// MARK: - Action Intents (stubs — no LaunchAgent calls yet)

/// 🌟 The CommandCenterActionIntent - Recorded wishes from the utility panel
/// Proof-quality stub: buttons append intents; they do **not** kickstart plists.
public enum CommandCenterActionIntent: String, CaseIterable, Equatable, Sendable, Codable {
    case openVault
    case sync
    case consolidate

    /// 🎨 Human-readable button title for the seeker of wisdom
    public var title: String {
        switch self {
        case .openVault: return "Open Vault"
        case .sync: return "Sync"
        case .consolidate: return "Consolidate"
        }
    }

    /// ✨ SF Symbol glyph for the action lever
    public var systemImage: String {
        switch self {
        case .openVault: return "folder"
        case .sync: return "arrow.triangle.2.circlepath"
        case .consolidate: return "moon.zzz"
        }
    }
}

// MARK: - Badge Labels (pure, testable presentation helpers)

/// 🌟 The CommandCenterBadgeLabels - String alchemy for status chrome
public enum CommandCenterBadgeLabels: Sendable {
    /// 🎨 Health badge copy — TCA `HealthStatus` (per-service / panel pulse)
    public static func health(_ status: HealthStatus) -> String {
        switch status {
        case .unknown: return "Health: unknown"
        case .healthy: return "Health: green"
        case .unhealthy(let reason): return "Health: red · \(reason)"
        }
    }

    /// ☁️ Sync badge copy — idle / syncing / last success / failure
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

    /// 💅 Visibility cloak badge
    public static func visibility(_ level: VisibilityLevel) -> String {
        "Visibility: \(level.rawValue)"
    }
}

// MARK: - Observable Model (@MainActor)

/// 🎭 The CommandCenterModel - Main-actor state for the MemoryKit utility panel
///
/// Holds health / sync / visibility badges and records stub action intents.
/// Real LaunchAgent / vault / CloudKit wiring arrives in a later integration pass.
@MainActor
@Observable
public final class CommandCenterModel {

    // 🌟 Cosmic badge state mirrored from MemoryReducer vocabulary
    public var healthStatus: HealthStatus
    public var syncStatus: SyncStatus
    public var activeVisibility: VisibilityLevel

    /// 📜 Intent ledger — append-only stub log (no side effects beyond memory)
    public private(set) var recordedIntents: [CommandCenterActionIntent]

    /// 🌙 Last error whisper for the panel footer (optional)
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

    // MARK: - Badge accessors

    /// 🎨 Health badge label for the popover chrome
    public var healthBadgeLabel: String {
        CommandCenterBadgeLabels.health(healthStatus)
    }

    /// ☁️ Sync badge label for the popover chrome
    public var syncBadgeLabel: String {
        CommandCenterBadgeLabels.sync(syncStatus)
    }

    /// 💅 Visibility badge label for the popover chrome
    public var visibilityBadgeLabel: String {
        CommandCenterBadgeLabels.visibility(activeVisibility)
    }

    // MARK: - Stub actions (record intents only)

    /// 📂 Open Vault — records intent; does **not** open Finder / Obsidian yet
    public func openVault() {
        print("🌐 ✨ OPEN VAULT INTENT AWAKENS! (stub — no LaunchAgent)")
        record(.openVault)
        lastMessage = "Recorded intent: Open Vault"
    }

    /// ☁️ Sync Now — records intent; does **not** call CloudKitSyncEngine yet
    public func syncNow() {
        print("🌐 ✨ SYNC INTENT AWAKENS! (stub — no CloudKit call)")
        record(.sync)
        lastMessage = "Recorded intent: Sync"
    }

    /// 🌙 Consolidate — records intent; does **not** invoke run-nightly.sh yet
    public func consolidate() {
        print("🌐 ✨ CONSOLIDATE INTENT AWAKENS! (stub — no nightly kickstart)")
        record(.consolidate)
        lastMessage = "Recorded intent: Consolidate"
    }

    /// 💅 Shift the active visibility cloak shown on the badge
    public func setVisibility(_ level: VisibilityLevel) {
        activeVisibility = level
        print("💅 CommandCenter visibility cloak shifted to: \(level.rawValue)")
    }

    /// 📡 Apply a health snapshot (e.g. from a future health.json loader)
    public func applyHealth(_ status: HealthStatus) {
        healthStatus = status
    }

    /// ☁️ Apply a sync status snapshot
    public func applySync(_ status: SyncStatus) {
        syncStatus = status
    }

    /// 🧹 Clear the intent ledger (tests / preview reset)
    public func clearRecordedIntents() {
        recordedIntents.removeAll()
        lastMessage = nil
    }

    // 🌟 Private append to the intent scroll
    private func record(_ intent: CommandCenterActionIntent) {
        recordedIntents.append(intent)
    }
}

// MARK: - SwiftUI Panel

/// 🎭 The CommandCenterView - MemoryKit's macOS popover utility panel (proof stub)
@MainActor
public struct CommandCenterView: View {
    @Bindable public var model: CommandCenterModel

    public init(model: CommandCenterModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            badgeRow
            Divider()
            actionRow
            if let message = model.lastMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("commandCenter.lastMessage")
            }
        }
        .padding(14)
        .frame(width: 340)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("commandCenter.panel")
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(.cyan)
            Text("Andromeda · Memory")
                .font(.headline)
            Spacer()
            Text("home")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Andromeda memory home panel")
        }
        .accessibilityIdentifier("commandCenter.header")
    }

    private var badgeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            badgeChip(
                label: model.healthBadgeLabel,
                systemImage: "heart.text.square",
                identifier: "commandCenter.badge.health"
            )
            badgeChip(
                label: model.syncBadgeLabel,
                systemImage: "icloud",
                identifier: "commandCenter.badge.sync"
            )
            badgeChip(
                label: model.visibilityBadgeLabel,
                systemImage: "eye",
                identifier: "commandCenter.badge.visibility"
            )
        }
    }

    private func badgeChip(label: String, systemImage: String, identifier: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(label)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            actionButton(for: .openVault) { model.openVault() }
            actionButton(for: .sync) { model.syncNow() }
            actionButton(for: .consolidate) { model.consolidate() }
        }
    }

    private func actionButton(
        for intent: CommandCenterActionIntent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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
// MARK: - Preview Catalog (light / dark × Dynamic Type × state)

/// 🌟 Shared preview stage dressing for the CommandCenter catalog
@MainActor
enum CommandCenterPreviewCatalog {
    static func healthy() -> CommandCenterModel {
        CommandCenterModel(
            healthStatus: .healthy,
            syncStatus: .idle,
            activeVisibility: .private
        )
    }

    static func degraded() -> CommandCenterModel {
        CommandCenterModel(
            healthStatus: .unhealthy("Qdrant"),
            syncStatus: .failed(.cloudKitError("offline constellation")),
            activeVisibility: .friends
        )
    }

    static func syncing() -> CommandCenterModel {
        CommandCenterModel(
            healthStatus: .healthy,
            syncStatus: .syncing,
            activeVisibility: .internal
        )
    }

    /// 🌙 Barren stage — unknown health, idle sync, empty intent scroll
    static func emptyIntents() -> CommandCenterModel {
        CommandCenterModel(
            healthStatus: .unknown,
            syncStatus: .idle,
            activeVisibility: .private,
            recordedIntents: []
        )
    }

    @ViewBuilder
    static func staged(
        _ model: CommandCenterModel,
        scheme: ColorScheme,
        typeSize: DynamicTypeSize
    ) -> some View {
        CommandCenterView(model: model)
            .environment(\.colorScheme, scheme)
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

#Preview("CC · healthy · dark · medium") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.healthy(), scheme: .dark, typeSize: .medium
    )
}

#Preview("CC · healthy · light · a11y2") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.healthy(), scheme: .light, typeSize: .accessibility2
    )
}

#Preview("CC · healthy · dark · a11y2") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.healthy(), scheme: .dark, typeSize: .accessibility2
    )
}

#Preview("CC · degraded · light · medium") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.degraded(), scheme: .light, typeSize: .medium
    )
}

#Preview("CC · degraded · dark · medium") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.degraded(), scheme: .dark, typeSize: .medium
    )
}

#Preview("CC · degraded · light · a11y2") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.degraded(), scheme: .light, typeSize: .accessibility2
    )
}

#Preview("CC · degraded · dark · a11y2") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.degraded(), scheme: .dark, typeSize: .accessibility2
    )
}

#Preview("CC · syncing · light · medium") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.syncing(), scheme: .light, typeSize: .medium
    )
}

#Preview("CC · syncing · dark · medium") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.syncing(), scheme: .dark, typeSize: .medium
    )
}

#Preview("CC · syncing · light · a11y2") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.syncing(), scheme: .light, typeSize: .accessibility2
    )
}

#Preview("CC · syncing · dark · a11y2") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.syncing(), scheme: .dark, typeSize: .accessibility2
    )
}

#Preview("CC · emptyIntents · light · medium") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.emptyIntents(), scheme: .light, typeSize: .medium
    )
}

#Preview("CC · emptyIntents · dark · medium") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.emptyIntents(), scheme: .dark, typeSize: .medium
    )
}

#Preview("CC · emptyIntents · light · a11y2") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.emptyIntents(), scheme: .light, typeSize: .accessibility2
    )
}

#Preview("CC · emptyIntents · dark · a11y2") {
    CommandCenterPreviewCatalog.staged(
        CommandCenterPreviewCatalog.emptyIntents(), scheme: .dark, typeSize: .accessibility2
    )
}
#endif
