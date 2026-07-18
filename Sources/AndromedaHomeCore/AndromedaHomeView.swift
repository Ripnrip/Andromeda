/**
 * 🎭 AndromedaHomeView — visible product home for the Andromeda control plane.
 *
 * Default path: memory.* console (store / recall / journal). CommandCenter +
 * project.state panel stay embedded MemoryKit chrome. No Linear/Multica brands.
 */

import SwiftUI
import MemoryKit

@MainActor
public struct AndromedaHomeView: View {
    @Bindable public var model: AndromedaHomeModel
    /// 🧪 Snapshot / preview force for reduce-motion chrome (hourglass vs spinner).
    public var forceReduceMotion: Bool

    public init(model: AndromedaHomeModel, forceReduceMotion: Bool = false) {
        self.model = model
        self.forceReduceMotion = forceReduceMotion
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MemoryConsoleView(
                        session: model.memory,
                        query: $model.memoryQuery,
                        onSubmit: {
                            Task { await model.runMemoryCommand() }
                        },
                        forceReduceMotion: forceReduceMotion
                    )

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            CommandCenterView(model: model.commandCenter)
                            capabilitiesCard
                        }
                        ProjectStatePanel(
                            model: model.projectState,
                            onRefresh: { Task { await model.refreshProjectState() } },
                            onCreate: { Task { await model.createProjectItem() } }
                        )
                    }
                }
                .padding(16)
            }
            Spacer(minLength: 0)
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("andromedaHome.root")
    }

    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.cyan)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Andromeda")
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Local-first control plane · Observe → Evolve → Execute → Internalize")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(model.fleetStatus.rawValue.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(fleetTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(fleetTint.opacity(0.15), in: Capsule())
                    .accessibilityLabel("Fleet status \(model.fleetStatus.rawValue)")
                Text(model.fleetDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .accessibilityIdentifier("andromedaHome.fleetPulse")
                    .accessibilityLabel("Fleet pulse \(model.fleetDetail)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .accessibilityIdentifier("andromedaHome.hero")
    }

    private var capabilitiesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Client capabilities")
                .font(.headline)
            ForEach([
                ("memory.*", "recall · store · journal"),
                ("project.state.*", "list · create · update"),
                ("infer.write", "provider selection hidden"),
            ], id: \.0) { id, blurb in
                HStack {
                    Text(id)
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                    Spacer()
                    Text(blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
            Text("Capability IDs only — provider selection stays behind the curtain.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("andromedaHome.capabilities")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Refresh") { model.refresh() }
                .accessibilityLabel("Refresh fleet pulse and project.state")
            Button("MultibrainBar") { model.openMultibrainBar() }
                .accessibilityLabel("Open MultibrainBar")
            Button("Fleet Observe") { model.openFleetObserve() }
                .accessibilityLabel("Open Fleet Observe")
            Button("Vault") { model.openVault() }
                .accessibilityLabel("Open vault")
            Spacer()
            Text("refreshed \(model.lastRefresh.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var fleetTint: Color {
        switch model.fleetStatus {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        case .unknown: return .secondary
        }
    }
}

#if DEBUG
@MainActor
enum AndromedaHomePreviewCatalog {
    static func staged(
        _ model: AndromedaHomeModel,
        scheme: ColorScheme,
        typeSize: DynamicTypeSize = .medium,
        reduceMotion: Bool = false
    ) -> some View {
        AndromedaHomeView(model: model, forceReduceMotion: reduceMotion)
            .environment(\.dynamicTypeSize, typeSize)
            .preferredColorScheme(scheme)
            .frame(width: 780, height: 560)
    }
}

#Preview("Home · healthy · light") {
    AndromedaHomePreviewCatalog.staged(AndromedaHomeFixtures.healthyHome(), scheme: .light)
}

#Preview("Home · recalled · dark") {
    AndromedaHomePreviewCatalog.staged(AndromedaHomeFixtures.recalledHome(), scheme: .dark)
}

#Preview("Home · healthy · a11y2") {
    AndromedaHomePreviewCatalog.staged(
        AndromedaHomeFixtures.healthyHome(),
        scheme: .light,
        typeSize: .accessibility2
    )
}

#Preview("Home · syncing · reduceMotion · dark") {
    AndromedaHomePreviewCatalog.staged(
        AndromedaHomeFixtures.syncingHome(),
        scheme: .dark,
        reduceMotion: true
    )
}

#Preview("Home · degraded · light") {
    AndromedaHomePreviewCatalog.staged(AndromedaHomeFixtures.degradedHome(), scheme: .light)
}
#endif
