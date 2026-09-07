import Foundation
import Observation
import os

// MARK: - Internal observability

//
// The console's own flight recorder. Every meaningful state change becomes a
// typed event — never a concatenated string at the call site. Events carry
// their glyph, name, and summary; `Codable` so journals serialize; `Sendable`
// so they can cross boundaries. `os.Logger` gets the emoji-prefixed line at
// the single bridge point (`OrchestratorLog`), and the in-memory journal
// feeds the States screen's SELF section — internal observability that
// exists before any provider wiring.

/// One internal console event. Associated values, not strings: the payload
/// IS the type. `glyph`/`name`/`summary` are derived in one place each.
public enum OrchestratorEvent: Codable, Equatable, Sendable {
    case screenChanged(OrchestratorModel.Screen)
    case hudDetached(Bool)
    case launchPhase(OrchestratorModel.LaunchPhase)
    case onboardingAdvanced(from: Int, to: Int?)
    case onboardingSkipped(from: Int)
    case wizardOpened(OrchestratorModel.Wizard)
    case wizardAdvanced(from: Int, to: Int)
    case wizardClosed(atStep: Int)
    case scopeToggled(String, withheld: Bool)
    case probeStarted(lineCount: Int)
    case probeAdvanced(line: Int, of: Int)
    case probeCompleted
    case streamPaused
    case streamResumed(speed: Double)
    case replayRequested

    /// The emoji the journal and log lines are prefixed with — one per event,
    /// in one switch (canon: enums switch, call sites never concatenate).
    public var glyph: String {
        switch self {
        case .screenChanged: "🧭"
        case .hudDetached: "🛰"
        case .launchPhase: "🚀"
        case .onboardingAdvanced: "🪜"
        case .onboardingSkipped: "⏭"
        case .wizardOpened: "🧙"
        case .wizardAdvanced: "🔐"
        case .wizardClosed: "✅"
        case .scopeToggled: "🗝"
        case .probeStarted: "🔬"
        case .probeAdvanced: "🧪"
        case .probeCompleted: "🏁"
        case .streamPaused: "⏸"
        case .streamResumed: "▶️"
        case .replayRequested: "🔁"
        }
    }

    /// Stable, human-readable event name — the localization key candidate.
    public var name: String {
        switch self {
        case .screenChanged: "screen changed"
        case .hudDetached: "hud placement"
        case .launchPhase: "launch reveal"
        case .onboardingAdvanced: "onboarding advanced"
        case .onboardingSkipped: "onboarding skipped"
        case .wizardOpened: "wizard opened"
        case .wizardAdvanced: "wizard advanced"
        case .wizardClosed: "wizard closed"
        case .scopeToggled: "scope toggled"
        case .probeStarted: "probe started"
        case .probeAdvanced: "probe advanced"
        case .probeCompleted: "probe completed"
        case .streamPaused: "stream paused"
        case .streamResumed: "stream resumed"
        case .replayRequested: "first-run replay"
        }
    }

    /// One-line derived summary of the payload.
    public var summary: String {
        switch self {
        case let .screenChanged(screen): screen.title
        case let .hudDetached(detached): detached ? "detached — floating NSPanel" : "docked — console corner"
        case let .launchPhase(phase): phase.describe
        case let .onboardingAdvanced(from, to):
            to.map { "step \(from) → \($0)" } ?? "step \(from) → done"
        case let .onboardingSkipped(from): "step \(from) → dismissed"
        case let .wizardOpened(wizard): wizard.describe
        case let .wizardAdvanced(from, to): "step \(from) → \(to)"
        case let .wizardClosed(atStep): "at step \(atStep)"
        case let .scopeToggled(scope, withheld): "\(scope) — \(withheld ? "withheld" : "granted")"
        case let .probeStarted(lineCount): "\(lineCount) checklist lines"
        case let .probeAdvanced(line, of): "line \(line)/\(of)"
        case .probeCompleted: "all lines verified"
        case .streamPaused: "ticker halted"
        case let .streamResumed(speed): "speed " + String(format: "%.1f", speed) + "×"
        case .replayRequested: "launch + onboarding"
        }
    }
}

extension OrchestratorModel.LaunchPhase {
    /// Derived description — no string concatenation at call sites.
    var describe: String {
        switch self {
        case .idle: "settled"
        case .markOnly: "mark beat"
        case .wordmark: "wordmark beat"
        case .tagline: "tagline beat"
        case .dissolving: "dissolving beat"
        }
    }
}

extension OrchestratorModel.Wizard {
    var describe: String {
        switch self {
        case .addModel: "add a model"
        case .addMCPServer: "add an MCP server"
        }
    }
}

/// One journal record. `Identifiable` for SwiftUI lists; `Codable` so a
/// journal survives export; timestamps travel as timeIntervalSinceReferenceDate.
public struct JournalEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let at: Date
    public let event: OrchestratorEvent

    public init(id: UUID = UUID(), at: Date = Date(), event: OrchestratorEvent) {
        self.id = id
        self.at = at
        self.event = event
    }

    /// The complete derived line — glyph + name + summary.
    public var display: String {
        "\(event.glyph) \(event.name): \(event.summary)"
    }

    /// Short relative age — derived, no call-site formatting. The reference
    /// instant is injected so snapshots pin it.
    public func ago(since now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(at))
        if seconds < 60 {
            return String(Int(seconds)) + "s"
        }
        if seconds < 3600 {
            return String(Int(seconds / 60)) + "m"
        }
        return String(Int(seconds / 3600)) + "h"
    }
}

/// The `os.Logger` bridge — the ONLY place raw log strings are formed.
public enum OrchestratorLog {
    public static let subsystem = "ai.andromeda.orchestrator"

    /// One logger per category; the emoji prefix rides on the event, not on
    /// format strings scattered around the codebase.
    public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    public static let navigation = Logger(subsystem: subsystem, category: "navigation")
    public static let flows = Logger(subsystem: subsystem, category: "flows")
    public static let stream = Logger(subsystem: subsystem, category: "stream")

    /// Emits one structured line. `info` for the routine, `notice` for
    /// transitions worth seeing in a default Console.app filter.
    public static func emit(_ entry: JournalEntry) {
        let line = entry.display
        switch entry.event {
        case .screenChanged, .hudDetached, .replayRequested:
            navigation.notice("\(line, privacy: .public)")
        case .launchPhase, .onboardingAdvanced, .onboardingSkipped:
            lifecycle.notice("\(line, privacy: .public)")
        case .wizardOpened, .wizardAdvanced, .wizardClosed, .scopeToggled,
             .probeStarted, .probeAdvanced, .probeCompleted:
            flows.info("\(line, privacy: .public)")
        case .streamPaused, .streamResumed:
            stream.notice("\(line, privacy: .public)")
        }
    }
}

/// The in-memory ring journal. `@Observable` so views can watch it; the
/// capacity is a named constant, not a magic number.
@MainActor
@Observable
public final class OrchestratorJournal {
    /// Bounded ring — the console keeps a flight recorder, not a leak.
    public static let capacity = 256

    public private(set) var entries: [JournalEntry] = []

    public init(entries: [JournalEntry] = []) {
        self.entries = Array(entries.suffix(Self.capacity))
    }

    public func record(_ event: OrchestratorEvent) {
        let entry = JournalEntry(event: event)
        entries.append(entry)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
        OrchestratorLog.emit(entry)
    }

    /// Most recent first — the reading order of a flight recorder.
    public var recent: [JournalEntry] {
        entries.reversed()
    }

    /// Replaces the ring contents — fixtures and previews only. Bounded by
    /// `capacity`, same as `record`.
    public func replaceAll(with seeded: [JournalEntry]) {
        entries = Array(seeded.suffix(Self.capacity))
    }
}

#if canImport(SwiftUI)
    import SwiftUI

    // MARK: - Journal wall

//
    // The SELF section on the States screen: the console reading its own flight
    // recorder. Internal observability that exists before provider wiring.

    /// Environment clock for the journal wall — snapshots pin it; the app runs
    /// real time. Same law as reduce-motion stills: determinism from the
    /// environment, never from hoping the wall clock holds still.
    public struct JournalNowKey: EnvironmentKey {
        public static let defaultValue: @Sendable () -> Date = { Date() }
    }

    public extension EnvironmentValues {
        var journalNow: @Sendable () -> Date {
            get { self[JournalNowKey.self] }
            set { self[JournalNowKey.self] = newValue }
        }
    }

    public struct JournalWall: View {
        @Environment(\.palette) private var palette
        @Environment(\.journalNow) private var now
        @Bindable public var journal: OrchestratorJournal

        /// Bounded wall height — the section scrolls inside itself.
        private static let wallHeight: CGFloat = 240

        public init(journal: OrchestratorJournal) {
            self.journal = journal
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    ScreenHeader(
                        title: "Self — internal events",
                        subtitle: "The console's own flight recorder. Typed events, emoji-glyphed, \(OrchestratorJournal.capacity)-entry ring."
                    )
                    Spacer()
                    Text("\(journal.entries.count)/\(OrchestratorJournal.capacity)")
                        .font(OrchestratorFont.mono(9.5))
                        .foregroundStyle(palette.muted)
                        .monospacedDigit()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if journal.entries.isEmpty {
                            Text("No events yet — navigate, open a wizard, toggle the stream.")
                                .font(OrchestratorFont.mono(10))
                                .foregroundStyle(palette.dim)
                        }
                        ForEach(journal.recent) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(entry.event.glyph)
                                Text(entry.event.name)
                                    .font(OrchestratorFont.mono(9.5, .semibold))
                                    .foregroundStyle(palette.muted)
                                Text(entry.event.summary)
                                    .font(OrchestratorFont.mono(10))
                                    .foregroundStyle(palette.ink)
                                    .lineLimit(1)
                                Spacer()
                                Text(entry.ago(since: now()))
                                    .font(OrchestratorFont.mono(9))
                                    .foregroundStyle(palette.dim)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(palette.panel, in: .rect(cornerRadius: 7))
                        }
                    }
                }
                .frame(maxHeight: Self.wallHeight)
            }
            .padding(16)
            .panel()
        }
    }

    #Preview("Journal · obsidian") {
        let journal = OrchestratorJournal()
        journal.record(.screenChanged(.overview))
        journal.record(.wizardOpened(.addModel))
        journal.record(.scopeToggled("mcp.write", withheld: true))
        journal.record(.probeAdvanced(line: 3, of: 5))
        journal.record(.probeCompleted)
        journal.record(.hudDetached(true))
        journal.record(.streamPaused)
        return JournalWall(journal: journal)
            .frame(width: 640)
            .padding(24)
            .background(OrchestratorPalette.obsidian.void)
            .orchestratorPalette()
    }

    #Preview("Journal · light") {
        let journal = OrchestratorJournal()
        journal.record(.launchPhase(.wordmark))
        journal.record(.onboardingAdvanced(from: 0, to: 1))
        journal.record(.onboardingSkipped(from: 3))
        journal.record(.replayRequested)
        return JournalWall(journal: journal)
            .frame(width: 640)
            .padding(24)
            .background(OrchestratorPalette.observatory.void)
            .environment(\.colorScheme, .light)
            .orchestratorPalette()
    }
#endif
