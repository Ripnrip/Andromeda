// AndromedaHUDMotion.swift
//
// Porting kit — SwiftUI translations of the web HUD's reusable animation
// primitives (components/andromeda/hud/animations.tsx). Intended to land in
// `Sources/AndromedaBrand/HUDMotion/` in the Ripnrip/Andromeda repo, alongside
// AndromedaTheme, AndromedaPalette, and AndromedaChrome. Do not invent a
// second theme — every color here comes from AndromedaTheme (see the
// andromeda-ui skill) so this always matches andromeda-lac-theta.vercel.app.
//
// Conventions (swift-skill): Swift 6 strict concurrency, SwiftUI-first,
// @MainActor for UI state, Sendable value types, Reduce Motion honored on
// every primitive, all continuous motion driven by TimelineView(.animation)
// rather than ad-hoc Timers so previews and screenshots stay deterministic.

import SwiftUI

// MARK: - Reduce Motion helper

@MainActor
private struct MotionEnvironment {
    static func phase(_ context: TimelineViewDefaultContext, reduceMotion: Bool, period: Double) -> Double {
        guard !reduceMotion else { return 0 }
        let t = context.date.timeIntervalSinceReferenceDate
        return (t.truncatingRemainder(dividingBy: period)) / period
    }
}

// MARK: - 1. Waveform — vertical bars breathing at staggered phases

struct AndromedaWaveform: View {
    var bars: Int = 4
    var color: Color = AndromedaTheme.primary
    var height: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<bars, id: \.self) { i in
                    let phase = MotionEnvironment.phase(context, reduceMotion: reduceMotion, period: 0.9)
                    let scale = reduceMotion ? 0.55 : 0.25 + 0.75 * abs(sin(phase * 2 * .pi + Double(i) * 0.7))
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: height * scale)
                }
            }
            .frame(height: height)
        }
    }
}

// MARK: - 2. ShimmerSweep — diagonal highlight sweeping across a surface

struct AndromedaShimmerSweep: View {
    var color: Color = AndromedaTheme.primary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                let phase = MotionEnvironment.phase(context, reduceMotion: reduceMotion, period: 2.2)
                let x = reduceMotion ? geo.size.width * 0.5 : geo.size.width * (phase * 1.6 - 0.3)
                LinearGradient(
                    colors: [color.opacity(0), color.opacity(0.35), color.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.4)
                .rotationEffect(.degrees(20))
                .offset(x: x)
                .blendMode(.plusLighter)
            }
            .clipped()
        }
    }
}

// MARK: - 3. OrbitDots — satellites revolving around a still center

struct AndromedaOrbitDots: View {
    var size: CGFloat = 24
    var dots: Int = 3
    var color: Color = AndromedaTheme.primary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let phase = MotionEnvironment.phase(context, reduceMotion: reduceMotion, period: 3.0)
            let angleBase = reduceMotion ? 0 : phase * 2 * .pi
            ZStack {
                Circle().fill(color).frame(width: 4, height: 4)
                ForEach(0..<dots, id: \.self) { i in
                    let a = angleBase + (2 * .pi / Double(dots)) * Double(i)
                    Circle()
                        .fill(color.opacity(0.85))
                        .frame(width: 3.2, height: 3.2)
                        .offset(x: cos(a) * size / 2.4, y: sin(a) * size / 2.4)
                }
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - 4. ParticleDrift — motes rising with per-particle drift and delay

struct AndromedaParticleDrift: View {
    var count: Int = 7
    var color: Color = AndromedaTheme.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Deterministic seeds — mirrors the web's post-mount Math.random() seed
    /// generation, but computed once from fixed constants so SwiftUI
    /// previews and snapshot tests stay stable across runs.
    private var seeds: [(x: CGFloat, delay: Double, dur: Double, size: CGFloat)] {
        (0..<count).map { i in
            let f = Double(i)
            return (
                x: CGFloat((f * 37).truncatingRemainder(dividingBy: 100)) / 100,
                delay: (f * 0.44).truncatingRemainder(dividingBy: 2.5),
                dur: 3 + (f * 0.9).truncatingRemainder(dividingBy: 2.5),
                size: 1.5 + (f * 0.6).truncatingRemainder(dividingBy: 2)
            )
        }
    }

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                let t = context.date.timeIntervalSinceReferenceDate
                ForEach(Array(seeds.enumerated()), id: \.offset) { _, s in
                    let cycle = reduceMotion ? 0.5 : ((t - s.delay).truncatingRemainder(dividingBy: s.dur)) / s.dur
                    let clamped = max(0, cycle)
                    let y = geo.size.height * (1 - clamped)
                    let opacity = reduceMotion ? 0.5 : sin(clamped * .pi)
                    Circle()
                        .fill(color)
                        .frame(width: s.size, height: s.size)
                        .position(x: geo.size.width * s.x, y: y)
                        .opacity(opacity)
                }
            }
        }
    }
}

// MARK: - 5. BreathingGlow — a slow, calm pulse behind an icon or pill

struct AndromedaBreathingGlow: View {
    var color: Color = AndromedaTheme.accent
    var intensity: Double = 0.7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let phase = MotionEnvironment.phase(context, reduceMotion: reduceMotion, period: 3.0)
            let s = reduceMotion ? 1.0 : 0.9 + 0.25 * sin(phase * 2 * .pi)
            let o = reduceMotion ? intensity * 0.6 : intensity * (0.4 + 0.6 * sin(phase * 2 * .pi))
            Circle()
                .fill(color.opacity(o))
                .scaleEffect(s)
                .blur(radius: 6)
        }
    }
}

// MARK: - 6. RippleRings — concentric rings expanding outward, staggered

struct AndromedaRippleRings: View {
    var color: Color = AndromedaTheme.signal
    var rings: Int = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<rings, id: \.self) { i in
                    let period = 2.0
                    let delay = Double(i) * (period / Double(rings))
                    let phase = reduceMotion ? 0.4 : ((t - delay).truncatingRemainder(dividingBy: period)) / period
                    let clamped = max(0, phase)
                    Circle()
                        .strokeBorder(color, lineWidth: 1.4)
                        .scaleEffect(0.3 + clamped * 1.4)
                        .opacity(reduceMotion ? 0.5 : (1 - clamped))
                }
            }
        }
    }
}

// MARK: - 7. MarchingSignal — sequential pulses along a line, like packets

struct AndromedaMarchingSignal: View {
    var count: Int = 3
    var color: Color = AndromedaTheme.primary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { i in
                    let period = 1.6
                    let delay = Double(i) * 0.2
                    let phase = reduceMotion ? 0.5 : ((t - delay).truncatingRemainder(dividingBy: period)) / period
                    let clamped = max(0, phase)
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                        .opacity(reduceMotion ? 0.6 : sin(clamped * .pi))
                }
            }
        }
    }
}

// MARK: - 8. RotatingRing — a dashed ring in slow, constant rotation

struct AndromedaRotatingRing: View {
    var color: Color = AndromedaTheme.accent
    var lineWidth: CGFloat = 1.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let phase = MotionEnvironment.phase(context, reduceMotion: reduceMotion, period: 6.0)
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: lineWidth, dash: [3, 5]))
                .foregroundStyle(color)
                .rotationEffect(.degrees(reduceMotion ? 0 : phase * 360))
        }
    }
}

// MARK: - 9. VectorGrid — a lattice that lights up in a nearest-neighbor sweep

struct AndromedaVectorGrid: View {
    var cols: Int = 5
    var rows: Int = 3
    var color: Color = AndromedaTheme.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            VStack(spacing: 3) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 3) {
                        ForEach(0..<cols, id: \.self) { c in
                            let period = 1.6
                            let delay = Double(c + r) * 0.11
                            let phase = reduceMotion ? 0.5 : ((t - delay).truncatingRemainder(dividingBy: period)) / period
                            let clamped = max(0, phase)
                            let o = reduceMotion ? 0.35 : 0.18 + 0.82 * abs(sin(clamped * .pi))
                            RoundedRectangle(cornerRadius: 1)
                                .fill(color.opacity(o))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 10. TokenStream — mono blocks streaming in like decoded tokens

struct AndromedaTokenStream: View {
    var count: Int = 5
    var color: Color = AndromedaTheme.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    let period = 1.5
                    let delay = Double(i) * 0.16
                    let phase = reduceMotion ? 0.5 : ((t - delay).truncatingRemainder(dividingBy: period)) / period
                    let clamped = max(0, phase)
                    let width: CGFloat = 4 + CGFloat(i % 3) * 3
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: width, height: 8)
                        .opacity(reduceMotion ? 0.6 : sin(clamped * .pi))
                        .offset(y: reduceMotion ? 0 : (1 - sin(clamped * .pi)) * 3)
                }
            }
        }
    }
}

// MARK: - 11. TypeStream — text revealed word-by-word, like a thought forming

struct AndromedaTypeStream: View {
    var text: String
    var speedPerWord: Double = 0.4
    var font: Font = AndromedaTheme.Font.serifItalic(size: 12)
    var color: Color = AndromedaTheme.foreground

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var words: [String] { text.split(separator: " ").map(String.init) }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let total = Double(words.count) * speedPerWord
            let elapsed = reduceMotion ? total : t.truncatingRemainder(dividingBy: total + 1.2)
            let shown = max(0, min(words.count, Int(elapsed / speedPerWord) + 1))
            Text(words.prefix(shown).joined(separator: " "))
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - 12. ElasticPop — a spring-in emphasis for a badge or icon on arrival

struct AndromedaElasticPop<Content: View>: View {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .scaleEffect(appeared ? 1 : 0.4)
            .opacity(appeared ? 1 : 0)
            .task {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                        appeared = true
                    }
                }
            }
    }
}

// MARK: - 13. CountUp — animates an integer counting up to a target value

struct AndromedaCountUp: View {
    var target: Int
    var duration: Double = 1.2
    var font: Font = AndromedaTheme.Font.mono(size: 13)
    var color: Color = AndromedaTheme.foreground

    @State private var startDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let progress = reduceMotion ? 1 : min(1, elapsed / duration)
            let value = Int(Double(target) * progress)
            Text("\(value)")
                .font(font)
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

// MARK: - 14. ProgressFill — a bar that fills, holds, then loops

struct AndromedaProgressFill: View {
    var color: Color = AndromedaTheme.primary
    var trackColor: Color = AndromedaTheme.border

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let phase = MotionEnvironment.phase(context, reduceMotion: reduceMotion, period: 2.4)
            let fill = reduceMotion ? 0.65 : min(1, phase * 1.3)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(trackColor)
                    Capsule().fill(color).frame(width: geo.size.width * fill)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Previews (one per primitive, per swift-skill's #Preview-per-state rule)

#Preview("Waveform")       { AndromedaWaveform().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("ShimmerSweep")   { AndromedaShimmerSweep().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("OrbitDots")      { AndromedaOrbitDots().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("ParticleDrift")  { AndromedaParticleDrift().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("BreathingGlow")  { AndromedaBreathingGlow().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("RippleRings")    { AndromedaRippleRings().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("MarchingSignal") { AndromedaMarchingSignal().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("RotatingRing")   { AndromedaRotatingRing().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("VectorGrid")     { AndromedaVectorGrid().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("TokenStream")    { AndromedaTokenStream().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("TypeStream")     { AndromedaTypeStream(text: "a thought forms word by word").frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("ElasticPop") {
    AndromedaElasticPop {
        Text("NEW")
            .font(AndromedaTheme.Font.mono(size: 11))
            .foregroundStyle(AndromedaTheme.foreground)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(AndromedaTheme.accent.opacity(0.18), in: Capsule())
    }
    .frame(width: 240, height: 144).background(AndromedaTheme.card)
}
#Preview("CountUp")        { AndromedaCountUp(target: 128).frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("ProgressFill")   { AndromedaProgressFill().frame(width: 240, height: 144).background(AndromedaTheme.card) }
