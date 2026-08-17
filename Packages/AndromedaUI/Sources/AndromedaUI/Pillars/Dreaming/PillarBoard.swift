

import SwiftUI

// MARK: - Driver
// Optional: the pure views above take a Binding and animate on change. This
// object drives all nine on one clock, and stops cycling a pillar the moment
// the user pins it by tapping a chip.

@MainActor
@Observable
public final class PillarDriver {
    public var dream: DreamState = .rem
    public var memory: MemoryState = .consolidating
    public var perception: PerceptionState = .listening
    public var writePath: WritePathState = .committing
    public var proxy: ProxyState = .streaming
    public var skills: SkillState = .installing
    public var mcp: MCPState = .discovering
    public var fabric: FabricState = .vector
    public var fleet: FleetState = .ingesting

    /// Seconds each state holds before the board advances.
    public var interval: TimeInterval
    public private(set) var isRunning = false
    /// Pillars the user pinned; the driver leaves these alone.
    public private(set) var pinned: Set<String> = []

    private var tick = 0
    private var task: Task<Void, Never>?

    /// Smallest allowed hold time — a nonpositive interval would turn the
    /// driver loop into a main-actor busy spin (Task.sleep(0) returns
    /// immediately and `advance()` never yields).
    private static let minimumInterval: TimeInterval = 0.1

    public init(interval: TimeInterval = 4.2) {
        self.interval = max(interval, Self.minimumInterval)
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Clamp at use too: `interval` is a settable var, so a later
                // assignment of 0 (or negative) must not revive the busy spin.
                try? await Task.sleep(for: .seconds(max(self.interval, Self.minimumInterval)))
                guard !Task.isCancelled else { return }
                self.advance()
            }
        }
    }

    public func stop() {
        task?.cancel(); task = nil; isRunning = false
    }

    public func toggle() { isRunning ? stop() : start() }

    /// Pin a pillar so it stops cycling — called when a chip is tapped.
    public func pin(_ key: String) { pinned.insert(key) }
    public func unpinAll() { pinned.removeAll() }

    public func advance() {
        tick += 1
        withAnimation(.easeInOut(duration: 0.5)) {
            if !pinned.contains("dream")      { dream = .cycled(tick) }
            if !pinned.contains("memory")     { memory = .cycled(tick + 2) }
            if !pinned.contains("perception") { perception = .cycled(tick) }
            if !pinned.contains("write")      { writePath = .cycled(tick + 1) }
            if !pinned.contains("proxy")      { proxy = .cycled(tick + 2) }
            if !pinned.contains("skills")     { skills = .cycled(tick) }
            if !pinned.contains("mcp")        { mcp = .cycled(tick + 1) }
            if !pinned.contains("fabric")     { fabric = .cycled(tick + 3) }
            if !pinned.contains("fleet")      { fleet = .cycled(tick + 2) }
        }
    }

    /// Every state across every pillar — 37 in total.
    public static var stateCount: Int {
        DreamState.allCases.count + MemoryState.allCases.count + PerceptionState.allCases.count
            + WritePathState.allCases.count + ProxyState.allCases.count + SkillState.allCases.count
            + MCPState.allCases.count + FabricState.allCases.count + FleetState.allCases.count
    }
}

// MARK: - Coupling strip

/// What the current dream state does to the memory lattice.
public struct CouplingStrip: View {
    @Environment(\.andromedaMotionActive) private var motionActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var liveMotion: Bool { motionActive && !reduceMotion }
    public var dream: DreamState
    public var memory: MemoryState
    public init(dream: DreamState, memory: MemoryState) { self.dream = dream; self.memory = memory }

    public var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !liveMotion)) { context in
            // Paused schedules still deliver the wall-clock date; pin to 0 so
            // frozen captures are deterministic (PillarScenes convention).
            let t = liveMotion ? context.date.timeIntervalSinceReferenceDate : 0
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Text("Coupling").cpTitle().foregroundStyle(Color.andromedaInk)
                    Rectangle().fill(Color.andromedaTeal.opacity(0.1)).frame(height: 1)
                    Text("dream state → what memory becomes")
                        .font(AndromedaFont.mono(9.5))
                        .foregroundStyle(Color.andromedaMuted)
                        .fixedSize()
                }
                HStack(spacing: 14) {
                    end("dreaming", dream.label, dream.accent)
                    Canvas { ctx, size in
                        var wire = Path()
                        wire.move(to: CGPoint(x: 2, y: size.height / 2))
                        wire.addLine(to: CGPoint(x: size.width - 14, y: size.height / 2))
                        ctx.stroke(wire, with: .color(dream.accent.opacity(0.7)),
                                   style: .flowing(t, speed: 22, width: 1.3))
                        var head = Path()
                        head.move(to: CGPoint(x: size.width - 18, y: size.height / 2 - 5))
                        head.addLine(to: CGPoint(x: size.width - 10, y: size.height / 2))
                        head.addLine(to: CGPoint(x: size.width - 18, y: size.height / 2 + 5))
                        ctx.stroke(head, with: .color(memory.accent),
                                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    }
                    .frame(width: 64, height: 20)
                    end("memory", memory.label, memory.accent)
                    Text(dream.coupling)
                        .cpBody()
                        .foregroundStyle(Color.andromedaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .background(Color.andromedaVoid.opacity(0.5), in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.andromedaTeal.opacity(0.08)))
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            .background(Color.andromedaPanel.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.andromedaTeal.opacity(0.1)))
        }
    }

    private func end(_ eyebrow: String, _ name: String, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(eyebrow)
            Text(name).font(AndromedaFont.mono(13)).foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(accent.opacity(0.24)))
        .animation(.easeInOut(duration: 0.5), value: accent)
    }
}

// MARK: - The board

/// All nine pillars, thirty-seven states, on one surface.
public struct PillarBoard: View {
    @Environment(\.andromedaMotionActive) private var motionActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var liveMotion: Bool { motionActive && !reduceMotion }
    @State private var driver: PillarDriver

    public init(driver: PillarDriver = PillarDriver()) {
        _driver = State(initialValue: driver)
    }

    private let wide = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]
    private let trio = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20),
                        GridItem(.flexible(), spacing: 20)]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                LazyVGrid(columns: wide, spacing: 20) {
                    PillarPanel(
                        title: "Dreaming", subtitle: "what it does while you sleep",
                        state: $driver.dream, stageHeight: 270, glow: driver.dream != .awake,
                        onPick: { driver.pin("dream") }
                    ) {
                        TimelineView(.animation(minimumInterval: nil, paused: !liveMotion)) { ctx in
                            // Paused ⇒ spin pinned to 0 (deterministic captures).
                            DreamingMark(accent: driver.dream.accent, awake: driver.dream == .awake,
                                         spin: (liveMotion ? ctx.date.timeIntervalSinceReferenceDate : 0)
                                             * (driver.dream == .lucid ? 90 : 40))
                        }
                    } scene: {
                        DreamingScene(state: driver.dream)
                    }

                    PillarPanel(
                        title: "Memory", subtitle: "six ways to be remembered",
                        state: $driver.memory, stageHeight: 270,
                        onPick: { driver.pin("memory") }
                    ) {
                        TimelineView(.animation(minimumInterval: nil, paused: !liveMotion)) { ctx in
                            // Paused ⇒ core pulse pinned to 0 (deterministic captures).
                            let t = liveMotion ? ctx.date.timeIntervalSinceReferenceDate : 0
                            MemoryMark(accent: driver.memory.accent,
                                       corePulse: driver.memory == .recalled ? 1 + 0.2 * sin(t * 3.4) : 1)
                        }
                    } scene: {
                        MemoryScene(state: driver.memory)
                    }
                }

                sectionRule

                LazyVGrid(columns: trio, spacing: 20) {
                    PillarPanel(title: "Perception", subtitle: "sense & recall",
                                state: $driver.perception, onPick: { driver.pin("perception") }) {
                        PillarMark(.perception, accent: driver.perception.accent)
                    } scene: {
                        PerceptionScene(state: driver.perception)
                    }

                    PillarPanel(title: "Write path", subtitle: "nothing enters unwitnessed",
                                state: $driver.writePath, onPick: { driver.pin("write") }) {
                        PillarMark(.writePath, accent: driver.writePath.accent)
                    } scene: {
                        WritePathScene(state: driver.writePath)
                    }

                    PillarPanel(title: "LLM proxy", subtitle: "one endpoint · many minds",
                                state: $driver.proxy, onPick: { driver.pin("proxy") }) {
                        PillarMark(.proxy, accent: driver.proxy.accent)
                    } scene: {
                        ProxyScene(state: driver.proxy)
                    }

                    PillarPanel(title: "Agent skills", subtitle: "abilities it grows into",
                                state: $driver.skills, onPick: { driver.pin("skills") }) {
                        PillarMark(.skills, accent: driver.skills.accent)
                    } scene: {
                        SkillsScene(state: driver.skills)
                    }

                    PillarPanel(title: "MCP", subtitle: "tools it is allowed to touch",
                                state: $driver.mcp, onPick: { driver.pin("mcp") }) {
                        PillarMark(.mcp, accent: driver.mcp.accent)
                    } scene: {
                        MCPScene(state: driver.mcp)
                    }

                    PillarPanel(title: "Memory fabric", subtitle: "one verb, the right store",
                                state: $driver.fabric, onPick: { driver.pin("fabric") }) {
                        PillarMark(.fabric, accent: driver.fabric.accent)
                    } scene: {
                        FabricScene(state: driver.fabric)
                    }
                }

                PillarPanel(title: "Fleet signals", subtitle: "milestones and honest failures",
                            state: $driver.fleet, stageHeight: 158,
                            onPick: { driver.pin("fleet") }) {
                    PillarMark(.fleet, accent: driver.fleet.accent)
                } scene: {
                    FleetScene(state: driver.fleet)
                }

                CouplingStrip(dream: driver.dream, memory: driver.memory)
            }
            .padding(.horizontal, 48)
            .padding(.top, 44)
            .padding(.bottom, 60)
        }
        .background(AndromedaSurface().ignoresSafeArea())
        .onAppear { driver.start() }
        .onDisappear { driver.stop() }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 30) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Andromida · state studies · 📐 design surface")
                Text("Nine pillars, thirty-seven states")
                    .font(AndromedaFont.serif(46))
                    .foregroundStyle(Color.andromedaInk)
                Text("Design studies for the control plane Andromida is becoming — each state is vocabulary for a mode we intend, not a claim it ships today. Ship-state per pillar is tracked honestly (🚧 partial · 📐 specified) in the control-plane docs.")
                    .cpBody()
                    .foregroundStyle(Color.andromedaMuted)
                    .frame(maxWidth: 660, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            HStack(spacing: 9) {
                Button { driver.toggle() } label: {
                    Label(driver.isRunning ? "auto" : "paused",
                          systemImage: driver.isRunning ? "pause.fill" : "play.fill")
                        .font(AndromedaFont.mono(9))
                        .textCase(.uppercase)
                        .foregroundStyle(driver.isRunning ? Color.andromedaInk : Color.andromedaMuted)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(driver.isRunning ? Color.andromedaTeal.opacity(0.13)
                                                     : Color.andromedaTeal.opacity(0.03),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.andromedaTeal.opacity(driver.isRunning ? 0.4 : 0.12)))
                }
                .buttonStyle(.plain)

                Text("\(PillarDriver.stateCount) states")
                    .font(AndromedaFont.mono(9)).textCase(.uppercase)
                    .foregroundStyle(Color.andromedaMuted)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.andromedaTeal.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.andromedaTeal.opacity(0.14)))
            }
        }
    }

    private var sectionRule: some View {
        HStack(spacing: 14) {
            Text("The other seven")
                .font(AndromedaFont.serif(26))
                .foregroundStyle(Color.andromedaInk)
            Rectangle().fill(Color.andromedaTeal.opacity(0.1)).frame(height: 1)
            Text("perception · durability · inference · capability · connectors · backends · health")
                .font(AndromedaFont.mono(9.5))
                .foregroundStyle(Color.andromedaMuted)
                .fixedSize()
        }
        .padding(.top, 10)
    }
}

// MARK: - Catalogue

public extension AndromedaCatalogue {
    /// The pillar scenes, registered for the gallery and snapshot sweep.
    @MainActor static var pillarSpecimens: [AndromedaSpecimen] {
        [
            .init("Dreaming · REM", DreamingScene(state: .rem)),
            .init("Dreaming · deep", DreamingScene(state: .deep)),
            .init("Memory · recalled", MemoryScene(state: .recalled)),
            .init("Memory · conflicted", MemoryScene(state: .conflicted)),
            .init("Perception · listening", PerceptionScene(state: .listening)),
            .init("WritePath · committing", WritePathScene(state: .committing)),
            .init("Proxy · routing", ProxyScene(state: .routing)),
            .init("Skills · invoking", SkillsScene(state: .invoking)),
            .init("MCP · tool call", MCPScene(state: .toolcall)),
            .init("Fabric · memory.vector", FabricScene(state: .vector)),
            .init("Fleet · milestone", FleetScene(state: .milestone)),
            .init("EEGMontage", EEGMontage(lead: .rem, accent: .andromedaDream, time: 0)),
            .init("NumericTicker", NumericTicker(37_612, glow: .andromedaGlow)),
            .init("ThinkingDots", ThinkingDots()),
            .init("SparkBurst", SparkBurst(color: .andromedaGlow, time: 0.6)),
        ]
    }
}

// MARK: - Previews

#Preview("Pillar board") {
    PillarBoard().frame(minWidth: 1300, minHeight: 1100)
}

#Preview("Dreaming · every state") {
    VStack(spacing: 12) {
        ForEach(DreamState.allCases) { state in
            PillarStage(accent: state.accent, height: 270, glow: state != .awake) {
                DreamingScene(state: state)
            }
        }
    }
    .padding(20)
    .frame(width: 620)
    .background(AndromedaSurface())
}

#Preview("Memory · every state") {
    VStack(spacing: 12) {
        ForEach(MemoryState.allCases) { state in
            PillarStage(accent: state.accent, height: 270) { MemoryScene(state: state) }
        }
    }
    .padding(20)
    .frame(width: 620)
    .background(AndromedaSurface())
}

#Preview("Seven pillars") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(PerceptionState.allCases) { s in
                PillarStage(accent: s.accent) { PerceptionScene(state: s) }
            }
            ForEach(WritePathState.allCases) { s in
                PillarStage(accent: s.accent) { WritePathScene(state: s) }
            }
            ForEach(ProxyState.allCases) { s in
                PillarStage(accent: s.accent) { ProxyScene(state: s) }
            }
            ForEach(SkillState.allCases) { s in
                PillarStage(accent: s.accent) { SkillsScene(state: s) }
            }
            ForEach(MCPState.allCases) { s in
                PillarStage(accent: s.accent) { MCPScene(state: s) }
            }
            ForEach(FabricState.allCases) { s in
                PillarStage(accent: s.accent) { FabricScene(state: s) }
            }
            ForEach(FleetState.allCases) { s in
                PillarStage(accent: s.accent) { FleetScene(state: s) }
            }
        }
        .padding(20)
    }
    .frame(width: 520, height: 900)
    .background(AndromedaSurface())
}
