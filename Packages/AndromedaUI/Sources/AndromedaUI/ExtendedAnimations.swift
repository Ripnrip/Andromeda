import SwiftUI

// MARK: - Extended set
// Loaders, feedback, and ambient motion for the whole control plane —
// same tokens, same teal. Every specimen gates its loop through
// `andromedaLoop` so previews, snapshots, and Reduce Motion all behave.

// MARK: Data Stream

/// Packets traveling a bus — write-ahead log, outbox drain, sync in flight.
public struct DataStream: View {
    public var dots: Int
    public var tint: Color
    @State private var go = false
    public init(dots: Int = 4, tint: Color = .andromedaTeal) { self.dots = dots; self.tint = tint }
    public var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(tint.opacity(0.16)).frame(width: 140, height: 2)
            ForEach(0..<dots, id: \.self) { i in
                Circle().fill(tint)
                    .frame(width: 6, height: 6)
                    .shadow(color: tint, radius: 6)
                    .offset(x: go ? 140 : 0)
                    .andromedaLoop(
                        .linear(duration: 1.8).repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.45),
                        value: go
                    )
            }
        }
        .frame(width: 140, height: 20)
        .onAppear { go = true }
        .accessibilityLabel("data streaming")
    }
}

// MARK: Signal Bars

/// Throughput. Four bars rising in sequence.
public struct SignalBars: View {
    public var heights: [CGFloat]
    public var tint: Color
    @State private var up = false
    public init(heights: [CGFloat] = [14, 22, 30, 38], tint: Color = .andromedaTeal) {
        self.heights = heights; self.tint = tint
    }
    public var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { i, h in
                Capsule().fill(tint)
                    .frame(width: 5, height: h)
                    .scaleEffect(y: up ? 1 : 0.3, anchor: .bottom)
                    .opacity(up ? 1 : 0.4)
                    .andromedaLoop(
                        .easeInOut(duration: 0.7).repeatForever().delay(Double(i) * 0.11),
                        value: up
                    )
            }
        }
        .frame(height: 40, alignment: .bottom)
        .onAppear { up = true }
    }
}

// MARK: Typing Caret

/// A capability id being written, with a blinking block caret.
public struct TypingCaret: View {
    public var text: String
    @State private var visible = true
    public init(_ text: String = "infer.write") { self.text = text }
    public var body: some View {
        HStack(spacing: 2) {
            Text(text)
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(Color.andromedaGlow)
            Rectangle().fill(Color.andromedaTeal)
                .frame(width: 2, height: 17)
                .opacity(visible ? 1 : 0)
                .andromedaLoop(.easeInOut(duration: 0.55).repeatForever(), value: visible)
        }
        .onAppear { visible = false }
        .accessibilityLabel(text)
    }
}

// MARK: Spinner Arc

/// Indeterminate work. One trimmed arc on a dim track.
public struct SpinnerArc: View {
    public var size: CGFloat
    public var tint: Color
    @State private var spin = false
    public init(size: CGFloat = 34, tint: Color = .andromedaTeal) { self.size = size; self.tint = tint }
    public var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.16), lineWidth: 3)
            Circle().trim(from: 0, to: 0.28)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .andromedaLoop(.linear(duration: 0.85).repeatForever(autoreverses: false), value: spin)
        }
        .frame(width: size, height: size)
        .onAppear { spin = true }
        .accessibilityLabel("working")
    }
}

// MARK: Progress Fill

/// Determinate work — a value you can trust, not a spinner.
public struct ProgressFill: View {
    public var value: Double
    public var tint: Color
    public init(value: Double = 0.62, tint: Color = .andromedaTeal) {
        self.value = min(max(value, 0), 1); self.tint = tint
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(colors: [tint, .andromedaGlow], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * value)
                        .shadow(color: tint.opacity(0.7), radius: 6)
                }
            }
            .frame(width: 130, height: 6)
            Text("\(Int(value * 100))%")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color.andromedaMuted)
        }
        .animation(.spring(duration: 0.5, bounce: 0.2), value: value)
        .accessibilityLabel("progress \(Int(value * 100)) percent")
    }
}

// MARK: Radar Ping

/// Discovery. Rings leaving a node — fleet probe, mDNS sweep.
public struct RadarPing: View {
    public var tint: Color
    @State private var ping = false
    public init(tint: Color = .andromedaTeal) { self.tint = tint }
    public var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle().stroke(tint, lineWidth: 1.2)
                    .frame(width: 22, height: 22)
                    .scaleEffect(ping ? 2.6 : 0.6)
                    .opacity(ping ? 0 : 0.9)
                    .andromedaLoop(
                        .easeOut(duration: 2.1).repeatForever(autoreverses: false).delay(Double(i) * 0.7),
                        value: ping
                    )
            }
            Circle().fill(tint).frame(width: 10, height: 10).shadow(color: tint, radius: 8)
        }
        .frame(width: 70, height: 70)
        .onAppear { ping = true }
    }
}

// MARK: Heartbeat

/// The ECG trace — process liveness, drawn not faked.
public struct Heartbeat: View {
    public var tint: Color
    @State private var draw = false
    public init(tint: Color = .andromedaLive) { self.tint = tint }
    public var body: some View {
        ECGPath()
            .trim(from: 0, to: draw ? 1 : 0)
            .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .shadow(color: tint.opacity(0.8), radius: 5)
            .frame(width: 116, height: 44)
            .andromedaLoop(.easeInOut(duration: 1.9).repeatForever(autoreverses: false), value: draw)
            .onAppear { draw = true }
            .accessibilityLabel("heartbeat")
    }
}

/// The spike shape behind `Heartbeat`.
public struct ECGPath: Shape {
    public init() {}
    public func path(in r: CGRect) -> Path {
        var p = Path()
        let mid = r.midY
        p.move(to: CGPoint(x: 0, y: mid))
        p.addLine(to: CGPoint(x: r.width * 0.26, y: mid))
        p.addLine(to: CGPoint(x: r.width * 0.33, y: mid - r.height * 0.32))
        p.addLine(to: CGPoint(x: r.width * 0.41, y: mid + r.height * 0.34))
        p.addLine(to: CGPoint(x: r.width * 0.48, y: mid - r.height * 0.18))
        p.addLine(to: CGPoint(x: r.width * 0.55, y: mid))
        p.addLine(to: CGPoint(x: r.width, y: mid))
        return p
    }
}

// MARK: Dot Loader

/// Three dots, phase-offset — the smallest "thinking" tell.
public struct DotLoader: View {
    public var tint: Color
    @State private var up = false
    public init(tint: Color = .andromedaTeal) { self.tint = tint }
    public var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(tint)
                    .frame(width: 9, height: 9)
                    .offset(y: up ? -7 : 0)
                    .opacity(up ? 1 : 0.45)
                    .andromedaLoop(
                        .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.13),
                        value: up
                    )
            }
        }
        .frame(height: 24)
        .onAppear { up = true }
        .accessibilityLabel("loading")
    }
}

// MARK: Aurora

/// The ambient backdrop — two slow blurred lobes drifting past each other.
public struct Aurora: View {
    @State private var drift = false
    public init() {}
    public var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.andromedaTeal.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 44))
                .frame(width: 88, height: 88)
                .blur(radius: 10)
                .offset(x: drift ? 22 : -22, y: drift ? -14 : 10)
            Circle()
                .fill(RadialGradient(colors: [Color.andromedaLive.opacity(0.40), .clear], center: .center, startRadius: 0, endRadius: 40))
                .frame(width: 78, height: 78)
                .blur(radius: 10)
                .offset(x: drift ? -20 : 20, y: drift ? 14 : -10)
        }
        .frame(width: 150, height: 100)
        .andromedaLoop(.easeInOut(duration: 5).repeatForever(), value: drift)
        .onAppear { drift = true }
        .accessibilityHidden(true)
    }
}

// MARK: Token Roll

/// A counter that rolls rather than jumps — tokens, spend, recall count.
public struct TokenRoll: View {
    public var prefix: String
    public var digits: [String]
    @State private var roll = false
    public init(prefix: String = "1,2", digits: [String] = ["4", "5", "6", "7"]) {
        self.prefix = prefix; self.digits = digits
    }
    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(prefix)
            VStack(spacing: 0) {
                ForEach(digits, id: \.self) { Text($0) }
            }
            .offset(y: roll ? -CGFloat(digits.count - 1) * 26 : 0)
            .andromedaLoop(
                .timingCurve(0.6, 0, 0.2, 1, duration: 2.4).repeatForever(autoreverses: false),
                value: roll
            )
            .frame(height: 26, alignment: .top)
            .clipped()
        }
        .font(.system(size: 22, weight: .medium, design: .monospaced))
        .foregroundStyle(Color.andromedaGlow)
        .onAppear { roll = true }
        .accessibilityLabel("token count rolling")
    }
}

// MARK: Ripple Tap

/// Touch acknowledgement — a ring leaving the point of contact.
public struct RippleTap: View {
    public var tint: Color
    @State private var ripple = false
    public init(tint: Color = .andromedaTeal) { self.tint = tint }
    public var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.8), lineWidth: 1.4)
                .frame(width: 30, height: 30)
                .scaleEffect(ripple ? 2.2 : 1)
                .opacity(ripple ? 0 : 1)
                .andromedaLoop(.easeOut(duration: 1.3).repeatForever(autoreverses: false), value: ripple)
            RoundedRectangle(cornerRadius: 11)
                .fill(tint.opacity(0.16))
                .frame(width: 76, height: 34)
                .overlay(
                    Text("recall")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.andromedaGlow)
                )
        }
        .frame(width: 110, height: 60)
        .onAppear { ripple = true }
    }
}

// MARK: Success Check

/// Completion — a ring closes, a check draws.
public struct SuccessCheck: View {
    public var tint: Color
    @State private var done = false
    public init(tint: Color = .andromedaLive) { self.tint = tint }
    public var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: 2.4).frame(width: 46, height: 46)
            Circle().trim(from: 0, to: done ? 1 : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 46, height: 46)
            CheckPath().trim(from: 0, to: done ? 1 : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .frame(width: 24, height: 18)
        }
        .shadow(color: tint.opacity(done ? 0.6 : 0), radius: 10)
        .andromedaLoop(.easeInOut(duration: 0.7).delay(0.15), value: done)
        .onAppear { done = true }
        .accessibilityLabel("succeeded")
    }
}

/// The tick behind `SuccessCheck` and `CheckmarkToggle`.
public struct CheckPath: Shape {
    public init() {}
    public func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r.height * 0.55))
        p.addLine(to: CGPoint(x: r.width * 0.38, y: r.height))
        p.addLine(to: CGPoint(x: r.width, y: 0))
        return p
    }
}

// MARK: Error Shake

/// Rejection — a short lateral shake, never a color change alone.
public struct ErrorShake: View {
    public var label: String
    @State private var shake = false
    public init(_ label: String = "secrets.broker") { self.label = label }
    public var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12))
            Text(label).font(.system(size: 11.5, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(Color.andromedaAlert)
        .padding(.horizontal, 13).padding(.vertical, 8)
        .background(
            Capsule().fill(Color.andromedaAlert.opacity(0.12))
                .overlay(Capsule().stroke(Color.andromedaAlert.opacity(0.35)))
        )
        .offset(x: shake ? 5 : -5)
        .andromedaLoop(.easeInOut(duration: 0.09).repeatCount(6, autoreverses: true), value: shake)
        .onAppear { shake = true }
        .accessibilityLabel("\(label) failed")
    }
}


// MARK: Badge Pop

/// A count arriving — spring in, never fade in.
public struct BadgePop: View {
    public var count: Int
    @State private var pop = false
    public init(count: Int = 3) { self.count = count }
    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.andromedaMuted)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.andromedaVoid)
                .frame(width: 17, height: 17)
                .background(Circle().fill(Color.andromedaLive))
                .scaleEffect(pop ? 1 : 0.1)
                .offset(x: 8, y: -5)
                .andromedaLoop(.spring(duration: 0.5, bounce: 0.62).delay(0.2), value: pop)
        }
        .frame(width: 54, height: 44)
        .onAppear { pop = true }
        .accessibilityLabel("\(count) notifications")
    }
}

// MARK: Route Trace

/// A request finding its provider — the line draws, a head leads it.
public struct RouteTrace: View {
    public var tint: Color
    @State private var trace = false
    public init(tint: Color = .andromedaTeal) { self.tint = tint }
    public var body: some View {
        ZStack {
            RoutePath().stroke(tint.opacity(0.18), lineWidth: 1.5)
            RoutePath().trim(from: trace ? 1 : 0, to: trace ? 1 : 0.001)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            RoutePath().trim(from: 0, to: trace ? 1 : 0)
                .stroke(
                    LinearGradient(colors: [tint.opacity(0), tint, .andromedaGlow], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
                .shadow(color: tint.opacity(0.7), radius: 5)
        }
        .frame(width: 132, height: 56)
        .andromedaLoop(.easeInOut(duration: 2.2).repeatForever(autoreverses: false), value: trace)
        .onAppear { trace = true }
        .accessibilityLabel("routing request")
    }
}

/// The S-curve behind `RouteTrace`.
public struct RoutePath: Shape {
    public init() {}
    public func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r.height * 0.5))
        p.addCurve(
            to: CGPoint(x: r.width * 0.5, y: r.height * 0.2),
            control1: CGPoint(x: r.width * 0.25, y: r.height * 0.5),
            control2: CGPoint(x: r.width * 0.25, y: r.height * 0.2)
        )
        p.addCurve(
            to: CGPoint(x: r.width, y: r.height * 0.82),
            control1: CGPoint(x: r.width * 0.75, y: r.height * 0.2),
            control2: CGPoint(x: r.width * 0.75, y: r.height * 0.82)
        )
        return p
    }
}

// MARK: Edge Pulse

/// A surface asking for attention without moving — the border breathes.
public struct EdgePulse: View {
    public var tint: Color
    @State private var pulse = false
    public init(tint: Color = .andromedaTeal) { self.tint = tint }
    public var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(tint, lineWidth: pulse ? 2.2 : 1)
            .frame(width: 118, height: 62)
            .shadow(color: tint.opacity(pulse ? 0.7 : 0.1), radius: pulse ? 12 : 2)
            .opacity(pulse ? 1 : 0.45)
            .andromedaLoop(.easeInOut(duration: 1.5).repeatForever(), value: pulse)
            .onAppear { pulse = true }
            .accessibilityHidden(true)
    }
}

// MARK: Segmented Loader

/// A dashed ring — indeterminate work with a mechanical read.
public struct SegmentedLoader: View {
    public var tint: Color
    @State private var spin = false
    public init(tint: Color = .andromedaTeal) { self.tint = tint }
    public var body: some View {
        Circle()
            .stroke(tint, style: StrokeStyle(lineWidth: 2.4, dash: [5, 6]))
            .frame(width: 38, height: 38)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .andromedaLoop(.linear(duration: 3).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
            .accessibilityLabel("working")
    }
}

// MARK: Idle Float

/// The bar at rest — a slow vertical drift so it never looks frozen.
public struct IdleFloat: View {
    @State private var float = false
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("andromeda").font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.andromedaGlow)
            Text("idle · listening").font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color.andromedaMuted)
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 13).fill(Color.andromedaPanel.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.andromedaTeal.opacity(0.18)))
        )
        .offset(y: float ? -6 : 6)
        .shadow(color: .black.opacity(0.35), radius: float ? 16 : 8, y: float ? 12 : 6)
        .andromedaLoop(.easeInOut(duration: 3.2).repeatForever(), value: float)
        .onAppear { float = true }
    }
}

// MARK: Ambient Glow

/// Powered and listening — the smallest ambient token in the system.
public struct AmbientGlow: View {
    public var tint: Color
    @State private var glow = false
    public init(tint: Color = .andromedaLive) { self.tint = tint }
    public var body: some View {
        Circle()
            .fill(RadialGradient(colors: [tint, tint.opacity(0.12)], center: .center, startRadius: 0, endRadius: 16))
            .frame(width: 24, height: 24)
            .scaleEffect(glow ? 1.28 : 0.86)
            .shadow(color: tint.opacity(glow ? 0.8 : 0.25), radius: glow ? 20 : 6)
            .andromedaLoop(.easeInOut(duration: 2.6).repeatForever(), value: glow)
            .onAppear { glow = true }
            .accessibilityHidden(true)
    }
}

// MARK: Flip Tile

/// A stat swapping its face — 3D flip, not a crossfade.
public struct FlipTile: View {
    public var front: String
    public var back: String
    @State private var flipped = false
    public init(front: String = "1,247", back: String = "recalls") { self.front = front; self.back = back }
    public var body: some View {
        ZStack {
            face(front).opacity(flipped ? 0 : 1)
            face(back).opacity(flipped ? 1 : 0).rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 1, y: 0, z: 0))
        .andromedaLoop(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(1.1), value: flipped)
        .onAppear { flipped = true }
    }
    private func face(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 17, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.andromedaGlow)
            .frame(width: 104, height: 54)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Color.andromedaTeal.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.andromedaTeal.opacity(0.28)))
            )
    }
}

// MARK: Scanline

/// Inspection — a line sweeping a panel while it is read.
public struct Scanline: View {
    public var tint: Color
    @State private var sweep = false
    public init(tint: Color = .andromedaTeal) { self.tint = tint }
    public var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.andromedaPanel.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.2)))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(tint.opacity(0.16))
                        .frame(width: [70.0, 88.0, 54.0][i], height: 5)
                }
            }
            .padding(14)
            LinearGradient(colors: [.clear, tint.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
                .offset(y: sweep ? 62 : -8)
                .andromedaLoop(.easeInOut(duration: 1.9).repeatForever(autoreverses: false), value: sweep)
        }
        .frame(width: 122, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { sweep = true }
        .accessibilityLabel("scanning")
    }
}

// MARK: Orbit Cluster

/// Concurrent work — several satellites at different radii and speeds.
public struct OrbitCluster: View {
    public var rings: Int
    @State private var spin = false
    public init(rings: Int = 3) { self.rings = rings }
    public var body: some View {
        ZStack {
            Circle().fill(Color.andromedaTeal).frame(width: 12, height: 12)
                .shadow(color: .andromedaTeal, radius: 9)
            ForEach(0..<rings, id: \.self) { i in
                let radius = 18 + CGFloat(i) * 13
                Circle().stroke(Color.andromedaTeal.opacity(0.14), lineWidth: 1)
                    .frame(width: radius * 2, height: radius * 2)
                Circle().fill(Color.andromedaGlow)
                    .frame(width: 6, height: 6)
                    .shadow(color: .andromedaGlow, radius: 5)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .andromedaLoop(
                        .linear(duration: 4 + Double(i) * 2.4).repeatForever(autoreverses: false),
                        value: spin
                    )
            }
        }
        .frame(width: 110, height: 110)
        .onAppear { spin = true }
        .accessibilityLabel("concurrent work in flight")
    }
}

// MARK: Elastic Toggle

/// A switch with weight — the knob overshoots, the track catches up.
public struct ElasticToggle: View {
    public var tint: Color
    @State private var on = false
    public init(tint: Color = .andromedaLive) { self.tint = tint }
    public var body: some View {
        Capsule()
            .fill(on ? tint.opacity(0.32) : Color.andromedaMuted.opacity(0.2))
            .frame(width: 56, height: 31)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(on ? tint : Color.andromedaMuted)
                    .frame(width: 25, height: 25)
                    .shadow(color: on ? tint.opacity(0.8) : .clear, radius: 8)
                    .padding(3)
            }
            .andromedaLoop(.spring(duration: 0.55, bounce: 0.55).repeatForever(autoreverses: true).delay(0.6), value: on)
            .onAppear { on = true }
            .accessibilityLabel("toggle")
            .accessibilityValue(on ? "on" : "off")
    }
}

// MARK: Broadcast

/// One node telling the fleet — arcs leaving in one direction.
public struct Broadcast: View {
    public var tint: Color
    @State private var emit = false
    public init(tint: Color = .andromedaTeal) { self.tint = tint }
    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 12, height: 12).shadow(color: tint, radius: 8)
            ZStack(alignment: .leading) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().trim(from: 0.86, to: 1.14)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 26 + CGFloat(i) * 20, height: 26 + CGFloat(i) * 20)
                        .opacity(emit ? 0.15 : 0.95)
                        .andromedaLoop(
                            .easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(Double(i) * 0.28),
                            value: emit
                        )
                }
            }
            .frame(width: 46, height: 66, alignment: .leading)
        }
        .frame(width: 96, height: 70)
        .onAppear { emit = true }
        .accessibilityLabel("broadcasting to fleet")
    }
}

// MARK: Ignition

/// Cold start — sparks leaving the core as the runtime comes up.
public struct Ignition: View {
    public var sparks: Int
    @State private var fire = false
    public init(sparks: Int = 9) { self.sparks = sparks }
    public var body: some View {
        ZStack {
            ForEach(0..<sparks, id: \.self) { i in
                let angle = Double(i) / Double(sparks) * 2 * .pi
                Circle()
                    .fill(i.isMultiple(of: 2) ? Color.andromedaGlow : Color.andromedaLive)
                    .frame(width: 4, height: 4)
                    .offset(
                        x: fire ? CGFloat(cos(angle)) * 42 : 0,
                        y: fire ? CGFloat(sin(angle)) * 42 : 0
                    )
                    .opacity(fire ? 0 : 1)
                    .andromedaLoop(
                        .easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(Double(i) * 0.06),
                        value: fire
                    )
            }
            Circle().fill(Color.andromedaTeal).frame(width: 16, height: 16)
                .shadow(color: .andromedaTeal, radius: fire ? 16 : 6)
        }
        .frame(width: 110, height: 110)
        .onAppear { fire = true }
        .accessibilityLabel("starting up")
    }
}

// MARK: - Previews

#Preview("Data Stream")      { SchemePair { DataStream() } }
#Preview("Signal Bars")      { SchemePair { SignalBars() } }
#Preview("Typing Caret")     { SchemePair { TypingCaret() } }
#Preview("Spinner Arc")      { SchemePair { SpinnerArc() } }
#Preview("Progress Fill")    { SchemePair { ProgressFill() } }
#Preview("Radar Ping")       { SchemePair { RadarPing() } }
#Preview("Heartbeat")        { SchemePair { Heartbeat() } }
#Preview("Dot Loader")       { SchemePair { DotLoader() } }
#Preview("Aurora")           { SchemePair { Aurora() } }
#Preview("Token Roll")       { SchemePair { TokenRoll() } }
#Preview("Ripple Tap")       { SchemePair { RippleTap() } }
#Preview("Success Check")    { SchemePair { SuccessCheck() } }
#Preview("Error Shake")      { SchemePair { ErrorShake() } }
#Preview("Badge Pop")        { SchemePair { BadgePop() } }
#Preview("Route Trace")      { SchemePair { RouteTrace() } }
#Preview("Edge Pulse")       { SchemePair { EdgePulse() } }
#Preview("Segmented Loader") { SchemePair { SegmentedLoader() } }
#Preview("Idle Float")       { SchemePair { IdleFloat() } }
#Preview("Ambient Glow")     { SchemePair { AmbientGlow() } }
#Preview("Flip Tile")        { SchemePair { FlipTile() } }
#Preview("Scanline")         { SchemePair { Scanline() } }
#Preview("Orbit Cluster")    { SchemePair { OrbitCluster() } }
#Preview("Elastic Toggle")   { SchemePair { ElasticToggle() } }
#Preview("Broadcast")        { SchemePair { Broadcast() } }
#Preview("Ignition")         { SchemePair { Ignition() } }

#Preview("Progress · states") {
    AndromedaStateMatrix { state in
        ProgressFill(
            value: state == .idle ? 0 : state == .active ? 0.46 : state == .alert ? 0.72 : 1,
            tint: state.tint
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Loader · states") {
    AndromedaStateMatrix { state in
        Group {
            switch state {
            case .idle:   AmbientGlow(tint: state.tint)
            case .active: SpinnerArc(tint: state.tint)
            case .alert:  ErrorShake()
            case .done:   SuccessCheck()
            }
        }
        .andromedaMotion(state.isAnimating)
    }
    .preferredColorScheme(.dark)
}
