import SwiftUI

// MARK: - Pillar motion kit
// The techniques from the open-swiftui-animations catalogue, packaged as
// reusable modifiers and applied across the nine pillars. Each piece names
// the specimen it derives from so the gallery and the board stay in step.
//
//   DashMarch      → MarchingBorder, TravellingDash
//   SignatureDraw  → TrimDraw
//   NumericCrossfade → NumericTicker
//   Typewriter     → TypingLog
//   LikeBurst      → KeyframePop
//   Jiggle/Jello   → JelloOnChange
//   HueRotation    → HueDrift
//   PulsingHeart   → PhasePulse
//   Thinking       → ThinkingDots
//   ShimmerSkeleton→ Shimmer
//   ConfettiBurst  → SparkBurst
//   IncomingCall   → SymbolBeacon

// MARK: DashMarch — a border whose dashes crawl

public struct MarchingBorder: ViewModifier {
    public var color: Color
    public var radius: CGFloat
    public var lineWidth: CGFloat
    public var period: Double
    @State private var phase: CGFloat = 0

    public init(color: Color, radius: CGFloat = 8, lineWidth: CGFloat = 1, period: Double = 1.4) {
        self.color = color; self.radius = radius; self.lineWidth = lineWidth; self.period = period
    }

    public func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: [5, 4], dashPhase: phase))
        )
        .onAppear {
            withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) { phase = -18 }
        }
    }
}

public extension View {
    /// Crawling dashed border — marks the element currently doing work.
    func marchingBorder(_ color: Color, radius: CGFloat = 8, period: Double = 1.4) -> some View {
        modifier(MarchingBorder(color: color, radius: radius, period: period))
    }
}

// MARK: SignatureDraw — a path that draws itself, then erases

public struct TrimDraw<S: Shape>: View {
    public var shape: S
    public var color: Color
    public var lineWidth: CGFloat
    public var period: Double

    public init(_ shape: S, color: Color, lineWidth: CGFloat = 1.6, period: Double = 2.6) {
        self.shape = shape; self.color = color; self.lineWidth = lineWidth; self.period = period
    }

    public var body: some View {
        PhaseAnimator([0.0, 1.0], trigger: false) { phase in
            shape
                .trim(from: 0, to: phase)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        } animation: { _ in
            .easeInOut(duration: period)
        }
    }
}

// MARK: NumericCrossfade — digits that roll instead of snap

public struct NumericTicker: View {
    public var value: Int
    public var size: CGFloat
    public var weight: Font.Weight
    public var glow: Color

    public init(_ value: Int, size: CGFloat = 32, weight: Font.Weight = .medium, glow: Color = .andromedaTeal) {
        self.value = value; self.size = size; self.weight = weight; self.glow = glow
    }

    public var body: some View {
        Text(value, format: .number.grouping(.automatic))
            .font(AndromedaFont.mono(size, weight))
            .foregroundStyle(Color.andromedaInk)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(value)))
            .shadow(color: glow.opacity(0.55), radius: size * 0.45)
            .animation(.snappy(duration: 0.35), value: value)
            .accessibilityLabel("\(value)")
    }
}

// MARK: Typewriter — the log line types itself in

public struct TypingLog: View {
    public var text: String
    public var tint: Color
    public var charactersPerSecond: Double
    public var holdSeconds: Double

    public init(_ text: String, tint: Color, charactersPerSecond: Double = 42, holdSeconds: Double = 2.4) {
        self.text = text; self.tint = tint
        self.charactersPerSecond = charactersPerSecond; self.holdSeconds = holdSeconds
    }

    public var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let typing = Double(text.count) / charactersPerSecond
            let loop = (t).truncatingRemainder(dividingBy: typing + holdSeconds)
            let shown = min(text.count, Int(loop * charactersPerSecond))
            let done = shown >= text.count
            HStack(spacing: 2) {
                Text(String(text.prefix(shown)))
                    .font(AndromedaFont.mono(9))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Rectangle()
                    .fill(tint)
                    .frame(width: 5, height: 10)
                    .opacity(done ? (loop.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0) : 0.9)
                Spacer(minLength: 0)
            }
            .accessibilityLabel(text)
        }
    }
}

// MARK: LikeBurst — keyframed overshoot on a discrete event

public struct KeyframePop<Trigger: Equatable>: ViewModifier {
    public var trigger: Trigger
    public init(trigger: Trigger) { self.trigger = trigger }

    public func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: PopFrame(), trigger: trigger) { view, frame in
            view.scaleEffect(frame.scale).rotationEffect(.degrees(frame.tilt))
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                SpringKeyframe(1.22, duration: 0.16, spring: .bouncy)
                SpringKeyframe(0.95, duration: 0.14, spring: .bouncy)
                SpringKeyframe(1.0, duration: 0.22, spring: .bouncy)
            }
            KeyframeTrack(\.tilt) {
                CubicKeyframe(-4, duration: 0.14)
                CubicKeyframe(3, duration: 0.16)
                CubicKeyframe(0, duration: 0.22)
            }
        }
    }
}

public struct PopFrame: Equatable, Sendable {
    public var scale: CGFloat = 1
    public var tilt: Double = 0
    public init() {}
}

public extension View {
    /// Springy overshoot whenever `trigger` changes — state chips, badges.
    func keyframePop<T: Equatable>(on trigger: T) -> some View {
        modifier(KeyframePop(trigger: trigger))
    }
}

// MARK: Jiggle / Jello — squash on change, for things that must be noticed

public struct JelloOnChange<Trigger: Equatable>: ViewModifier {
    public var trigger: Trigger
    public init(trigger: Trigger) { self.trigger = trigger }

    public func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: JelloFrame(), trigger: trigger) { view, frame in
            view.scaleEffect(x: frame.x, y: frame.y)
        } keyframes: { _ in
            KeyframeTrack(\.x) {
                CubicKeyframe(1.16, duration: 0.14)
                CubicKeyframe(0.92, duration: 0.14)
                SpringKeyframe(1, duration: 0.28, spring: .bouncy)
            }
            KeyframeTrack(\.y) {
                CubicKeyframe(0.86, duration: 0.14)
                CubicKeyframe(1.10, duration: 0.14)
                SpringKeyframe(1, duration: 0.28, spring: .bouncy)
            }
        }
    }
}

public struct JelloFrame: Equatable, Sendable {
    public var x: CGFloat = 1
    public var y: CGFloat = 1
    public init() {}
}

public extension View {
    func jello<T: Equatable>(on trigger: T) -> some View { modifier(JelloOnChange(trigger: trigger)) }
}

// MARK: HueRotation — the dream ramp drifts through its neighbours

public struct HueDrift: ViewModifier {
    public var degrees: Double
    public var period: Double
    public var active: Bool
    @State private var on = false

    public init(degrees: Double = 18, period: Double = 6, active: Bool = true) {
        self.degrees = degrees; self.period = period; self.active = active
    }

    public func body(content: Content) -> some View {
        content
            .hueRotation(.degrees(active && on ? degrees : 0))
            .animation(.easeInOut(duration: period).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

public extension View {
    func hueDrift(_ degrees: Double = 18, period: Double = 6, active: Bool = true) -> some View {
        modifier(HueDrift(degrees: degrees, period: period, active: active))
    }
}

// MARK: PulsingHeart — a phase-driven double beat

public struct PhasePulse<Content: View>: View {
    public var color: Color
    private let content: Content

    public init(color: Color = .andromedaTeal, @ViewBuilder _ content: () -> Content) {
        self.color = color; self.content = content()
    }

    public var body: some View {
        PhaseAnimator([0, 1, 2], trigger: false) { phase in
            content
                .scaleEffect(phase == 1 ? 1.14 : (phase == 2 ? 0.97 : 1))
                .shadow(color: color.opacity(phase == 1 ? 0.75 : 0.25), radius: phase == 1 ? 14 : 5)
        } animation: { phase in
            phase == 1 ? .bouncy(duration: 0.28) : .easeOut(duration: 0.6)
        }
    }
}

// MARK: Thinking — three dots weighing options

public struct ThinkingDots: View {
    public var color: Color
    public var dotSize: CGFloat
    public init(color: Color = .andromedaTeal, dotSize: CGFloat = 5) {
        self.color = color; self.dotSize = dotSize
    }

    public var body: some View {
        PhaseAnimator([0, 1, 2], trigger: false) { phase in
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(color)
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(phase == i ? 1.5 : 0.85)
                        .opacity(phase == i ? 1 : 0.4)
                }
            }
        } animation: { _ in .easeInOut(duration: 0.32) }
    }
}

// MARK: ShimmerSkeleton — a sheen crossing pending rows

public struct Shimmer: ViewModifier {
    public var color: Color
    public var period: Double
    @State private var phase: CGFloat = -1

    public init(color: Color = .andromedaGlow, period: Double = 1.4) {
        self.color = color; self.period = period
    }

    public func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(colors: [.clear, color.opacity(0.45), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: phase * geo.size.width)
            }
            .allowsHitTesting(false)
        )
        .onAppear {
            withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) { phase = 1.6 }
        }
    }
}

public extension View {
    func shimmer(_ color: Color = .andromedaGlow, period: Double = 1.4) -> some View {
        modifier(Shimmer(color: color, period: period))
    }
}

// MARK: ConfettiBurst — sparks for a threshold crossed

public struct SparkBurst: View {
    public var color: Color
    public var count: Int
    public var time: TimeInterval
    public var period: Double

    public init(color: Color, count: Int = 14, time: TimeInterval, period: Double = 2.6) {
        self.color = color; self.count = count; self.time = time; self.period = period
    }

    public var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let p = (time / period).truncatingRemainder(dividingBy: 1)
            let eased = 1 - pow(1 - p, 2.4)
            for i in 0..<count {
                let angle = Double(i) / Double(count) * .pi * 2
                let reach = size.height * (0.32 + Double(i % 3) * 0.09)
                let pt = CGPoint(x: center.x + CGFloat(cos(angle) * reach * eased),
                                 y: center.y + CGFloat(sin(angle) * reach * eased))
                let r = CGFloat(2.4 * (1 - p))
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                         with: .color(color.opacity(0.85 * (1 - p))))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: IncomingCall — a symbol beacon with variable colour

public struct SymbolBeacon: View {
    public var systemName: String
    public var color: Color
    public var size: CGFloat
    public var active: Bool

    public init(_ systemName: String, color: Color, size: CGFloat = 15, active: Bool = true) {
        self.systemName = systemName; self.color = color; self.size = size; self.active = active
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundStyle(color)
            .symbolEffect(.variableColor.iterative.reversing, isActive: active)
            .symbolEffect(.pulse, isActive: active)
    }
}

// MARK: TravellingDash — a signal moving along a wire

public struct TravellingDash: Shape, Sendable {
    public var from: CGPoint
    public var to: CGPoint
    public init(from: CGPoint, to: CGPoint) { self.from = from; self.to = to }

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + from.x * rect.width, y: rect.minY + from.y * rect.height))
        p.addLine(to: CGPoint(x: rect.minX + to.x * rect.width, y: rect.minY + to.y * rect.height))
        return p
    }
}

/// Standard dash-phase stroke for any "work in flight" wire.
public extension StrokeStyle {
    static func flowing(_ time: TimeInterval, speed: Double = 26, width: CGFloat = 1.5) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, dash: [6, 8], dashPhase: -time * speed)
    }
}
