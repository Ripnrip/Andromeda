import SwiftUI

// MARK: - Shared models

/// Pillar-chip palette shared by the showcase cards.
public enum PillarChipTone: Sendable {
    case live
    case partial
    case specified
    case dim

    var color: Color {
        switch self {
        case .live: return .andromedaLive
        case .partial: return .andromedaAmber
        case .specified: return .andromedaTeal
        case .dim: return .andromedaDim
        }
    }
}

/// A small state chip shown under each pillar card.
public struct PillarChip: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let label: String
    public let tone: PillarChipTone

    public init(_ key: String, _ label: String, _ tone: PillarChipTone) {
        self.key = key
        self.label = label
        self.tone = tone
    }
}

/// Stable skill-row states for the Agent Skills card.
public enum SkillRunState: String, Sendable {
    case loaded
    case invoke
    case failure

    var chip: PillarChip {
        switch self {
        case .loaded: return .init(rawValue, rawValue, .specified)
        case .invoke: return .init(rawValue, rawValue, .partial)
        case .failure: return .init(rawValue, rawValue, .dim)
        }
    }
}

/// A row in the Agent Skills card.
public struct SkillStatusRow: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let state: SkillRunState

    public init(_ name: String, _ state: SkillRunState) {
        self.name = name
        self.state = state
    }
}

/// Connectivity states for the MCP surface card.
public enum MCPSurfaceState: String, Sendable {
    case connected
    case degraded
    case offline

    var badge: String {
        switch self {
        case .connected: return "5 servers"
        case .degraded: return "3 of 5"
        case .offline: return "offline"
        }
    }

    var tone: PillarChipTone {
        switch self {
        case .connected: return .live
        case .degraded: return .partial
        case .offline: return .dim
        }
    }
}

/// Server node metadata for the MCP surface card.
public struct MCPServerNode: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let angle: Double
    public let radius: CGFloat

    public init(_ name: String, angle: Double, radius: CGFloat) {
        self.name = name
        self.angle = angle
        self.radius = radius
    }
}

/// Dream-stage states rendered by the Dreaming card.
public enum DreamPhase: String, Sendable {
    case awake
    case rem
    case deep

    var badge: String {
        switch self {
        case .awake: return "awake"
        case .rem: return "REM · consolidating"
        case .deep: return "deep · pruning"
        }
    }

    var tone: PillarChipTone {
        switch self {
        case .awake: return .specified
        case .rem, .deep: return .partial
        }
    }
}

/// Write-path stage state for the WAL / commit card.
public enum WriteStageState: String, Sendable {
    case buffered
    case validating
    case conflict
    case committed

    var badge: String { rawValue }

    var tone: PillarChipTone {
        switch self {
        case .buffered, .validating: return .specified
        case .conflict: return .partial
        case .committed: return .live
        }
    }
}

/// A memory family in the Memory Types grid.
public struct MemoryFamily: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let count: String
    public let tone: PillarChipTone
    public let glyphStyle: RoundedCornerStyle

    public init(_ key: String, _ name: String, _ count: String, _ tone: PillarChipTone, glyphStyle: RoundedCornerStyle = .circular) {
        self.key = key
        self.name = name
        self.count = count
        self.tone = tone
        self.glyphStyle = glyphStyle
    }
}

/// Backend lane data for the Retrieval Bench card.
public struct RetrievalLane: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let holds: String
    public let latencyMS: Int
    public let recall: Double
    public let tone: PillarChipTone

    public init(_ key: String, _ name: String, _ holds: String, latencyMS: Int, recall: Double, tone: PillarChipTone) {
        self.key = key
        self.name = name
        self.holds = holds
        self.latencyMS = latencyMS
        self.recall = recall
        self.tone = tone
    }
}

// MARK: - Shared sample data

public enum AndromedaPillarsData {
    public static let skills: [SkillStatusRow] = [
        .init("ui.package/specimen", .loaded),
        .init("snapshot/gallery-proof", .invoke),
        .init("slack/thread-sync", .loaded),
        .init("vault/live-smoke", .failure),
    ]

    public static let servers: [MCPServerNode] = [
        .init("filesystem", angle: -145, radius: 66),
        .init("zotero", angle: -72, radius: 74),
        .init("calendar", angle: 0, radius: 66),
        .init("slack", angle: 72, radius: 74),
        .init("browser", angle: 145, radius: 66),
    ]

    public static let memoryFamilies: [MemoryFamily] = [
        .init("episodic", "episodic", "22,940", .specified),
        .init("semantic", "semantic", "11,306", .live),
        .init("procedural", "procedural", "2,118", .live),
        .init("preference", "preference", "844", .partial),
        .init("constraint", "constraint", "391", .partial),
        .init("working", "working", "live", .dim),
    ]

    public static let retrievalLanes: [RetrievalLane] = [
        .init("web", "web search", "fresh facts", latencyMS: 410, recall: 0.64, tone: .dim),
        .init("graffiti", "graffiti", "change over time", latencyMS: 96, recall: 0.84, tone: .partial),
        .init("memory.vector", "vector", "resemblance", latencyMS: 22, recall: 0.78, tone: .specified),
        .init("procedural", "procedural", "how you act", latencyMS: 9, recall: 0.51, tone: .live),
        .init("episodic", "episodic log", "what happened", latencyMS: 37, recall: 0.88, tone: .partial),
    ]

    public static let writeLog: [String] = [
        "0x41f2  APPEND  trace/site-split  ok",
        "0x41f3  APPEND  trace/instrument-corr  ok",
        "0x41f4  APPEND  trace/pooled-estimate  CONFLICT",
        "0x41f5  FSYNC   pending",
    ]
}

// MARK: - Shared views

/// Rounded panel used by every showcase card.
public struct PillarCard<Content: View>: View {
    private let title: String
    private let subtitle: String
    private let badge: String
    private let badgeTone: PillarChipTone
    private let note: String
    private let content: Content

    public init(
        title: String,
        subtitle: String,
        badge: String,
        badgeTone: PillarChipTone,
        note: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.badgeTone = badgeTone
        self.note = note
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .cpTitle()
                        .foregroundStyle(Color.andromedaInk)
                    Text(subtitle)
                        .cpMeta()
                        .foregroundStyle(Color.andromedaMuted)
                }
                Spacer(minLength: 8)
                PillarBadge(text: badge, tone: badgeTone)
            }

            content
                .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)

            Text(note)
                .cpBody()
                .foregroundStyle(Color.andromedaMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.andromedaPanel.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.andromedaTeal.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
        )
    }
}

/// Small badge used in the card header.
public struct PillarBadge: View {
    public let text: String
    public let tone: PillarChipTone

    public init(text: String, tone: PillarChipTone) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .cpMeta()
            .foregroundStyle(tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(tone.color.opacity(0.12))
                    .overlay(Capsule().stroke(tone.color.opacity(0.35), lineWidth: 1))
            )
    }
}

/// Small chip row item rendered under a card's visual state.
public struct PillarStateChip: View {
    public let chip: PillarChip
    public let isActive: Bool

    public init(_ chip: PillarChip, isActive: Bool) {
        self.chip = chip
        self.isActive = isActive
    }

    public var body: some View {
        Text(chip.label)
            .cpMeta()
            .foregroundStyle(isActive ? chip.tone.color : Color.andromedaMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isActive ? chip.tone.color.opacity(0.14) : Color.white.opacity(0.03))
                    .overlay(
                        Capsule().stroke(
                            isActive ? chip.tone.color.opacity(0.35) : Color.andromedaTeal.opacity(0.08),
                            lineWidth: 1
                        )
                    )
            )
    }
}

/// Shared section footer for rows of chips.
public struct PillarChipRow: View {
    public let chips: [PillarChip]
    public let activeKey: String

    public init(chips: [PillarChip], activeKey: String) {
        self.chips = chips
        self.activeKey = activeKey
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(chips) { chip in
                PillarStateChip(chip, isActive: chip.key == activeKey)
            }
        }
    }
}

// MARK: - Individual cards

/// The LLM proxy card: one entry surface, several client-facing lanes.
public struct LLMProxyPillarCard: View {
    public enum ProxyState: String, Sendable {
        case idle
        case routing
        case saturated

        var badge: String {
            switch self {
            case .idle: return "ready"
            case .routing: return "routing"
            case .saturated: return "load shedding"
            }
        }

        var tone: PillarChipTone {
            switch self {
            case .idle: return .specified
            case .routing: return .live
            case .saturated: return .partial
            }
        }
    }

    public let state: ProxyState
    @State private var travel = false

    public init(state: ProxyState = .routing) {
        self.state = state
    }

    public var body: some View {
        PillarCard(
            title: "LLM proxy",
            subtitle: "one endpoint · many minds",
            badge: state.badge,
            badgeTone: state.tone,
            note: "Provider choice stays behind the curtain. Clients hit stable lanes and see capacity, not vendor trivia."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                proxyDiagram
                PillarChipRow(
                    chips: [.init("idle", "idle", .specified), .init("routing", "routing", .live), .init("saturated", "saturated", .partial)],
                    activeKey: state.rawValue
                )
            }
        }
    }

    private var proxyDiagram: some View {
        HStack(spacing: 16) {
            ZStack {
                BreathingRing(color: .andromedaTeal)
                    .frame(width: 54, height: 54)
                Circle().fill(Color.andromedaTeal).frame(width: 12, height: 12)
                    .shadow(color: .andromedaTeal, radius: 8)
            }
            .frame(width: 54, height: 54)

            VStack(spacing: 14) {
                proxyLane(label: "infer.write · fast", offset: travel ? 38 : -8, tone: .live)
                proxyLane(label: "infer.write · deep", offset: travel ? 54 : -10, tone: .specified)
                proxyLane(label: "infer.write · code", offset: travel ? 44 : -6, tone: .partial)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                travel = true
            }
        }
    }

    private func proxyLane(label: String, offset: CGFloat, tone: PillarChipTone) -> some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.andromedaTeal.opacity(0.08))
                    .frame(width: 108, height: 2)
                Circle()
                    .fill(tone.color)
                    .frame(width: 7, height: 7)
                    .shadow(color: tone.color, radius: 6)
                    .offset(x: offset)
            }
            .frame(width: 108, height: 10)

            Text(label)
                .cpMeta()
                .foregroundStyle(Color.andromedaInk)
        }
    }
}

/// A skills card that shows explicit capability load / invoke / failure state.
public struct AgentSkillsPillarCard: View {
    public let rows: [SkillStatusRow]

    public init(rows: [SkillStatusRow] = AndromedaPillarsData.skills) {
        self.rows = rows
    }

    public var body: some View {
        PillarCard(
            title: "Agent skills",
            subtitle: "capabilities it can grow into",
            badge: "4 skills",
            badgeTone: .specified,
            note: "A failed skill should fail visibly. The answer can still arrive without that capability, but the gap gets named."
        ) {
            VStack(spacing: 6) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Circle().fill(row.state.chip.tone.color).frame(width: 6, height: 6)
                            .shadow(color: row.state.chip.tone.color, radius: 4)
                        Text(row.name)
                            .cpMeta()
                            .foregroundStyle(Color.andromedaInk)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        PillarStateChip(row.state.chip, isActive: true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.03))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.andromedaTeal.opacity(0.08)))
                    )
                }
            }
        }
    }
}

/// A radial MCP card that makes the allowed tool surface legible.
public struct MCPSurfacePillarCard: View {
    public let state: MCPSurfaceState
    public let servers: [MCPServerNode]
    @State private var pulse = false

    public init(state: MCPSurfaceState = .degraded, servers: [MCPServerNode] = AndromedaPillarsData.servers) {
        self.state = state
        self.servers = servers
    }

    public var body: some View {
        PillarCard(
            title: "MCP surface",
            subtitle: "the tools it is allowed to touch",
            badge: state.badge,
            badgeTone: state.tone,
            note: "This ring is the permission model made visible. The absence of a server means the capability really is absent."
        ) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(state.tone.color.opacity(0.22), lineWidth: 1)
                        .frame(width: 92, height: 92)
                    Circle()
                        .stroke(state.tone.color.opacity(0.35), lineWidth: 1)
                        .frame(width: pulse ? 104 : 86, height: pulse ? 104 : 86)
                        .opacity(pulse ? 0 : 0.85)
                    Circle()
                        .fill(state.tone.color)
                        .frame(width: 36, height: 36)
                        .shadow(color: state.tone.color, radius: 10)
                        .overlay(Text("mcp").cpMeta().foregroundStyle(Color.andromedaVoid))

                    ForEach(Array(servers.enumerated()), id: \.element.id) { index, server in
                        let isDimmed = state == .offline || (state == .degraded && (index == 1 || index == 4))
                        let point = pointForServer(server)
                        VStack(spacing: 4) {
                            Circle().fill(isDimmed ? Color.andromedaDim : state.tone.color).frame(width: 6, height: 6)
                            Text(server.name)
                                .cpMeta()
                                .foregroundStyle(isDimmed ? Color.andromedaMuted : Color.andromedaInk)
                        }
                        .position(point)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 114)
                .onAppear {
                    withAnimation(.easeOut(duration: 2.1).repeatForever(autoreverses: false)) {
                        pulse = true
                    }
                }

                PillarChipRow(
                    chips: [.init("connected", "connected", .live), .init("degraded", "degraded", .partial), .init("offline", "offline", .dim)],
                    activeKey: state.rawValue
                )
            }
        }
    }

    /// Computes the radial label position for an MCP server tag.
    private func pointForServer(_ server: MCPServerNode) -> CGPoint {
        let radians = server.angle * .pi / 180
        let center = CGPoint(x: 140, y: 56)
        return CGPoint(
            x: center.x + cos(radians) * server.radius,
            y: center.y + sin(radians) * server.radius
        )
    }
}

/// Dreaming card: visible stage changes while consolidation and pruning run.
public struct DreamingPillarCard: View {
    public let phase: DreamPhase
    @State private var drift = false

    public init(phase: DreamPhase = .rem) {
        self.phase = phase
    }

    public var body: some View {
        PillarCard(
            title: "Dreaming",
            subtitle: "what it does while you sleep",
            badge: phase.badge,
            badgeTone: phase.tone,
            note: phase == .awake
                ? "While you work, Andromeda only captures. Reorganising memory mid-conversation would make its own answers unstable."
                : "Reflection is a visible system behavior: contradictions reconcile in REM, and dead fragments prune in deep sleep."
        ) {
            VStack(spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundGradient)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(phase.tone.color.opacity(0.2)))

                    ForEach(0..<8, id: \.self) { index in
                        Circle()
                            .fill(phase.tone.color.opacity(phase == .awake ? 0.28 : 0.9))
                            .frame(width: CGFloat(3 + index % 3), height: CGFloat(3 + index % 3))
                            .offset(x: CGFloat(12 + (index * 23) % 220), y: drift ? CGFloat(-24 - (index * 7) % 32) : CGFloat((index * 11) % 24))
                            .opacity(drift ? 0.18 : 0.7)
                            .animation(.easeInOut(duration: Double(4 + index)).repeatForever(autoreverses: true), value: drift)
                    }

                    REMTrace(phase: phase)
                        .stroke(phase.tone.color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                        .frame(height: 42)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
                .frame(height: 108)
                .onAppear { drift = true }

                PillarChipRow(
                    chips: [.init("awake", "awake", .specified), .init("rem", "REM", .partial), .init("deep", "deep", .partial)],
                    activeKey: phase.rawValue
                )
            }
        }
    }

    private var backgroundGradient: LinearGradient {
        switch phase {
        case .awake:
            return LinearGradient(colors: [Color.andromedaPanel, Color.andromedaVoid], startPoint: .top, endPoint: .bottom)
        case .rem:
            return LinearGradient(colors: [Color.andromedaPanel, Color.andromedaTeal.opacity(0.12), Color.andromedaVoid], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .deep:
            return LinearGradient(colors: [Color(red: 0.06, green: 0.05, blue: 0.11), Color.andromedaVoid], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Write path card: append, validate, dedupe, commit with a visible WAL.
public struct WritePathPillarCard: View {
    public let state: WriteStageState
    @State private var settled = false
    private let stages = ["capture", "validate", "dedupe", "commit"]

    public init(state: WriteStageState = .conflict) {
        self.state = state
    }

    public var body: some View {
        PillarCard(
            title: "Write path",
            subtitle: "nothing enters memory unwitnessed",
            badge: state.badge,
            badgeTone: state.tone,
            note: state == .conflict
                ? "Conflicts surface, queue, and wait for the next reflective pass — nothing silently overwrites a held belief."
                : "Writes land in a log first. If the process dies mid-thought, only the accounted trace survives."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                        VStack(spacing: 6) {
                            Circle()
                                .fill(colorForStage(index))
                                .frame(width: activeIndex == index ? 13 : 9, height: activeIndex == index ? 13 : 9)
                                .shadow(color: colorForStage(index), radius: activeIndex == index ? 8 : 0)
                            Text(stage)
                                .cpMeta()
                                .foregroundStyle(index <= activeIndex ? Color.andromedaInk : Color.andromedaMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .trailing) {
                            if index < stages.count - 1 {
                                Rectangle()
                                    .fill(index < activeIndex ? colorForStage(index) : Color.andromedaTeal.opacity(0.1))
                                    .frame(height: 1.5)
                                    .offset(x: 42)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(AndromedaPillarsData.writeLog.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .cpMeta()
                            .foregroundStyle(index == 2 && state == .conflict ? Color.andromedaAmber : Color.andromedaMuted)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.03))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.andromedaTeal.opacity(0.08)))
                )

                PillarChipRow(
                    chips: [
                        .init("buffered", "buffered", .specified),
                        .init("validating", "validating", .specified),
                        .init("committed", "committed", .live),
                        .init("conflict", "conflict", .partial),
                    ],
                    activeKey: state.rawValue
                )
            }
            .onAppear { settled = true }
        }
    }

    private var activeIndex: Int {
        switch state {
        case .buffered: return 0
        case .validating: return 1
        case .conflict: return 2
        case .committed: return 3
        }
    }

    private func colorForStage(_ index: Int) -> Color {
        if index < activeIndex { return state == .committed ? Color.andromedaLive : Color.andromedaTeal }
        if index == activeIndex { return state.tone.color }
        return Color.andromedaDim
    }
}

/// Memory types card: six families, one visible palette.
public struct MemoryTypesPillarCard: View {
    public let families: [MemoryFamily]

    public init(families: [MemoryFamily] = AndromedaPillarsData.memoryFamilies) {
        self.families = families
    }

    public var body: some View {
        PillarCard(
            title: "Memory types",
            subtitle: "six ways to be remembered",
            badge: "37,599 traces",
            badgeTone: .specified,
            note: "Different memory families should look and behave differently. Preference is not episodic, and working memory is never sold as durable storage."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(families) { family in
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 5, style: family.glyphStyle)
                                .fill(family.tone.color)
                                .frame(width: 16, height: 16)
                                .shadow(color: family.tone.color.opacity(0.45), radius: 6)
                            Text(family.name)
                                .cpMeta()
                                .foregroundStyle(Color.andromedaInk)
                            Text(family.count)
                                .cpMeta()
                                .foregroundStyle(Color.andromedaMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(family.tone.color.opacity(0.08))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(family.tone.color.opacity(0.16)))
                        )
                    }
                }

                PillarBadge(text: "written by reflection and capture", tone: .partial)
            }
        }
    }
}

/// Retrieval bench card: lane winner depends on what kind of truth the question needs.
public struct RetrievalBenchPillarCard: View {
    public let lanes: [RetrievalLane]
    public let winner: String
    @State private var animateBars = false

    public init(lanes: [RetrievalLane] = AndromedaPillarsData.retrievalLanes, winner: String = "episodic") {
        self.lanes = lanes
        self.winner = winner
    }

    public var body: some View {
        PillarCard(
            title: "Retrieval bench",
            subtitle: "truth changes with the question",
            badge: winnerLabel,
            badgeTone: winnerTone,
            note: "The winner should depend on the question: fresh facts, resemblance, habit, chronology, or what literally happened."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    PillarBadge(text: "question · chronology", tone: .partial)
                    Text("“When did we stop running non-visual snapshots?”")
                        .cpBody()
                        .foregroundStyle(Color.andromedaInk)
                        .lineLimit(2)
                }

                VStack(spacing: 8) {
                    ForEach(lanes) { lane in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(lane.name)
                                    .cpMeta()
                                    .foregroundStyle(lane.key == winner ? Color.andromedaInk : Color.andromedaMuted)
                                Spacer()
                                Text("\(lane.latencyMS) ms · \(Int(lane.recall * 100))%")
                                    .cpMeta()
                                    .foregroundStyle(lane.key == winner ? lane.tone.color : Color.andromedaMuted)
                            }
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.andromedaTeal.opacity(0.08)).frame(height: 8)
                                Capsule()
                                    .fill(lane.tone.color)
                                    .frame(width: animateBars ? max(CGFloat(lane.recall) * 180, 18) : 10, height: 8)
                            }
                            Text(lane.holds)
                                .cpMeta()
                                .foregroundStyle(Color.andromedaMuted)
                        }
                    }
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.9)) {
                    animateBars = true
                }
            }
        }
    }

    private var winnerLabel: String {
        lanes.first(where: { $0.key == winner })?.name ?? "winner"
    }

    private var winnerTone: PillarChipTone {
        lanes.first(where: { $0.key == winner })?.tone ?? .specified
    }
}

// MARK: - Composite surface

/// The multi-card export rendered as a package surface instead of a one-off HTML mock.
public struct AndromedaPillarsShowcase: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
                    spacing: 18
                ) {
                    LLMProxyPillarCard()
                    AgentSkillsPillarCard()
                    MCPSurfacePillarCard()
                    DreamingPillarCard()
                    WritePathPillarCard()
                    MemoryTypesPillarCard()
                }

                RetrievalBenchPillarCard()
            }
            .padding(20)
        }
        .background(AndromedaSurface().ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("Andromida · component sets")
                Text("The six pillars")
                    .cpDisplay(38)
                    .foregroundStyle(Color.andromedaInk)
                Text("Every pillar is a live component set, not a diagram — each one carries states, motion, and the vocabulary the HUD can borrow when it talks about that subsystem.")
                    .cpBody()
                    .foregroundStyle(Color.andromedaMuted)
                    .frame(maxWidth: 720, alignment: .leading)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                PillarBadge(text: "7 cards", tone: .specified)
                PillarBadge(text: "24+ states", tone: .partial)
            }
        }
    }
}

// MARK: - Supporting shapes

/// The stylized REM trace used by the Dreaming card.
public struct REMTrace: Shape {
    public let phase: DreamPhase

    public init(phase: DreamPhase) {
        self.phase = phase
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: midY))

        switch phase {
        case .awake:
            path.addCurve(to: CGPoint(x: rect.maxX, y: midY), control1: CGPoint(x: rect.width * 0.25, y: midY - 3), control2: CGPoint(x: rect.width * 0.75, y: midY + 3))
        case .rem:
            var x = rect.minX
            let step = rect.width / 10
            for index in 0..<10 {
                let y = midY + (index.isMultiple(of: 2) ? -10 : 10)
                path.addQuadCurve(to: CGPoint(x: x + step, y: y), control: CGPoint(x: x + step / 2, y: midY))
                x += step
            }
        case .deep:
            path.addCurve(to: CGPoint(x: rect.maxX, y: midY), control1: CGPoint(x: rect.width * 0.25, y: midY), control2: CGPoint(x: rect.width * 0.75, y: midY))
        }

        return path
    }
}

// MARK: - Previews

#Preview("Pillars showcase · dark") {
    AndromedaPillarsShowcase()
        .frame(width: 1160, height: 980)
        .preferredColorScheme(.dark)
}

#Preview("Pillars showcase · light") {
    AndromedaPillarsShowcase()
        .frame(width: 1160, height: 980)
        .preferredColorScheme(.light)
}

#Preview("Pillar cards") {
    SchemePair {
        VStack(spacing: 12) {
            LLMProxyPillarCard()
            RetrievalBenchPillarCard()
        }
        .frame(width: 420)
    }
}
