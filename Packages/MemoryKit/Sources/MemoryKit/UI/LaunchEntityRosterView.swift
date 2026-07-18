/**
 * 🎭 The LaunchEntityRosterView - The Impossible-to-Ignore Playbill
 *
 * Modern SwiftUI: material chrome, ContentUnavailableView, LazyVStack,
 * `.animation(_:value:)`, extracted rows, reduce-motion safe pulse.
 */

import Foundation
import SwiftUI

// MARK: - Presentation states

public enum LaunchEntityRosterState: String, Sendable, Equatable, CaseIterable {
    case loading
    case empty
    case hubFull = "hub-full"
    case satelliteNA = "satellite-na"

    public var headline: String {
        switch self {
        case .loading: return "Launch Entities · Loading"
        case .empty: return "Launch Entities · EMPTY"
        case .hubFull: return "Launch Entities · Hub Roster"
        case .satelliteNA: return "Launch Entities · Satellite (n/a honesty)"
        }
    }

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

    public var accessibilityIdentifier: String {
        "launchEntityRoster.state.\(rawValue)"
    }
}

// MARK: - Model

@MainActor
@Observable
public final class LaunchEntityRosterModel {
    public var state: LaunchEntityRosterState
    public var entities: [LaunchEntity]
    public var lastTelemetry: LaunchEntityRefreshTelemetry?
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

    public var accessibilityLabel: String {
        var parts = [state.headline]
        if let lastTelemetry {
            parts.append(lastTelemetry.displaySummary)
        } else {
            parts.append("\(entities.count) entities")
        }
        return parts.joined(separator: ". ")
    }

    public func apply(registry: LaunchEntityRegistry) {
        let roster = registry.all()
        lastTelemetry = registry.lastTelemetry
        entities = roster
        if roster.isEmpty {
            state = .empty
            return
        }
        switch registry.observingHostRole {
        case .hub: state = .hubFull
        case .satellite, .isolated: state = .satelliteNA
        }
    }

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

// MARK: - Fixtures

public enum LaunchEntityRosterFixtures {
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

// MARK: - View

@MainActor
public struct LaunchEntityRosterView: View {
    @Bindable private var model: LaunchEntityRosterModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private let honorSystemReduceMotion: Bool

    public init(model: LaunchEntityRosterModel, honorSystemReduceMotion: Bool = true) {
        self.model = model
        self.honorSystemReduceMotion = honorSystemReduceMotion
    }

    public var body: some View {
        let effectiveReduce = honorSystemReduceMotion
            ? (model.reduceMotion || systemReduceMotion)
            : model.reduceMotion

        VStack(alignment: .leading, spacing: 12) {
            LaunchEntityMarquee(state: model.state, reduceMotion: effectiveReduce)
            LaunchEntityTelemetryStrip(telemetry: model.lastTelemetry, state: model.state)
            Divider().opacity(0.35)
            LaunchEntityRosterContent(model: model, reduceMotion: effectiveReduce)
        }
        .padding(16)
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 520, minHeight: 280)
        .memoryKitPanelChrome(cornerRadius: 14)
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(marqueeTint.opacity(0.35), lineWidth: 1)
        }
        .animation(MemoryKitMotion.animation(reduceMotion: effectiveReduce), value: model.state)
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
            guard honorSystemReduceMotion, newValue else { return }
            model.reduceMotion = true
        }
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

// MARK: - Subviews

private struct LaunchEntityMarquee: View {
    let state: LaunchEntityRosterState
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.title2)
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, isActive: state == .loading && !reduceMotion)
                Text(state.headline)
                    .font(.title2.weight(.bold))
                Spacer(minLength: 0)
                Text(state.rawValue.uppercased())
                    .font(.caption.weight(.heavy).monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.2), in: Capsule())
                    .accessibilityIdentifier("launchEntityRoster.badge")
            }
            Text(state.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("launchEntityRoster.marquee")
    }

    private var tint: Color {
        switch state {
        case .loading: return .cyan
        case .empty: return .red
        case .hubFull: return .green
        case .satelliteNA: return .orange
        }
    }
}

private struct LaunchEntityTelemetryStrip: View {
    let telemetry: LaunchEntityRefreshTelemetry?
    let state: LaunchEntityRosterState

    var body: some View {
        Group {
            if let pulse = telemetry {
                HStack(spacing: 10) {
                    chip("run", value: "\(pulse.running)", tint: .green)
                    chip("stop", value: "\(pulse.stopped)", tint: .secondary)
                    chip("n/a", value: "\(pulse.notApplicable)", tint: .orange)
                    if pulse.isolatedMiniFlagged {
                        chip("mini", value: "ISOLATED", tint: .purple)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityIdentifier("launchEntityRoster.telemetry")
                .accessibilityLabel(pulse.displaySummary)
            } else if state == .loading {
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

    private func chip(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.bold).monospaced())
                .foregroundStyle(tint)
        }
        .memoryKitChipChrome()
    }
}

private struct LaunchEntityRosterContent: View {
    @Bindable var model: LaunchEntityRosterModel
    let reduceMotion: Bool

    var body: some View {
        switch model.state {
        case .loading:
            HStack(spacing: 12) {
                if reduceMotion {
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
        case .empty:
            ContentUnavailableView {
                Label("EMPTY ROSTER", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text("Register LaunchEntities or the hive goes dark.")
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .accessibilityIdentifier("launchEntityRoster.empty")
        case .hubFull, .satelliteNA:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.entities) { entity in
                        LaunchEntityRowView(entity: entity, reduceMotion: reduceMotion)
                    }
                }
            }
            .frame(maxHeight: 320)
            .accessibilityIdentifier("launchEntityRoster.list")
        }
    }
}

// MARK: - Row

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
            Circle()
                .fill(statusColor.opacity(reduceMotion ? 0.55 : 0.9))
                .frame(width: 12, height: 12)
                .padding(.top, 4)
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
        .memoryKitChipChrome(cornerRadius: 10)
        .accessibilityIdentifier("launchEntityRoster.row.\(entity.slug)")
        .accessibilityLabel("\(entity.slug), \(statusLabel), \(entity.hostRole.rawValue)")
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

#if DEBUG
#Preview("Roster · Hub-Full · Dark") {
    LaunchEntityRosterView(
        model: LaunchEntityRosterFixtures.model(.hubFull),
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

#Preview("Roster · Loading · Reduce Motion") {
    LaunchEntityRosterView(
        model: LaunchEntityRosterFixtures.model(.loading, reduceMotion: true),
        honorSystemReduceMotion: false
    )
    .preferredColorScheme(.dark)
}
#endif
