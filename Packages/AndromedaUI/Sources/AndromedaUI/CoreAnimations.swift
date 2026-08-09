import SwiftUI

// MARK: - Core primitives
// The eight signals that anchor the Andromeda control plane.

/// Health & liveness — the heartbeat of every status dot.
public struct LivePulse: View {
    public var color: Color
    public var size: CGFloat
    @State private var on = false
    public init(color: Color = .andromedaLive, size: CGFloat = 16) {
        self.color = color; self.size = size
    }
    public var body: some View {
        Circle().fill(color)
            .frame(width: size, height: size)
            .shadow(color: color, radius: on ? 12 : 3)
            .opacity(on ? 0.45 : 1)
            .scaleEffect(on ? 0.92 : 1)
            .animation(Motion.pulse, value: on)
            .onAppear { on = true }
    }
}

/// The core at rest — a slow expanding halo.
public struct BreathingRing: View {
    public var color: Color
    @State private var open = false
    public init(color: Color = .andromedaTeal) { self.color = color }
    public var body: some View {
        Circle().stroke(color, lineWidth: 1.5)
            .frame(width: 46, height: 46)
            .scaleEffect(open ? 1.18 : 0.85)
            .opacity(open ? 0.25 : 0.95)
            .animation(Motion.breathe, value: open)
            .onAppear { open = true }
    }
}

/// A node circling the core — background work in flight.
public struct OrbitingSatellite: View {
    public var radius: CGFloat
    @State private var spin = false
    public init(radius: CGFloat = 26) { self.radius = radius }
    public var body: some View {
        ZStack {
            Circle().fill(Color.andromedaTeal).frame(width: 12, height: 12)
                .shadow(color: .andromedaTeal, radius: 8)
            Circle().fill(Color.andromedaGlow).frame(width: 6, height: 6)
                .shadow(color: .andromedaGlow, radius: 6)
                .offset(y: -radius)
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
        .animation(Motion.orbit, value: spin)
        .onAppear { spin = true }
    }
}

/// Staggered bars for streaming inference or memory recall.
public struct RecallWaveform: View {
    public var bars: Int
    @State private var tall = false
    public init(bars: Int = 5) { self.bars = bars }
    public var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule().fill(Color.andromedaTeal)
                    .frame(width: 4, height: 26)
                    .scaleEffect(y: tall ? 1 : 0.3)
                    .animation(Motion.wave.delay(Double(i) * 0.1), value: tall)
            }
        }
        .onAppear { tall = true }
    }
}

/// A comet-tail arc for scans, syncs, and provider resolution.
public struct ScanSweep: View {
    @State private var spin = false
    public init() {}
    public var body: some View {
        Circle().trim(from: 0, to: 0.28)
            .stroke(
                AngularGradient(colors: [.clear, .andromedaTeal, .andromedaGlow], center: .center),
                style: StrokeStyle(lineWidth: 4, lineCap: .round)
            )
            .frame(width: 44, height: 44)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(Motion.sweep, value: spin)
            .onAppear { spin = true }
    }
}

/// The signature — breathe + orbit + glow stacked into one token.
public struct HUDCore: View {
    public init() {}
    public var body: some View {
        ZStack {
            BreathingRing()
            OrbitingSatellite(radius: 30)
            Circle().fill(Color.andromedaTeal).frame(width: 14, height: 14)
                .shadow(color: .andromedaTeal, radius: 10)
        }
        .frame(width: 62, height: 62)
    }
}

/// Fleet members coming online, phase-offset so the grid shimmers.
public struct FleetConstellation: View {
    public var columns: Int
    @State private var lit = false
    public init(columns: Int = 4) { self.columns = columns }
    public var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(10), spacing: 8), count: columns),
            spacing: 8
        ) {
            ForEach(0..<(columns * columns), id: \.self) { i in
                RoundedRectangle(cornerRadius: 2).fill(Color.andromedaTeal)
                    .frame(width: 8, height: 8)
                    .opacity(lit ? 0.9 : 0.18)
                    .animation(Motion.pulse.delay(Double(i) * 0.06), value: lit)
            }
        }
        .fixedSize()
        .onAppear { lit = true }
    }
}

/// Loading placeholders — a teal sheen crossing redacted rows.
public struct ShimmerSkeleton: View {
    @State private var phase: CGFloat = -1
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.andromedaTeal.opacity(0.12))
                    .frame(width: i == 2 ? 74 : 124, height: 10)
                    .overlay(
                        LinearGradient(colors: [.clear, .andromedaGlow.opacity(0.5), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: 60)
                            .offset(x: phase * 124)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    )
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 2 }
        }
    }
}

// MARK: - Previews

#Preview("LivePulse")          { SchemePair { LivePulse() } }
#Preview("BreathingRing")      { SchemePair { BreathingRing() } }
#Preview("OrbitingSatellite")  { SchemePair { OrbitingSatellite() } }
#Preview("RecallWaveform")     { SchemePair { RecallWaveform() } }
#Preview("ScanSweep")          { SchemePair { ScanSweep() } }
#Preview("HUDCore")            { SchemePair { HUDCore() } }
#Preview("FleetConstellation") { SchemePair { FleetConstellation() } }
#Preview("ShimmerSkeleton")    { SchemePair { ShimmerSkeleton() } }
