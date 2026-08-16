import SwiftUI

// MARK: - Transition & ambient set
// State swaps, text motion, and background texture. Discrete swaps
// auto-cycle with an autoreversing loop so a preview or a snapshot shows
// the effect without a driver; freeze with `.andromedaFrozen()`.

// MARK: Cross Fade

/// The default swap — old fades out, new fades in, no movement.
public struct CrossFade: View {
    public var a: String
    public var b: String
    @State private var flipped = false
    public init(_ a: String = "resolving", _ b: String = "routed") { self.a = a; self.b = b }
    public var body: some View {
        ZStack {
            label(a, .andromedaMuted).opacity(flipped ? 0 : 1)
            label(b, .andromedaLive).opacity(flipped ? 1 : 0)
        }
        .andromedaLoop(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(0.8), value: flipped)
        .onAppear { flipped = true }
    }
    private func label(_ s: String, _ c: Color) -> some View {
        Text(s).font(.system(size: 15, design: .monospaced)).foregroundStyle(c)
    }
}

// MARK: Slide Swap

/// Sequential content — the outgoing value leaves, the incoming arrives.
public struct SlideSwap: View {
    public var values: [String]
    @State private var shifted = false
    /// Capability IDs by default — provider brands stay behind the curtain.
    public init(values: [String] = ["infer.deep", "infer.fast"]) { self.values = values }
    public var body: some View {
        // Empty input renders a quiet placeholder instead of trapping on
        // `values[0]` — a library client passing [] gets a blank chip.
        let slots = values.isEmpty ? ["", ""] : values
        return ZStack {
            chip(slots[0]).offset(y: shifted ? -26 : 0).opacity(shifted ? 0 : 1)
            chip(slots.count > 1 ? slots[1] : slots[0]).offset(y: shifted ? 0 : 26).opacity(shifted ? 1 : 0)
        }
        .frame(width: 140, height: 34)
        .clipped()
        .andromedaLoop(.spring(duration: 0.6, bounce: 0.28).repeatForever(autoreverses: true).delay(0.9), value: shifted)
        .onAppear { shifted = true }
    }
    private func chip(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(Color.andromedaGlow)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Color.andromedaTeal.opacity(0.13)))
    }
}

// MARK: Scale Pop

/// Arrival with weight — spring in from small, settle past 1.0.
public struct ScalePop: View {
    public var symbol: String
    @State private var shown = false
    public init(symbol: String = "sparkles") { self.symbol = symbol }
    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 30))
            .foregroundStyle(Color.andromedaGlow)
            .scaleEffect(shown ? 1 : 0.2)
            .opacity(shown ? 1 : 0)
            .andromedaLoop(.spring(duration: 0.7, bounce: 0.55).repeatForever(autoreverses: true).delay(0.7), value: shown)
            .onAppear { shown = true }
    }
}

// MARK: Matched Geometry

/// One element moving between two containers — identity preserved.
public struct MatchedGeometrySwap: View {
    @Namespace private var ns
    @State private var moved = false
    public init() {}
    public var body: some View {
        HStack(spacing: 22) {
            slot(showing: !moved)
            slot(showing: moved)
        }
        .andromedaLoop(.spring(duration: 0.65, bounce: 0.35).repeatForever(autoreverses: true).delay(0.9), value: moved)
        .onAppear { moved = true }
    }
    private func slot(showing: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.andromedaTeal.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(width: 54, height: 54)
            .overlay {
                if showing {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.andromedaTeal)
                        .frame(width: 38, height: 38)
                        .shadow(color: .andromedaTeal.opacity(0.7), radius: 10)
                        .matchedGeometryEffect(id: "token", in: ns)
                }
            }
    }
}

// MARK: Phase Cycle

/// `PhaseAnimator` — a multi-step loop that a single boolean can't express.
public struct PhaseCycle: View {
    public init() {}
    public var body: some View {
        PhaseAnimator([0, 1, 2]) { phase in
            RoundedRectangle(cornerRadius: phase == 1 ? 26 : 10)
                .fill(phase == 2 ? Color.andromedaLive : Color.andromedaTeal)
                .frame(width: 52, height: 52)
                .scaleEffect(phase == 1 ? 1.16 : 0.9)
                .rotationEffect(.degrees(Double(phase) * 45))
                .shadow(color: (phase == 2 ? Color.andromedaLive : Color.andromedaTeal).opacity(0.6), radius: 12)
        } animation: { _ in .easeInOut(duration: 0.9) }
        .accessibilityHidden(true)
    }
}

// MARK: Expand / Collapse

/// A disclosure that grows the surface rather than swapping screens.
public struct ExpandCollapse: View {
    @State private var open = false
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                Text("outbox").font(.system(size: 12, design: .monospaced))
            }
            .foregroundStyle(Color.andromedaGlow)
            if open {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(["append 0x4f", "flush 12", "ack"], id: \.self) { row in
                        Text(row).font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.andromedaMuted)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .frame(width: 128, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.andromedaTeal.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.andromedaTeal.opacity(0.2)))
        )
        .andromedaLoop(.spring(duration: 0.5, bounce: 0.24).repeatForever(autoreverses: true).delay(1.1), value: open)
        .onAppear { open = true }
    }
}

// MARK: Blur Fade

/// Content resolving into focus — the way recalled memory arrives.
public struct BlurFade: View {
    public var text: String
    @State private var focused = false
    public init(_ text: String = "recalled") { self.text = text }
    public var body: some View {
        Text(text)
            .font(.system(size: 19, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.andromedaGlow)
            .blur(radius: focused ? 0 : 7)
            .opacity(focused ? 1 : 0.25)
            .scaleEffect(focused ? 1 : 0.94)
            .andromedaLoop(.easeOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.7), value: focused)
            .onAppear { focused = true }
    }
}

// MARK: Word Rotate

/// A rotating claim — one word swaps on a vertical rail.
public struct WordRotate: View {
    public var words: [String]
    @State private var roll = false
    public init(words: [String] = ["episodic", "semantic", "soul"]) { self.words = words }
    public var body: some View {
        HStack(spacing: 6) {
            Text("memory ·").font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.andromedaMuted)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(words, id: \.self) { w in
                    Text(w)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.andromedaTeal)
                        .frame(height: 20)
                }
            }
            .offset(y: roll ? -CGFloat(words.count - 1) * 20 : 0)
            .frame(height: 20, alignment: .top)
            .clipped()
            .andromedaLoop(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: roll)
        }
        .onAppear { roll = true }
    }
}

// MARK: Morphing Text

/// A number that interpolates instead of cutting — `contentTransition`.
public struct MorphingText: View {
    public var from: Int
    public var to: Int
    @State private var high = false
    public init(from: Int = 1247, to: Int = 1893) { self.from = from; self.to = to }
    public var body: some View {
        Text("\(high ? to : from)")
            .font(.system(size: 26, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.andromedaGlow)
            .contentTransition(.numericText(countsDown: false))
            .andromedaLoop(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: high)
            .onAppear { high = true }
            .accessibilityLabel("count \(high ? to : from)")
    }
}

// MARK: Tab Underline

/// Selection that travels — the indicator slides, it never blinks.
public struct TabUnderline: View {
    public var tabs: [String]
    @State private var index = 0
    @Namespace private var ns
    public init(tabs: [String] = ["models", "speed", "health"]) { self.tabs = tabs }
    public var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                VStack(spacing: 6) {
                    Text(tab)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(i == index ? Color.andromedaGlow : Color.andromedaMuted)
                    ZStack {
                        Capsule().fill(.clear).frame(height: 2)
                        if i == index {
                            Capsule().fill(Color.andromedaTeal).frame(height: 2)
                                .matchedGeometryEffect(id: "underline", in: ns)
                        }
                    }
                }
            }
        }
        .andromedaLoop(.spring(duration: 0.5, bounce: 0.22).repeatForever(autoreverses: true).delay(0.8), value: index)
        .onAppear { index = tabs.count - 1 }
        .accessibilityElement(children: .contain)
    }
}

// MARK: Checkmark Toggle

/// A boolean with a drawn confirmation, not just a fill change.
public struct CheckmarkToggle: View {
    @State private var on = false
    public init() {}
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(on ? Color.andromedaLive.opacity(0.22) : .clear)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Color.andromedaLive : Color.andromedaMuted, lineWidth: 1.4))
                .frame(width: 30, height: 30)
            CheckPath().trim(from: 0, to: on ? 1 : 0)
                .stroke(Color.andromedaLive, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: 12)
        }
        .andromedaLoop(.easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(0.9), value: on)
        .onAppear { on = true }
        .accessibilityLabel("enabled")
        .accessibilityValue(on ? "on" : "off")
    }
}

// MARK: Chevron Rotate

/// The smallest state tell in the system.
public struct ChevronRotate: View {
    @State private var open = false
    public init() {}
    public var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color.andromedaTeal)
            .rotationEffect(.degrees(open ? 90 : 0))
            .andromedaLoop(.spring(duration: 0.45, bounce: 0.4).repeatForever(autoreverses: true).delay(0.8), value: open)
            .onAppear { open = true }
    }
}

// MARK: Marquee

/// A horizontal ticker — log tail, model list, fleet names.
public struct Marquee: View {
    public var text: String
    @State private var run = false
    public init(_ text: String = "memory.recall · mcp.host · infer.write · fleet.pulse ·  ") { self.text = text }
    public var body: some View {
        HStack(spacing: 0) {
            Text(text); Text(text)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(Color.andromedaMuted)
        .fixedSize()
        .offset(x: run ? -230 : 0)
        .andromedaLoop(.linear(duration: 8).repeatForever(autoreverses: false), value: run)
        .frame(width: 150, height: 22)
        .clipped()
        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
        .onAppear { run = true }
        .accessibilityLabel("capability ticker")
    }
}

// MARK: Vertical Marquee

/// A rolling log — new lines pushing old ones up.
public struct VerticalMarquee: View {
    public var lines: [String]
    @State private var run = false
    public init(lines: [String] = ["append 0x4f", "flush 12", "ack 0x50", "recall hit", "embed 384d"]) {
        self.lines = lines
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines + lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.andromedaMuted)
                    .frame(height: 14, alignment: .leading)
            }
        }
        .frame(width: 110, alignment: .leading)
        .offset(y: run ? -CGFloat(lines.count) * 18 : 0)
        .andromedaLoop(.linear(duration: 6).repeatForever(autoreverses: false), value: run)
        .frame(width: 110, height: 60, alignment: .top)
        .clipped()
        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
        .onAppear { run = true }
        .accessibilityLabel("live log")
    }
}

// MARK: Shimmer Sweep

/// A sheen crossing a surface — value arriving, not loading.
public struct ShimmerSweep: View {
    @State private var sweep = false
    public init() {}
    public var body: some View {
        Text("andromeda")
            .font(.system(size: 21, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.andromedaTeal.opacity(0.35))
            .overlay {
                Text("andromeda")
                    .font(.system(size: 21, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.andromedaGlow)
                    .mask(
                        LinearGradient(colors: [.clear, .black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 70)
                            .offset(x: sweep ? 110 : -110)
                    )
            }
            .andromedaLoop(.linear(duration: 2.2).repeatForever(autoreverses: false), value: sweep)
            .onAppear { sweep = true }
    }
}

// MARK: Meteors

/// Ambient depth for empty states — streaks crossing the void.
public struct Meteors: View {
    public var count: Int
    @State private var fall = false
    public init(count: Int = 5) { self.count = count }
    public var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(colors: [.andromedaGlow, .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 44, height: 1.4)
                    .rotationEffect(.degrees(28))
                    .offset(
                        x: fall ? 90 : -90,
                        y: CGFloat(i) * 22 - 44 + (fall ? 48 : -48)
                    )
                    .opacity(fall ? 0 : 1)
                    .andromedaLoop(
                        .linear(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 0.42),
                        value: fall
                    )
            }
        }
        .frame(width: 160, height: 110)
        .clipped()
        .onAppear { fall = true }
        .accessibilityHidden(true)
    }
}

// MARK: Animated Beam

/// A link between two nodes, with the packet visible on the wire.
public struct AnimatedBeam: View {
    @State private var travel = false
    public init() {}
    public var body: some View {
        ZStack {
            HStack(spacing: 0) {
                node("cpu")
                Rectangle().fill(Color.andromedaTeal.opacity(0.18)).frame(height: 1.5)
                node("externaldrive.connected.to.line.below")
            }
            Circle().fill(Color.andromedaGlow)
                .frame(width: 7, height: 7)
                .shadow(color: .andromedaGlow, radius: 7)
                .offset(x: travel ? 40 : -40)
                .andromedaLoop(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: travel)
        }
        .frame(width: 152, height: 44)
        .onAppear { travel = true }
        .accessibilityLabel("link active")
    }
    private func node(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13))
            .foregroundStyle(Color.andromedaTeal)
            .frame(width: 34, height: 34)
            .background(
                Circle().fill(Color.andromedaTeal.opacity(0.1))
                    .overlay(Circle().stroke(Color.andromedaTeal.opacity(0.3)))
            )
    }
}

// MARK: Retro Grid

/// The horizon under hero surfaces — a perspective grid drifting forward.
public struct RetroGrid: View {
    @State private var drift = false
    public init() {}
    public var body: some View {
        ZStack {
            VStack(spacing: 14) {
                ForEach(0..<7, id: \.self) { _ in
                    Rectangle().fill(Color.andromedaTeal.opacity(0.22)).frame(height: 1)
                }
            }
            .offset(y: drift ? 14 : 0)
            .andromedaLoop(.linear(duration: 1.6).repeatForever(autoreverses: false), value: drift)
            HStack(spacing: 20) {
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle().fill(Color.andromedaTeal.opacity(0.14)).frame(width: 1)
                }
            }
        }
        .frame(width: 160, height: 96)
        .clipped()
        .rotation3DEffect(.degrees(62), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
        .onAppear { drift = true }
        .accessibilityHidden(true)
    }
}

// MARK: Ripple Field

/// Concentric rings from a shared center — the curtain's resting texture.
public struct RippleField: View {
    public var rings: Int
    @State private var out = false
    public init(rings: Int = 4) { self.rings = rings }
    public var body: some View {
        ZStack {
            ForEach(0..<rings, id: \.self) { i in
                Circle()
                    .stroke(Color.andromedaTeal.opacity(0.5), lineWidth: 1)
                    .frame(width: 26, height: 26)
                    .scaleEffect(out ? 3.4 : 0.5)
                    .opacity(out ? 0 : 0.8)
                    .andromedaLoop(
                        .easeOut(duration: 3.2).repeatForever(autoreverses: false).delay(Double(i) * 0.8),
                        value: out
                    )
            }
        }
        .frame(width: 110, height: 110)
        .onAppear { out = true }
        .accessibilityHidden(true)
    }
}

// MARK: Pulsating Button

/// The one call to action — a halo leaves the capsule on a slow beat.
public struct PulsatingButton: View {
    public var title: String
    @State private var pulse = false
    public init(_ title: String = "Wake Andromeda") { self.title = title }
    public var body: some View {
        Text(title)
            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.andromedaVoid)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(Capsule().fill(Color.andromedaTeal))
            .background(
                Capsule().fill(Color.andromedaTeal.opacity(0.4))
                    .scaleEffect(pulse ? 1.5 : 1)
                    .opacity(pulse ? 0 : 0.7)
                    .andromedaLoop(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulse)
            )
            .onAppear { pulse = true }
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: Gradient Text

/// A heading with the aurora moving through it.
public struct GradientText: View {
    public var text: String
    @State private var shift = false
    public init(_ text: String = "Control Plane") { self.text = text }
    public var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [.andromedaTeal, .andromedaGlow, .andromedaLive, .andromedaTeal],
                    startPoint: shift ? .trailing : .leading,
                    endPoint: shift ? .leading : .trailing
                )
            )
            .andromedaLoop(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: shift)
            .onAppear { shift = true }
    }
}

// MARK: Spinning Text

/// Characters set on a ring — a seal for the about panel.
public struct SpinningText: View {
    public var text: String
    public var radius: CGFloat
    @State private var spin = false
    public init(_ text: String = "ANDROMEDA · CONTROL PLANE · ", radius: CGFloat = 44) {
        self.text = text; self.radius = radius
    }
    public var body: some View {
        let chars = Array(text)
        ZStack {
            ForEach(Array(chars.enumerated()), id: \.offset) { i, ch in
                Text(String(ch))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.andromedaTeal)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(i) / Double(chars.count) * 360))
            }
            Circle().fill(Color.andromedaGlow).frame(width: 8, height: 8)
                .shadow(color: .andromedaGlow, radius: 8)
        }
        .frame(width: radius * 2 + 16, height: radius * 2 + 16)
        .rotationEffect(.degrees(spin ? 360 : 0))
        .andromedaLoop(.linear(duration: 18).repeatForever(autoreverses: false), value: spin)
        .onAppear { spin = true }
        .accessibilityLabel(text)
    }
}

// MARK: Flickering Grid

/// Background texture that reads as activity — deterministic, not random.
public struct FlickeringGrid: View {
    public var columns: Int
    public var rows: Int
    @State private var flicker = false
    public init(columns: Int = 9, rows: Int = 6) { self.columns = columns; self.rows = rows }
    public var body: some View {
        VStack(spacing: 5) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 5) {
                    ForEach(0..<columns, id: \.self) { c in
                        let seed = Double((r * 7 + c * 13) % 11) / 11
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.andromedaTeal)
                            .frame(width: 9, height: 9)
                            .opacity(flicker ? 0.08 + seed * 0.55 : 0.5 - seed * 0.4)
                            .andromedaLoop(
                                .easeInOut(duration: 1.2 + seed).repeatForever(autoreverses: true).delay(seed * 1.6),
                                value: flicker
                            )
                    }
                }
            }
        }
        .onAppear { flicker = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Cross Fade")        { SchemePair { CrossFade() } }
#Preview("Slide Swap")        { SchemePair { SlideSwap() } }
#Preview("Scale Pop")         { SchemePair { ScalePop() } }
#Preview("Matched Geometry")  { SchemePair { MatchedGeometrySwap() } }
#Preview("Phase Cycle")       { SchemePair { PhaseCycle() } }
#Preview("Expand / Collapse") { SchemePair { ExpandCollapse() } }
#Preview("Blur Fade")         { SchemePair { BlurFade() } }
#Preview("Word Rotate")       { SchemePair { WordRotate() } }
#Preview("Morphing Text")     { SchemePair { MorphingText() } }
#Preview("Tab Underline")     { SchemePair { TabUnderline() } }
#Preview("Checkmark Toggle")  { SchemePair { CheckmarkToggle() } }
#Preview("Chevron Rotate")    { SchemePair { ChevronRotate() } }
#Preview("Marquee")           { SchemePair { Marquee() } }
#Preview("Vertical Marquee")  { SchemePair { VerticalMarquee() } }
#Preview("Border Beam")       { SchemePair { RoundedRectangle(cornerRadius: 20).fill(Color.andromedaPanel).frame(width: 132, height: 66).borderBeam() } }
#Preview("Shimmer Sweep")     { SchemePair { ShimmerSweep() } }
#Preview("Meteors")           { SchemePair { Meteors() } }
#Preview("Animated Beam")     { SchemePair { AnimatedBeam() } }
#Preview("Retro Grid")        { SchemePair { RetroGrid() } }
#Preview("Ripple Field")      { SchemePair { RippleField() } }
#Preview("Pulsating Button")  { SchemePair { PulsatingButton() } }
#Preview("Gradient Text")     { SchemePair { GradientText() } }
#Preview("Spinning Text")     { SchemePair { SpinningText() } }
#Preview("Flickering Grid")   { SchemePair { FlickeringGrid() } }

#Preview("Swap · states") {
    AndromedaStateMatrix { state in
        Group {
            switch state {
            case .idle:   ChevronRotate()
            case .active: SlideSwap()
            case .alert:  CrossFade("degraded", "retrying")
            case .done:   CheckmarkToggle()
            }
        }
        .andromedaMotion(state.isAnimating)
    }
    .preferredColorScheme(.dark)
}
