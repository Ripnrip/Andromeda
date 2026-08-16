import SwiftUI

// MARK: - Memory lattice
// Edges are drawn in a single Canvas beneath the nodes; nodes are real views
// so they stay hit-testable and accessible.

public struct TraceLattice: View {
    public var state: MemoryState
    public var time: TimeInterval

    public init(state: MemoryState, time: TimeInterval) { self.state = state; self.time = time }

    public var body: some View {
        GeometryReader { geo in
            let scale = CGSize(width: geo.size.width / TraceNode.design.width,
                               height: geo.size.height / TraceNode.design.height)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for (i, edge) in TraceNode.edges.enumerated() {
                        let a = TraceNode.all[edge.0], b = TraceNode.all[edge.1]
                        let mood = state.edgeMood(i)
                        var path = Path()
                        path.move(to: place(a.point, scale))
                        path.addLine(to: place(b.point, scale))

                        var style = StrokeStyle(lineWidth: 1, lineCap: .round)
                        var tint = Color.andromedaTeal.opacity(0.16)

                        switch mood {
                        case .linking:
                            tint = .andromedaDream
                            style = StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                                dash: [240], dashPhase: drawPhase(delay: Double(i) * 0.22))
                        case .onPath:
                            tint = .andromedaLive
                            style = StrokeStyle(lineWidth: 1.8, lineCap: .round,
                                                dash: [6, 8], dashPhase: -time * 26)
                        case .clashing:
                            tint = Color.andromedaAlert.opacity(0.35 + 0.6 * pulse(1.2))
                            style = StrokeStyle(lineWidth: 1.8, lineCap: .round)
                        case .fading:
                            tint = Color.andromedaTeal.opacity(0.06)
                            style = StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 5])
                        default:
                            break
                        }
                        ctx.stroke(path, with: .color(tint), style: style)
                    }
                }

                ForEach(TraceNode.all) { node in
                    TraceNodeView(node: node, mood: state.mood(for: node), time: time)
                        .position(place(node.point, scale))
                }
            }
        }
    }

    private func place(_ p: CGPoint, _ s: CGSize) -> CGPoint {
        CGPoint(x: p.x * s.width, y: p.y * s.height)
    }
    private func pulse(_ period: Double) -> Double {
        0.5 + 0.5 * sin(time / period * .pi * 2)
    }
    /// Edges "draw" by animating dash phase from full offset to zero.
    private func drawPhase(delay: Double) -> CGFloat {
        let p = ((time - delay) / 2.6).truncatingRemainder(dividingBy: 1)
        return CGFloat(240 * (1 - max(0, min(1, p * 1.6))))
    }
}

public struct TraceNodeView: View {
    public var node: TraceNode
    public var mood: TraceNodeMood
    public var time: TimeInterval

    public init(node: TraceNode, mood: TraceNodeMood, time: TimeInterval) {
        self.node = node; self.mood = mood; self.time = time
    }

    private var tint: Color {
        switch mood {
        case .clashing:      .andromedaAlert
        case .hit, .onPath:  .andromedaLive
        default:             node.kind.tint
        }
    }
    private var lit: Bool {
        switch mood { case .hit, .onPath, .clashing, .fresh: true; default: false }
    }

    public var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if mood == .hit {
                    let p = (time / 1.8).truncatingRemainder(dividingBy: 1)
                    TraceGlyph(node.kind)
                        .stroke(Color.andromedaLive, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                        .scaleEffect(0.4 + 2.8 * p)
                        .opacity(0.9 * (1 - p))
                }
                TraceGlyph(node.kind)
                    .fill(tint.opacity(lit ? 0.24 : 0.12))
                    .frame(width: 22, height: 22)
                    .overlay(
                        TraceGlyph(node.kind)
                            .stroke(tint.opacity(lit ? 0.9 : 0.35),
                                    style: StrokeStyle(lineWidth: 1.5,
                                                       dash: mood == .fresh ? [3, 3] : []))
                    )
                    .shadow(color: lit ? tint.opacity(0.5) : .clear, radius: 8)
                    .scaleEffect(breath)
            }
            Text(node.name)
                .font(AndromedaFont.mono(8))
                .foregroundStyle(lit ? Color.andromedaInk : Color.andromedaDim)
                .fixedSize()
        }
        .opacity(mood == .fading ? 0.3 : 1)
        .animation(.easeInOut(duration: 0.6), value: mood)
        .accessibilityLabel("\(node.name), \(node.kind.label)")
    }

    private var breath: CGFloat {
        switch mood {
        case .fresh:   1 + 0.12 * CGFloat(sin(time * 3.1))
        case .linking: 1 + 0.06 * CGFloat(sin(time * 2.8))
        default:       1
        }
    }
}

/// Per-kind salience, the memory's own sense of what matters.
public struct SalienceMeters: View {
    public var state: MemoryState
    public init(state: MemoryState) { self.state = state }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow("salience")
            ForEach(Array(TraceKind.allCases.enumerated()), id: \.element.id) { i, kind in
                let shift = state.salienceShift * (i % 2 == 0 ? 1 : 0.5)
                let value = max(0.05, min(1, kind.baseline + shift))
                HStack(spacing: 6) {
                    TraceGlyph(kind)
                        .fill(kind.tint.opacity(0.25))
                        .overlay(TraceGlyph(kind).stroke(kind.tint.opacity(0.6), lineWidth: 1))
                        .frame(width: 7, height: 7)
                    Text(kind.label)
                        .font(AndromedaFont.mono(8.5))
                        .foregroundStyle(Color.andromedaMuted)
                        .frame(width: 52, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.andromedaTeal.opacity(0.09))
                            Capsule().fill(kind.tint.opacity(0.85))
                                .frame(width: geo.size.width * value)
                        }
                    }
                    .frame(height: 3)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(kind.label) salience \(Int(value * 100)) percent")
            }
        }
        .animation(.easeInOut(duration: 0.8), value: state)
    }
}

/// The full Memory stage.
public struct MemoryScene: View {
    public var state: MemoryState
    public init(state: MemoryState) { self.state = state }

    public var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            VStack(alignment: .leading, spacing: 10) {
                PillarLog(state.log, tint: state.accent)
                HStack(alignment: .top, spacing: 14) {
                    TraceLattice(state: state, time: t)
                        .frame(maxWidth: .infinity)
                    SalienceMeters(state: state)
                        .frame(width: 120)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
    }
}
