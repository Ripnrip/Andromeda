import SwiftUI

// MARK: - Perception

public struct PerceptionScene: View {
    public var state: PerceptionState
    public init(state: PerceptionState) { self.state = state }

    public var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .top) {
                PillarLog(state.log, tint: state.accent)
                    .padding(.horizontal, 14).padding(.top, 12)

                Group {
                    switch state {
                    case .listening:
                        HStack(spacing: 4) {
                            ForEach(0..<11, id: \.self) { i in
                                let period = 0.62 + Double((i * 37) % 9) * 0.07
                                let v = 0.18 + 0.82 * (0.5 + 0.5 * sin((t + Double(i) * 0.06) / period * .pi * 2))
                                Capsule().fill(state.accent)
                                    .frame(width: 3, height: 44 * v)
                                    .shadow(color: state.accent.opacity(0.5), radius: 4)
                            }
                        }
                    case .recalling:
                        ZStack {
                            Circle().fill(state.accent)
                                .frame(width: 11, height: 11)
                                .shadow(color: state.accent, radius: 8)
                                .scaleEffect(1 + 0.2 * sin(t * 2.8))
                            ForEach(0..<4, id: \.self) { i in
                                Circle().fill(state.accent)
                                    .frame(width: 6, height: 6)
                                    .offset(y: -(24 + CGFloat(i) * 11))
                                    .rotationEffect(.degrees(t / (3.2 + Double(i) * 1.1) * 360))
                            }
                        }
                    case .whisper:
                        FlowingWords(words: ["you", "argued", "the", "opposite", "on", "Tuesday"],
                                     accent: state.accent, time: t)
                    case .focus:
                        HStack(spacing: 6) {
                            ForEach(0..<4, id: \.self) { i in
                                Text("queued")
                                    .font(AndromedaFont.mono(11.5))
                                    .foregroundStyle(Color.andromedaMuted)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .overlay(RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.andromedaTeal.opacity(0.12)))
                                    .opacity(0.35 + 0.25 * sin((t + Double(i) * 0.5) * 1.6))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 22)
            }
        }
    }
}

/// Words arriving one at a time — a whisper assembling itself.
struct FlowingWords: View {
    var words: [String]
    var accent: Color
    var time: TimeInterval

    var body: some View {
        let cycle = (time / 3.2).truncatingRemainder(dividingBy: 1)
        HStack(spacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                let due = Double(i) / Double(words.count) * 0.7
                let shown = cycle > due
                Text(word)
                    .font(AndromedaFont.mono(11.5))
                    .foregroundStyle(Color.andromedaInk)
                    .shadow(color: accent.opacity(0.6), radius: 6)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 7)
            }
        }
        .animation(.easeOut(duration: 0.3), value: cycle > 0.5)
    }
}

// MARK: - Write path

public struct WritePathScene: View {
    public var state: WritePathState
    public init(state: WritePathState) { self.state = state }

    public var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            VStack(alignment: .leading, spacing: 0) {
                PillarLog(state.log, tint: state.accent, typing: state == .writing || state == .committing)

                HStack(spacing: 0) {
                    ForEach(Array(WritePathState.rail.enumerated()), id: \.offset) { i, name in
                        let done = i < state.stage
                        let here = i == state.stage
                        VStack(spacing: 5) {
                            Circle()
                                .fill(done || here ? state.accent : Color.andromedaDim.opacity(0.5))
                                .frame(width: here ? 12 : 8, height: here ? 12 : 8)
                                .shadow(color: here ? state.accent : .clear, radius: 7)
                                .scaleEffect(here ? 1 + 0.12 * sin(t * 3.4) : 1)
                            Text(name)
                                .font(AndromedaFont.mono(8.5))
                                .foregroundStyle(done || here ? Color.andromedaInk : Color.andromedaDim)
                        }
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .top) {
                            if i < WritePathState.rail.count - 1 {
                                Rectangle()
                                    .fill(done ? state.accent : Color.andromedaTeal.opacity(0.12))
                                    .frame(height: 1.5)
                                    .padding(.leading, 60)
                                    .offset(y: 5)
                            }
                        }
                    }
                }
                .padding(.top, 18)
                .animation(.easeInOut(duration: 0.45), value: state)

                Spacer(minLength: 6)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(lines(t).enumerated()), id: \.offset) { _, line in
                        Text(line.0)
                            .font(AndromedaFont.mono(8.5))
                            .foregroundStyle(line.1)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
    }

    private func lines(_ t: TimeInterval) -> [(String, Color)] {
        switch state {
        case .capturing:
            let secs = Int(t.truncatingRemainder(dividingBy: 600))
            let clock = String(format: "%02d:%02d", secs / 60, secs % 60)
            return [("● rec  \(clock)", Color.andromedaAlert),
                    ("buffer  4.1 MB  local only", .andromedaMuted),
                    ("— not yet a trace —", .andromedaDim)]
        case .writing:
            return [("0x41f4  DRAFT   trace/site-split", .andromedaMuted),
                    ("        type    episodic", .andromedaMuted),
                    ("        witness you · 09:41", .andromedaMuted)]
        case .committing:
            return [("0x41f4  APPEND  outbox         ok", .andromedaGlow),
                    ("0x41f5  FSYNC   3 traces sealed  ok", .andromedaGlow),
                    ("outbox depth  3", .andromedaMuted)]
        case .syncing:
            let queued = max(0, 7 - Int(t * 1.2).quotientAndRemainder(dividingBy: 9).remainder)
            return [("→ qdrant     ok", .andromedaLive),
                    ("→ graphiti   ok", .andromedaLive),
                    ("queued  \(queued)", .andromedaMuted)]
        }
    }
}

// MARK: - LLM proxy

public struct ProxyScene: View {
    public var state: ProxyState
    public init(state: ProxyState) { self.state = state }

    public var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .top) {
                PillarLog(state.log, tint: state.accent)
                    .padding(.horizontal, 14).padding(.top, 12)

                switch state {
                case .tokens:
                    VStack(spacing: 3) {
                        NumericTicker(counter(t), size: 32, glow: state.accent)
                        Eyebrow("tokens this session")
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.top, 14)

                case .streaming:
                    VStack(spacing: 0) {
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(0..<10, id: \.self) { i in
                                let p = ((t * 2.4) - Double(i) * 0.4).truncatingRemainder(dividingBy: 6)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(state.accent.opacity(0.85))
                                    .frame(width: CGFloat(9 + (i * 17) % 18), height: 7)
                                    .scaleEffect(p > 0 && p < 0.34 ? 1.25 : 1, anchor: .bottom)
                            }
                        }
                        .padding(.bottom, 14)
                    }

                default:
                    ProxyRouting(state: state, time: t)
                        .padding(.top, 30)
                }
            }
        }
    }

    /// Steps in visible increments so the digits roll rather than blur.
    private func counter(_ t: TimeInterval) -> Int {
        1240 + (Int(t * 6) % 1500) * 7
    }
}

struct ProxyRouting: View {
    var state: ProxyState
    var time: TimeInterval

    var body: some View {
        GeometryReader { geo in
            let rows = ProxyState.models.count
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    for i in 0..<rows {
                        let y = h * (CGFloat(i) + 0.5) / CGFloat(rows)
                        var path = Path()
                        path.move(to: CGPoint(x: 10, y: h / 2))
                        path.addCurve(to: CGPoint(x: size.width - 96, y: y),
                                      control1: CGPoint(x: size.width * 0.4, y: h / 2),
                                      control2: CGPoint(x: size.width * 0.45, y: y))
                        let live = state.activeModel == i
                        ctx.stroke(
                            path,
                            with: .color(live ? state.accent : Color.andromedaTeal.opacity(0.16)),
                            style: StrokeStyle(lineWidth: live ? 1.8 : 1, lineCap: .round,
                                               dash: [8, 10],
                                               dashPhase: live ? -time * (state == .routing ? 46 : 26) : 0)
                        )
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(ProxyState.models.enumerated()), id: \.offset) { i, name in
                        let live = state.activeModel == i
                        let dropped = state == .routing && i == 0
                        Text(name)
                            .font(AndromedaFont.mono(9))
                            .strikethrough(dropped)
                            .foregroundStyle(live ? Color.andromedaInk : Color.andromedaMuted)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background((live ? state.accent.opacity(0.15) : Color.andromedaTeal.opacity(0.03)),
                                        in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                if live {
                                    Color.clear.marchingBorder(state.accent, radius: 6, period: 1.1)
                                } else {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.andromedaTeal.opacity(0.10))
                                }
                            }
                            .opacity(dropped ? 0.5 : 1)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 88)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.5), value: state)
    }
}

// MARK: - Agent skills

public struct SkillsScene: View {
    public var state: SkillState
    public init(state: SkillState) { self.state = state }

    public var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                VStack(alignment: .leading, spacing: 0) {
                    PillarLog(state.log, tint: state.accent)
                    VStack(spacing: 6) {
                        ForEach(Array(SkillState.skills.enumerated()), id: \.offset) { i, name in
                            let live = state.activeSkill == i
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(live ? state.accent : (state == .ready ? Color.andromedaLive : Color.andromedaMuted))
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(live ? 1 + 0.25 * sin(t * 3.8) : 1)
                                Text(name)
                                    .font(AndromedaFont.mono(10))
                                    .foregroundStyle(Color.andromedaInk)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                if live && state == .invoking {
                                    ThinkingDots(color: state.accent, dotSize: 4)
                                }
                                Text(state.tag(i))
                                    .font(AndromedaFont.mono(8.5))
                                    .foregroundStyle(live ? state.accent : Color.andromedaMuted)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background((live ? state.accent.opacity(0.09) : Color.andromedaTeal.opacity(0.02)),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(live ? state.accent.opacity(0.35) : Color.andromedaTeal.opacity(0.08)))
                        }
                    }
                    .padding(.top, 12)
                    .opacity(state == .ready ? 0.28 : 1)

                    Spacer(minLength: 4)

                    if state == .installing {
                        GeometryReader { geo in
                            let p = (t / 3.4).truncatingRemainder(dividingBy: 1)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.andromedaTeal.opacity(0.09))
                                Capsule().fill(state.accent)
                                    .frame(width: geo.size.width * (0.14 + 0.85 * p))
                                    .shadow(color: state.accent.opacity(0.7), radius: 6)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)

                if state == .ready {
                    ForEach(0..<3, id: \.self) { i in
                        let p = ((t + Double(i) * 0.8) / 2.4).truncatingRemainder(dividingBy: 1)
                        Circle().stroke(state.accent, lineWidth: 1.5)
                            .frame(width: 34, height: 34)
                            .scaleEffect(0.4 + 2.8 * p)
                            .opacity(0.9 * (1 - p))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.5), value: state)
        }
    }
}

// MARK: - MCP

public struct MCPScene: View {
    public var state: MCPState
    public init(state: MCPState) { self.state = state }

    public var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .top) {
                PillarLog(state.log, tint: state.accent, typing: state == .toolcall)
                    .padding(.horizontal, 14).padding(.top, 12)

                GeometryReader { geo in
                    let hub = CGPoint(x: geo.size.width * 0.36, y: geo.size.height * 0.56)
                    let radius = min(geo.size.width, geo.size.height) * 0.42

                    ZStack {
                        Circle()
                            .fill(state.accent)
                            .frame(width: 14, height: 14)
                            .shadow(color: state.accent, radius: 10)
                            .opacity(state == .connecting ? 0.35 + 0.6 * (0.5 + 0.5 * sin(t * 4.6)) : 1)
                            .scaleEffect(state == .connecting ? 1 : 1 + 0.12 * sin(t * 2.6))
                            .position(hub)

                        ForEach(Array(MCPState.tools.enumerated()), id: \.offset) { i, tool in
                            let live = state != .connecting && tool.allowed
                            let angle = Angle.degrees(tool.angle)
                            Text(tool.name)
                                .font(AndromedaFont.mono(9))
                                .foregroundStyle(live ? Color.andromedaInk : Color.andromedaDim)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background((live ? state.accent.opacity(0.13) : Color.andromedaTeal.opacity(0.03)),
                                            in: RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    if state == .toolcall && i == 0 {
                                        Color.clear.marchingBorder(state.accent, radius: 6, period: 1.0)
                                    } else {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(live ? state.accent.opacity(0.5) : Color.andromedaTeal.opacity(0.16),
                                                    style: StrokeStyle(lineWidth: 1, dash: live ? [] : [3, 3]))
                                    }
                                }
                                .shadow(color: state == .toolcall && i == 0 ? state.accent.opacity(0.6) : .clear, radius: 10)
                                .opacity(state == .connecting ? 0.4 : 1)
                                .scaleEffect(state == .discovering ? popScale(t, delay: Double(i) * 0.12) : 1)
                                .position(x: hub.x + radius * CGFloat(cos(angle.radians)),
                                          y: hub.y + radius * CGFloat(sin(angle.radians)) * 0.86)
                        }

                        if state == .toolcall {
                            let p = (t / 1.5).truncatingRemainder(dividingBy: 1)
                            let angle = Angle.degrees(MCPState.tools[0].angle)
                            Circle().fill(state.accent)
                                .frame(width: 7, height: 7)
                                .shadow(color: state.accent, radius: 7)
                                .position(x: hub.x + radius * CGFloat(cos(angle.radians)) * CGFloat(p),
                                          y: hub.y + radius * CGFloat(sin(angle.radians)) * 0.86 * CGFloat(p))
                                .opacity(p < 0.1 || p > 0.9 ? 0 : 1)
                        }
                    }
                }
                .padding(.top, 28)
                .padding(.bottom, 10)
                .animation(.easeInOut(duration: 0.5), value: state)
            }
        }
    }

    private func popScale(_ t: TimeInterval, delay: Double) -> CGFloat {
        let p = ((t - delay) / 3.2).truncatingRemainder(dividingBy: 1)
        guard p > 0, p < 0.3 else { return 1 }
        return 1 + 0.2 * CGFloat(sin(p / 0.3 * .pi))
    }
}

// MARK: - Memory fabric

public struct FabricScene: View {
    public var state: FabricState
    public init(state: FabricState) { self.state = state }

    public var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .top) {
                PillarLog(state.log, tint: state.accent)
                    .padding(.horizontal, 14).padding(.top, 12)

                Group {
                    switch state {
                    case .qdrant:
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10),
                                  spacing: 6) {
                            ForEach(0..<30, id: \.self) { i in
                                let period = 1.6 + Double((i * 13) % 7) * 0.22
                                let phase = Double((i * 7) % 11) * 0.14
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(state.accent)
                                    .frame(height: 9)
                                    .opacity(0.14 + 0.86 * (0.5 + 0.5 * sin((t + phase) / period * .pi * 2)))
                            }
                        }
                        .padding(.horizontal, 16)

                    case .procedural:
                        HStack(spacing: 6) {
                            ForEach(1...6, id: \.self) { n in
                                let done = n < 3, here = n == 3
                                Text("\(n)")
                                    .font(AndromedaFont.mono(10))
                                    .foregroundStyle(here ? Color.andromedaInk
                                                     : (done ? state.accent : Color.andromedaDim))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 26)
                                    .background((here ? state.accent.opacity(0.2)
                                                 : (done ? state.accent.opacity(0.11) : Color.andromedaTeal.opacity(0.02))),
                                                in: RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7)
                                        .stroke(here ? state.accent : (done ? state.accent.opacity(0.3)
                                                                       : Color.andromedaTeal.opacity(0.10))))
                                    .scaleEffect(here ? 1 + 0.04 * sin(t * 3.2) : 1)
                            }
                        }
                        .padding(.horizontal, 16)

                    case .graphiti:
                        Circle()
                            .trim(from: 0, to: 0.62)
                            .stroke(state.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 74, height: 74)
                            .rotationEffect(.degrees(t * 52))
                            .scaleEffect(1 - 0.06 * abs(sin(t * 0.9)))
                            .shadow(color: state.accent.opacity(0.4), radius: 12)

                    case .web:
                        Circle()
                            .stroke(state.accent.opacity(0.75),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
                            .frame(width: 74, height: 74)
                            .rotationEffect(.degrees(t * 24))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 26)
                .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Fleet signals

public struct FleetScene: View {
    public var state: FleetState
    public init(state: FleetState) { self.state = state }

    public var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .top) {
                PillarLog(state.log, tint: state.accent)
                    .padding(.horizontal, 16).padding(.top, 12)

                Group {
                    switch state {
                    case .milestone:
                        ZStack {
                            ForEach(0..<3, id: \.self) { i in
                                let p = ((t + Double(i) * 0.85) / 2.6).truncatingRemainder(dividingBy: 1)
                                Circle().stroke(state.accent, lineWidth: 1.5)
                                    .frame(width: 66, height: 66)
                                    .scaleEffect(0.5 + 2.4 * p)
                                    .opacity(0.8 * (1 - p))
                            }
                            SparkBurst(color: state.accent, time: t)
                            NumericTicker(37_600 + (Int(t * 3) % 400), size: 40, glow: state.accent)
                        }

                    case .ingesting:
                        HStack(spacing: 12) {
                            ForEach(Array(FleetState.intake.enumerated()), id: \.offset) { i, file in
                                let live = i == 0
                                let p = live ? 0.12 + 0.86 * ((t / 6).truncatingRemainder(dividingBy: 1)) : file.progress
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(file.name)
                                        .font(AndromedaFont.mono(9.5))
                                        .foregroundStyle(live ? Color.andromedaInk : Color.andromedaMuted)
                                        .lineLimit(1)
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.andromedaTeal.opacity(0.1))
                                            Capsule()
                                                .fill(file.progress == 1 ? Color.andromedaLive : state.accent)
                                                .frame(width: geo.size.width * p)
                                                .opacity(live ? 1 : 0.5)
                                        }
                                    }
                                    .frame(height: 3)
                                    .padding(.vertical, 7)
                                    .shimmer(state.accent.opacity(live ? 0.5 : 0), period: 1.6)
                                    Text(file.meta)
                                        .font(AndromedaFont.mono(8.5))
                                        .foregroundStyle(Color.andromedaDim)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background((live ? state.accent.opacity(0.08) : Color.andromedaTeal.opacity(0.02)),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(live ? state.accent.opacity(0.3) : Color.andromedaTeal.opacity(0.08)))
                            }
                        }

                    case .reindexing:
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 24),
                                  spacing: 5) {
                            ForEach(0..<48, id: \.self) { i in
                                let period = 1.5 + Double((i * 11) % 8) * 0.19
                                let phase = Double((i * 5) % 13) * 0.11
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(state.accent)
                                    .frame(height: 16)
                                    .opacity(0.14 + 0.86 * (0.5 + 0.5 * sin((t + phase) / period * .pi * 2)))
                            }
                        }

                    case .degraded, .handoff:
                        HStack(spacing: 26) {
                            ForEach(Array(nodes.enumerated()), id: \.offset) { i, name in
                                let down = state == .degraded && i == 0
                                Text(name)
                                    .font(AndromedaFont.mono(name == "→" ? 15 : 10.5))
                                    .foregroundStyle(down ? state.accent
                                                     : (state == .handoff ? Color.andromedaInk : Color.andromedaMuted))
                                    .padding(.horizontal, name == "→" ? 0 : 14)
                                    .padding(.vertical, name == "→" ? 0 : 7)
                                    .background {
                                        if name != "→" {
                                            RoundedRectangle(cornerRadius: 9)
                                                .fill(down ? state.accent.opacity(0.12)
                                                      : (state == .handoff ? state.accent.opacity(0.11)
                                                         : Color.andromedaLive.opacity(0.09)))
                                        }
                                    }
                                    .overlay {
                                        if name != "→" {
                                            RoundedRectangle(cornerRadius: 9)
                                                .stroke(down ? state.accent.opacity(0.5)
                                                        : (state == .handoff ? state.accent.opacity(0.35)
                                                           : Color.andromedaLive.opacity(0.28)))
                                        }
                                    }
                                    .opacity(down ? 0.35 + 0.6 * (0.5 + 0.5 * sin(t * 2.8)) : 1)
                                    .scaleEffect(name == "→" ? 1 + 0.12 * sin(t * 3.4) : 1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 26)
                .padding(.bottom, 14)

                if state == .reindexing {
                    VStack {
                        Spacer()
                        GeometryReader { geo in
                            let p = (t / 1.8).truncatingRemainder(dividingBy: 1)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.andromedaTeal.opacity(0.09))
                                LinearGradient(colors: [.clear, state.accent, .clear],
                                               startPoint: .leading, endPoint: .trailing)
                                    .frame(width: geo.size.width * 0.34)
                                    .offset(x: -geo.size.width * 0.34 + geo.size.width * 1.34 * p)
                                    .clipShape(Capsule())
                            }
                        }
                        .frame(height: 5)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                    }
                }
            }
        }
    }

    private var nodes: [String] {
        state == .handoff ? ["capture agent", "→", "dream agent"] : FleetState.backends
    }
}
