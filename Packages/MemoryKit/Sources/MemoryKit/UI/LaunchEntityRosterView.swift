/**
 * 🎭 The LaunchEntityRosterView - The Impossible-to-Ignore Playbill
 *
 * "No more silent watchdogs humming unpaid soliloquies backstage.
 * The roster fills the glass — loading shimmer, empty hush,
 * hub-full chorus, or satellite n/a honesty — always visible,
 * always loud enough that the Mini tunnel cannot hide."
 *
 * - The Theatrical Virtuoso of Fleet Observability
 */

import Foundation
import SwiftUI

// MARK: - Presentation states

/**
 * 🌟 Four faces of the LaunchEntity roster — day-1 Observe UI.
 *
 * - `loading` — refresh in flight
 * - `empty` — catalog vacuum (should alarm operators)
 * - `hubFull` — Studio hub with the full multibrain + Mini cast
 * - `satelliteNA` — Book/satellite view where hub services are honest n/a
 */
public enum LaunchEntityRosterState: String, Sendable, Equatable, CaseIterable {
    case loading
    case empty
    case hubFull = "hub-full"
    case satelliteNA = "satellite-na"

    /// 🎨 VoiceOver / header title — impossible to skim past.
    public var headline: String {
        switch self {
        case .loading: return "Launch Entities · Loading"
        case .empty: return "Launch Entities · EMPTY"
        case .hubFull: return "Launch Entities · Hub Roster"
        case .satelliteNA: return "Launch Entities · Satellite (n/a honesty)"
        }
    }

    /// 📜 Supporting line under the marquee.
    public var subtitle: String {
        switch self {
        case .loading:
            return "Peeking at launchctl — observe only, never kickstart."
        case .empty:
            return "No LaunchEntities registered. This is a pageant failure."
        case .hubFull:
            return "Studio hub cast — watchdogs visible, Mini tunnel isolated."
        case .satelliteNA:
            return "Hub KeepAlives report n/a here — never fake red."
        }
    }

    /// ♿ Accessibility identifier stem for tests / snapshots.
    public var accessibilityIdentifier: String {
        "launchEntityRoster.state.\(rawValue)"
    }
}

// MARK: - Model

/**
 * 🎭 LaunchEntityRosterModel — MainActor mood board for the visible roster.
 *
 * Holds presentation state, entities, last telemetry pulse, and reduce-motion.
 * Injectable fixtures keep SnapshotTesting hermetic (no live launchctl).
 */
@MainActor
@Observable
public final class LaunchEntityRosterModel {
    public var state: LaunchEntityRosterState
    public var entities: [LaunchEntity]
    public var lastTelemetry: LaunchEntityRefreshTelemetry?
    /// 🌊 When true, status chips skip pulse chrome (static still life).
    public var reduceMotion: Bool

    public init(
        state: LaunchEntityRosterState = .loading,
        entities: [LaunchEntity] = [],
        lastTelemetry: LaunchEntityRefreshTelemetry? = nil,
        reduceMotion: Bool = false
    ) {
        self.state = state
        self.entities = entities
        self.lastTelemetry = lastTelemetry
        self.reduceMotion = reduceMotion
    }

    /// ♿ Combined announcement for the roster chrome.
    public var accessibilityLabel: String {
        var parts = [state.headline]
        if let lastTelemetry {
            parts.append(lastTelemetry.displaySummary)
        } else {
            parts.append("\(entities.count) entities")
        }
        return parts.joined(separator: ". ")
    }

    /// 🌟 Apply a refreshed registry into a concrete roster face.
    public func apply(registry: LaunchEntityRegistry) {
        let roster = registry.all()
        lastTelemetry = registry.lastTelemetry
        entities = roster
        if roster.isEmpty {
            state = .empty
            return
        }
        switch registry.observingHostRole {
        case .hub:
            state = .hubFull
        case .satellite, .isolated:
            state = .satelliteNA
        }
        print("🌐 ✨ LAUNCH ENTITY ROSTER AWAKENS! → \(state.rawValue) (\(roster.count) rows)")
    }

    /// 🌙 Force a named state with optional fixture entities (previews / snapshots).
    public func present(
        _ state: LaunchEntityRosterState,
        entities: [LaunchEntity] = [],
        telemetry: LaunchEntityRefreshTelemetry? = nil
    ) {
        self.state = state
        self.entities = entities
        self.lastTelemetry = telemetry
    }
}

// MARK: - Fixtures (previews + SnapshotTesting)

/// 🎬 Deterministic cast for Preview / snapshot catalogs — no live launchd.
public enum LaunchEntityRosterFixtures {
    /// 🌟 Hub-full cast with mixed running/stopped + isolated Mini flagged.
    public static func hubFullEntities() -> [LaunchEntity] {
        [
            LaunchEntity(
                slug: "job.nightly",
                label: "com.multibrain.nightly",
                kind: .cron,
                plistPath: "/tmp/com.multibrain.nightly.plist",
                schedule: .calendar(hour: 2, minute: 30, weekday: nil),
                status: .stopped,
                hostRole: .hub,
                purpose: "Dream batch — consolidate.py"
            ),
            LaunchEntity(
                slug: "svc.letta",
                label: "com.multibrain.letta",
                kind: .service,
                plistPath: "/tmp/com.multibrain.letta.plist",
                schedule: .keepAlive,
                status: .running,
                hostRole: .hub,
                purpose: "Letta Librarian :8283"
            ),
            LaunchEntity(
                slug: "river.dreamcatcher",
                label: "com.multibrain.dreamcatcher",
                kind: .watchdog,
                plistPath: "/tmp/com.multibrain.dreamcatcher.plist",
                schedule: .interval(seconds: 1800),
                status: .running,
                hostRole: .hub,
                purpose: "Idle-session dream census"
            ),
            LaunchEntity(
                slug: "tunnel.mac-mini-vnc",
                label: "com.local.mac-mini-vnc-tunnel",
                kind: .tunnel,
                plistPath: "/tmp/com.local.mac-mini-vnc-tunnel.plist",
                schedule: .keepAlive,
                status: .stopped,
                hostRole: .isolated,
                purpose: "Mac Mini VNC — isolated / non-hive"
            ),
        ]
    }

    /// 🛰️ Satellite cast — hub services honest n/a.
    public static func satelliteNAEntities() -> [LaunchEntity] {
        [
            LaunchEntity(
                slug: "job.health",
                label: "com.multibrain.health",
                kind: .cron,
                plistPath: "/tmp/com.multibrain.health.plist",
                schedule: .interval(seconds: 3600),
                status: .running,
                hostRole: .hub,
                purpose: "Hourly healthcheck"
            ),
            LaunchEntity(
                slug: "svc.letta",
                label: "com.multibrain.letta",
                kind: .service,
                plistPath: "/tmp/com.multibrain.letta.plist",
                schedule: .keepAlive,
                status: .notApplicable,
                hostRole: .hub,
                purpose: "Letta Librarian :8283"
            ),
            LaunchEntity(
                slug: "svc.ladybug.serve",
                label: "com.multibrain.index-server",
                kind: .service,
                plistPath: "/tmp/com.multibrain.index-server.plist",
                schedule: .keepAlive,
                status: .notApplicable,
                hostRole: .hub,
                purpose: "Ladybug index-server :8286"
            ),
        ]
    }

    public static func hubFullTelemetry() -> LaunchEntityRefreshTelemetry {
        LaunchEntityRefreshTelemetry.summarize(
            entities: hubFullEntities(),
            observingHostRole: .hub
        )
    }

    public static func satelliteTelemetry() -> LaunchEntityRefreshTelemetry {
        LaunchEntityRefreshTelemetry.summarize(
            entities: satelliteNAEntities(),
            observingHostRole: .satellite
        )
    }

    @MainActor
    public static func model(
        _ state: LaunchEntityRosterState,
        reduceMotion: Bool = false
    ) -> LaunchEntityRosterModel {
        switch state {
        case .loading:
            return LaunchEntityRosterModel(state: .loading, reduceMotion: reduceMotion)
        case .empty:
            return LaunchEntityRosterModel(state: .empty, entities: [], reduceMotion: reduceMotion)
        case .hubFull:
            return LaunchEntityRosterModel(
                state: .hubFull,
                entities: hubFullEntities(),
                lastTelemetry: hubFullTelemetry(),
                reduceMotion: reduceMotion
            )
        case .satelliteNA:
            return LaunchEntityRosterModel(
                state: .satelliteNA,
                entities: satelliteNAEntities(),
                lastTelemetry: satelliteTelemetry(),
                reduceMotion: reduceMotion
            )
        }
    }
}

// MARK: - SwiftUI View

/**
 * 🎭 LaunchEntityRosterView — visible LaunchAgent playbill (proof-quality).
 *
 * Impossible to ignore: marquee headline, telemetry strip, entity rows with
 * status / kind / host / schedule. Reduce-motion freezes status pulse chrome.
 */
@MainActor
public struct LaunchEntityRosterView: View {
    @Bindable private var model: LaunchEntityRosterModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// 🌟 When true, Environment reduce-motion merges into the model each body pass.
    private let honorSystemReduceMotion: Bool

    public init(model: LaunchEntityRosterModel, honorSystemReduceMotion: Bool = true) {
        self.model = model
        self.honorSystemReduceMotion = honorSystemReduceMotion
    }

    public var body: some View {
        let effectiveReduce = honorSystemReduceMotion
            ? (model.reduceMotion || systemReduceMotion)
            : model.reduceMotion

        return VStack(alignment: .leading, spacing: 12) {
            marquee
            telemetryStrip
            Divider()
            content(effectiveReduceMotion: effectiveReduce)
        }
        .padding(16)
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 520, minHeight: 280)
        .background(RosterBackdrop(state: model.state))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityIdentifier("launchEntityRoster.root")
        .accessibilityValue(model.state.rawValue)
        .onAppear {
            if honorSystemReduceMotion, systemReduceMotion {
                model.reduceMotion = true
            }
        }
        .onChange(of: systemReduceMotion) { _, newValue in
            guard honorSystemReduceMotion else { return }
            if newValue {
                model.reduceMotion = true
            }
        }
    }

    // MARK: - Chrome

    private var marquee: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.title2)
                    .foregroundStyle(marqueeTint)
                    .symbolEffect(
                        .pulse,
                        isActive: model.state == .loading && !model.reduceMotion
                    )
                Text(model.state.headline)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Text(model.state.rawValue.uppercased())
                    .font(.caption.weight(.heavy).monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(marqueeTint.opacity(0.2), in: Capsule())
                    .accessibilityIdentifier("launchEntityRoster.badge")
            }
            Text(model.state.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("launchEntityRoster.marquee")
    }

    private var telemetryStrip: some View {
        Group {
            if let pulse = model.lastTelemetry {
                HStack(spacing: 10) {
                    telemetryChip("run", value: "\(pulse.running)", tint: .green)
                    telemetryChip("stop", value: "\(pulse.stopped)", tint: .secondary)
                    telemetryChip("n/a", value: "\(pulse.notApplicable)", tint: .orange)
                    if pulse.isolatedMiniFlagged {
                        telemetryChip("mini", value: "ISOLATED", tint: .purple)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityIdentifier("launchEntityRoster.telemetry")
                .accessibilityLabel(pulse.displaySummary)
            } else if model.state == .loading {
                Text("Telemetry pending…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("launchEntityRoster.telemetry.pending")
            } else {
                Text("No telemetry pulse yet")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("launchEntityRoster.telemetry.none")
            }
        }
    }

    private func telemetryChip(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.bold).monospaced())
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func content(effectiveReduceMotion: Bool) -> some View {
        switch model.state {
        case .loading:
            loadingBody(effectiveReduceMotion: effectiveReduceMotion)
        case .empty:
            emptyBody
        case .hubFull, .satelliteNA:
            entityList(effectiveReduceMotion: effectiveReduceMotion)
        }
    }

    private func loadingBody(effectiveReduceMotion: Bool) -> some View {
        HStack(spacing: 12) {
            if effectiveReduceMotion {
                Image(systemName: "hourglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Observing LaunchAgents…")
                    .font(.headline)
                Text("Read-only · no bootstrap · no unload")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .accessibilityIdentifier("launchEntityRoster.loading")
    }

    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EMPTY ROSTER")
                .font(.title3.weight(.black))
                .foregroundStyle(.red)
            Text("Register LaunchEntities or the hive goes dark.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .accessibilityIdentifier("launchEntityRoster.empty")
    }

    private func entityList(effectiveReduceMotion: Bool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(model.entities) { entity in
                    LaunchEntityRowView(
                        entity: entity,
                        reduceMotion: effectiveReduceMotion
                    )
                }
            }
        }
        .frame(maxHeight: 320)
        .accessibilityIdentifier("launchEntityRoster.list")
    }

    private var marqueeTint: Color {
        switch model.state {
        case .loading: return .cyan
        case .empty: return .red
        case .hubFull: return .green
        case .satelliteNA: return .orange
        }
    }
}

// MARK: - Row

/// 🎭 One LaunchEntity as a loud, scannable roster row.
@MainActor
public struct LaunchEntityRowView: View {
    public let entity: LaunchEntity
    public let reduceMotion: Bool

    public init(entity: LaunchEntity, reduceMotion: Bool = false) {
        self.entity = entity
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusGlyph
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.slug)
                    .font(.headline.monospaced())
                Text(entity.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    metaChip(entity.kind.rawValue)
                    metaChip(entity.schedule.displaySummary)
                    metaChip(entity.hostRole.rawValue)
                    if entity.hostRole == .isolated {
                        metaChip("NON-HIVE")
                    }
                }
            }
            Spacer(minLength: 0)
            Text(statusLabel)
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(reduceMotion ? 0.12 : 0.22), in: Capsule())
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("launchEntityRoster.row.\(entity.slug)")
        .accessibilityLabel("\(entity.slug), \(statusLabel), \(entity.hostRole.rawValue)")
    }

    private var statusGlyph: some View {
        Circle()
            .fill(statusColor.opacity(reduceMotion ? 0.55 : 0.9))
            .frame(width: 12, height: 12)
            .padding(.top, 4)
    }

    private var statusLabel: String {
        switch entity.status {
        case .running: return "RUNNING"
        case .stopped: return "STOPPED"
        case .notApplicable: return "N/A"
        }
    }

    private var statusColor: Color {
        switch entity.status {
        case .running: return .green
        case .stopped: return .secondary
        case .notApplicable: return .orange
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.6), in: Capsule())
    }
}

// MARK: - Backdrop

/// 🎨 Soft state-tinted wash — keeps the roster from looking like a sparse stub.
private struct RosterBackdrop: View {
    let state: LaunchEntityRosterState

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(wash.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(wash.opacity(0.35), lineWidth: 1)
            )
    }

    private var wash: Color {
        switch state {
        case .loading: return .cyan
        case .empty: return .red
        case .hubFull: return .green
        case .satelliteNA: return .orange
        }
    }
}

// MARK: - Preview matrix (light / dark / Dynamic Type / reduce motion)

#if DEBUG
#Preview("Roster · Loading · Light") {
    LaunchEntityRosterView(
        model: LaunchEntityRosterFixtures.model(.loading),
        honorSystemReduceMotion: false
    )
    .preferredColorScheme(.light)
}

#Preview("Roster · Loading · Dark") {
    LaunchEntityRosterView(
        model: LaunchEntityRosterFixtures.model(.loading),
        honorSystemReduceMotion: false
    )
    .preferredColorScheme(.dark)
}

#Preview("Roster · Empty · Light") {
    LaunchEntityRosterView(
        model: LaunchEntityRosterFixtures.model(.empty),
        honorSystemReduceMotion: false
    )
    .preferredColorScheme(.light)
}

#Preview("Roster · Empty · Dark") {
    LaunchEntityRosterView(
        model: LaunchEntityRosterFixtures.model(.empty),
        honorSystemReduceMotion: false
    )
    .preferredColorScheme(.dark)
}

#Preview("Roster · Hub-Full · Light") {
    LaunchEntityRosterView(
        model: LaunchEntityRosterFixtures.model(.hubFull),
        honorSystemReduceMotion: false
    )
    .preferredColorScheme(.light)
}

#Preview("Roster · Hub-Full · Dark") {
    LaunchEntityRosterView(
        model: LaunchEntityRosterFixtures.model(.hubFull),
        honorSystemReduceMotion: false
    )
    .preferredColorScheme(.dark)
}

#Preview("Roster · Satellite-NA · Light") {
    LaunchEntityRosterView(
        model: LaunchEntityRosterFixtures.model(.satelliteNA),
        honorSystemReduceMotion: false
    )
    .preferredColorScheme(.light)
}

#Preview("Roster · Satellite-NA · Dark") {
    LaunchEntityRosterView(
        model: LaunchEntityRosterFixtures.model(.satelliteNA),
        honorSystemReduceMotion: false
    )
    .preferredColorScheme(.dark)
}

#Preview("Roster · Hub-Full · Dynamic Type XXXL") {
    LaunchEntityRosterView(
        model: LaunchEntityRosterFixtures.model(.hubFull),
        honorSystemReduceMotion: false
    )
    .preferredColorScheme(.light)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Roster · Hub-Full · Dark · Dynamic Type XXXL") {
    LaunchEntityRosterView(
        model: LaunchEntityRosterFixtures.model(.hubFull),
        honorSystemReduceMotion: false
    )
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Roster · Hub-Full · Reduce Motion") {
    LaunchEntityRosterView(
        model: LaunchEntityRosterFixtures.model(.hubFull, reduceMotion: true),
        honorSystemReduceMotion: false
    )
    .preferredColorScheme(.light)
}

#Preview("Roster · Loading · Reduce Motion · Dark") {
    LaunchEntityRosterView(
        model: LaunchEntityRosterFixtures.model(.loading, reduceMotion: true),
        honorSystemReduceMotion: false
    )
    .preferredColorScheme(.dark)
}
#endif
