// AndromedaDreamMemoryScenes.swift
//
// Porting kit — SwiftUI translations of the web HUD's bespoke, symbol-rich
// Dream + Memory scenes (components/andromeda/hud/dream-memory-visuals.tsx).
// Intended to land in `Sources/AndromedaBrand/HUDMotion/` in the
// Ripnrip/Andromeda repo. Every scene is drawn on the same Andromeda glyph
// geometry as the web version — core (100,60), ring r=26, four cardinal
// cyan nodes, one green accent node, one amber accent node — so Dream and
// Memory read as two expressions of the same organism, exactly matching
// andromeda-lac-theta.vercel.app.
//
// All scenes use SwiftUI Canvas + TimelineView(.animation) for deterministic,
// GPU-light custom drawing. No randomness anywhere — every position and
// phase is a fixed function of index/time, so #Preview and snapshot tests
// render identically on every run. Reduce Motion collapses each scene to a
// calm, legible resting frame per swift-skill's accessibility rules.

import SwiftUI

// MARK: - Shared logical canvas (mirrors the web's viewBox="0 0 200 120")

private enum Glyph {
    static let core = CGPoint(x: 100, y: 60)
    static let ringRadius: CGFloat = 26

    /// (position, color) for the four cardinal + two accent nodes.
    static func nodes(cyan: Color, green: Color, amber: Color) -> [(CGPoint, Color)] {
        [
            (CGPoint(x: 100, y: 18), cyan),
            (CGPoint(x: 100, y: 102), cyan),
            (CGPoint(x: 44, y: 60), cyan),
            (CGPoint(x: 156, y: 60), cyan),
            (CGPoint(x: 140, y: 28), green),
            (CGPoint(x: 60, y: 92), amber),
        ]
    }
}

/// Maps a point in the fixed 200×120 logical space into `rect`, matching the
/// web SVG's `preserveAspectRatio="xMidYMid meet"` (uniform scale, centered).
private func project(_ p: CGPoint, in rect: CGRect) -> CGPoint {
    let scale = min(rect.width / 200, rect.height / 120)
    let w = 200 * scale
    let h = 120 * scale
    let ox = rect.minX + (rect.width - w) / 2
    let oy = rect.minY + (rect.height - h) / 2
    return CGPoint(x: ox + p.x * scale, y: oy + p.y * scale)
}

private func projectedScale(_ rect: CGRect) -> CGFloat { min(rect.width / 200, rect.height / 120) }

// MARK: - 1. DreamField — a crescent moon watches while motes of thought rise

struct AndromedaDreamField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private let motes: [(x: CGFloat, r: CGFloat, delay: Double, drift: CGFloat, accent: Bool)] =
        [18, 42, 66, 92, 118, 150, 176].enumerated().map { i, x in
            (x: x, r: 1.2 + CGFloat(i % 3) * 0.7, delay: (Double(i) * 0.44).truncatingRemainder(dividingBy: 3),
             drift: (i % 2 == 0 ? 1 : -1) * (4 + CGFloat(i % 3) * 3), accent: i % 4 == 0)
        }

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                let scale = projectedScale(rect)
                let t = context.date.timeIntervalSinceReferenceDate

                // ambient halo behind the moon
                let haloCenter = project(CGPoint(x: 150, y: 34), in: rect)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: haloCenter.x - 60 * scale, y: haloCenter.y - 60 * scale, width: 120 * scale, height: 120 * scale)),
                    with: .radialGradient(
                        Gradient(colors: [AndromedaTheme.accent.opacity(0.22), AndromedaTheme.accent.opacity(0)]),
                        center: haloCenter, startRadius: 0, endRadius: 60 * scale
                    )
                )

                // crescent moon: teal disc minus an offset dark disc, plus a slow-breathing ring
                let moonCenter = project(CGPoint(x: 150, y: 34), in: rect)
                let moonR: CGFloat = 15 * scale
                var moon = Path(ellipseIn: CGRect(x: moonCenter.x - moonR, y: moonCenter.y - moonR, width: moonR * 2, height: moonR * 2))
                ctx.fill(moon, with: .color(AndromedaTheme.accent.opacity(0.9)))
                let biteCenter = CGPoint(x: moonCenter.x + 7 * scale, y: moonCenter.y - 4 * scale)
                moon = Path(ellipseIn: CGRect(x: biteCenter.x - moonR, y: biteCenter.y - moonR, width: moonR * 2, height: moonR * 2))
                ctx.fill(moon, with: .color(AndromedaTheme.popover))

                let ringPhase = reduceMotion ? 0.5 : (t.truncatingRemainder(dividingBy: 5)) / 5
                let ringOpacity = reduceMotion ? 0.5 : 0.3 + 0.4 * abs(sin(ringPhase * 2 * .pi))
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: moonCenter.x - moonR, y: moonCenter.y - moonR, width: moonR * 2, height: moonR * 2)),
                    with: .color(AndromedaTheme.accent.opacity(ringOpacity)),
                    lineWidth: 0.6 * scale
                )

                // rising motes
                for m in motes {
                    let period = 5.5
                    let cycle = reduceMotion ? 0.5 : ((t - m.delay).truncatingRemainder(dividingBy: period)) / period
                    let c = max(0, cycle)
                    let y = reduceMotion ? 60.0 : Double(116) - Double(104) * c
                    let x = Double(m.x) + Double(m.drift) * c
                    let opacity = reduceMotion ? 0.5 : sin(c * .pi)
                    let p = project(CGPoint(x: x, y: y), in: rect)
                    let r = m.r * scale
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                        with: .color((m.accent ? AndromedaTheme.signal : AndromedaTheme.primary).opacity(opacity))
                    )
                }

                // fixed twinkling stars (small 4-point sparkles)
                for (i, pt) in [CGPoint(x: 26, y: 26), CGPoint(x: 64, y: 40), CGPoint(x: 110, y: 22)].enumerated() {
                    let period = 2.6
                    let delay = Double(i) * 0.7
                    let phase = reduceMotion ? 0.5 : ((t - delay).truncatingRemainder(dividingBy: period)) / period
                    let c = max(0, phase)
                    let s = (reduceMotion ? 0.9 : 0.7 + 0.4 * sin(c * .pi)) * scale
                    let center = project(pt, in: rect)
                    var star = Path()
                    star.move(to: CGPoint(x: center.x, y: center.y - 3 * s))
                    star.addLine(to: CGPoint(x: center.x + 0.8 * s, y: center.y - 0.8 * s))
                    star.addLine(to: CGPoint(x: center.x + 3 * s, y: center.y))
                    star.addLine(to: CGPoint(x: center.x + 0.8 * s, y: center.y + 0.8 * s))
                    star.addLine(to: CGPoint(x: center.x, y: center.y + 3 * s))
                    star.addLine(to: CGPoint(x: center.x - 0.8 * s, y: center.y + 0.8 * s))
                    star.addLine(to: CGPoint(x: center.x - 3 * s, y: center.y))
                    star.addLine(to: CGPoint(x: center.x - 0.8 * s, y: center.y - 0.8 * s))
                    star.closeSubpath()
                    ctx.fill(star, with: .color(AndromedaTheme.primary.opacity(reduceMotion ? 0.6 : sin(c * .pi))))
                }
            }
            .accessibilityLabel("Dreaming — motes of thought rise past a crescent moon")
        }
    }
}

// MARK: - 2. RemWave — a full EEG array: several dim channels, one predominant

/// Deterministic EEG-style trace: a sum of two fixed sine waves per channel —
/// irregular and organic like a real reading, identical every render.
private func eegPoints(baseline: Double, amp: Double, freqA: Double, freqB: Double, phase: Double, mix: Double) -> [CGPoint] {
    stride(from: 14.0, through: 186.0, by: 4.0).map { x in
        let y = baseline - amp * (0.62 * sin(freqA * x + phase) + 0.38 * sin(freqB * x * 1.7 + phase * 1.3 + mix))
        return CGPoint(x: x, y: y)
    }
}

private struct EEGChannel {
    let baseline: Double
    let amp: Double
    let freqA: Double
    let freqB: Double
    let phase: Double
    let mix: Double
    let duration: Double
    var predominant: Bool = false
}

struct AndromedaRemWave: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let channels: [EEGChannel] = [
        EEGChannel(baseline: 70, amp: 3.5, freqA: 0.09, freqB: 0.05, phase: 0.4, mix: 0.6, duration: 6.2),
        EEGChannel(baseline: 84, amp: 9, freqA: 0.14, freqB: 0.08, phase: 1.1, mix: 1.2, duration: 4.4, predominant: true),
        EEGChannel(baseline: 98, amp: 3, freqA: 0.11, freqB: 0.06, phase: 2.2, mix: 0.3, duration: 5.6),
        EEGChannel(baseline: 110, amp: 2.2, freqA: 0.17, freqB: 0.04, phase: 3.0, mix: 1.8, duration: 7),
    ]

    private func path(for c: EEGChannel, in rect: CGRect) -> Path {
        var p = Path()
        let pts = eegPoints(baseline: c.baseline, amp: c.amp, freqA: c.freqA, freqB: c.freqB, phase: c.phase, mix: c.mix)
            .map { project($0, in: rect) }
        guard let first = pts.first else { return p }
        p.move(to: first)
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        return p
    }

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                let scale = projectedScale(rect)
                let t = context.date.timeIntervalSinceReferenceDate
                guard let lead = channels.first(where: { $0.predominant }) else { return }

                // closed eye with lashes
                var eye = Path()
                let eyeOrigin = CGPoint(x: 100, y: 36)
                eye.move(to: project(CGPoint(x: eyeOrigin.x - 30, y: eyeOrigin.y), in: rect))
                eye.addQuadCurve(
                    to: project(CGPoint(x: eyeOrigin.x + 30, y: eyeOrigin.y), in: rect),
                    control: project(CGPoint(x: eyeOrigin.x, y: eyeOrigin.y + 20), in: rect)
                )
                ctx.stroke(eye, with: .color(AndromedaTheme.accent), lineWidth: 2.5 * scale)
                for (i, x) in [-22.0, -11, 0, 11, 22].enumerated() {
                    let y0 = i == 2 ? 10.0 : 7 + abs(x) * 0.14
                    let start = project(CGPoint(x: eyeOrigin.x + x, y: eyeOrigin.y + y0), in: rect)
                    let end = project(CGPoint(x: eyeOrigin.x + x * 1.05, y: eyeOrigin.y + y0 + 5), in: rect)
                    var lash = Path(); lash.move(to: start); lash.addLine(to: end)
                    ctx.stroke(lash, with: .color(AndromedaTheme.accent.opacity(0.7)), lineWidth: 1.3 * scale)
                }

                // faint monitor grid
                for y in [62.0, 76, 90, 104] {
                    var grid = Path()
                    grid.move(to: project(CGPoint(x: 14, y: y), in: rect))
                    grid.addLine(to: project(CGPoint(x: 186, y: y), in: rect))
                    ctx.stroke(grid, with: .color(AndromedaTheme.border.opacity(0.25)), lineWidth: 0.5 * scale)
                }

                // background channels
                for c in channels where !c.predominant {
                    let phase = reduceMotion ? 0.5 : (t.truncatingRemainder(dividingBy: c.duration)) / c.duration
                    let opacity = reduceMotion ? 0.35 : 0.2 + 0.25 * (1 + sin(phase * 2 * .pi)) / 2
                    ctx.stroke(path(for: c, in: rect), with: .color(AndromedaTheme.accent.opacity(opacity)), lineWidth: 1 * scale)
                }

                // predominant channel: track + bold glowing trace
                ctx.stroke(path(for: lead, in: rect), with: .color(AndromedaTheme.border.opacity(0.4)), lineWidth: 1.5 * scale)
                var leadCtx = ctx
                leadCtx.addFilter(.shadow(color: AndromedaTheme.primary.opacity(0.7), radius: 4 * scale))
                leadCtx.stroke(path(for: lead, in: rect), with: .color(AndromedaTheme.primary), lineWidth: 2.4 * scale)

                // scanning read-head along the predominant baseline
                if !reduceMotion {
                    let period = lead.duration * 1.3
                    let phase = (t.truncatingRemainder(dividingBy: period)) / period
                    // ping-pong 0→1→0 across the trace
                    let ping = phase < 0.5 ? phase * 2 : (1 - phase) * 2
                    let x = 14.0 + (186.0 - 14.0) * ping
                    let head = project(CGPoint(x: x, y: lead.baseline), in: rect)
                    let r: CGFloat = 2.6 * scale
                    var headCtx = ctx
                    headCtx.addFilter(.shadow(color: AndromedaTheme.signal.opacity(0.8), radius: 4 * scale))
                    headCtx.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)), with: .color(AndromedaTheme.signal))
                }
            }
            .accessibilityLabel("Reflecting — an EEG array scans beneath a closed eye, one trace dominant")
        }
    }
}

// MARK: - 3. BraidMerge — two memory threads braid into a single summit star

struct AndromedaBraidMerge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                let scale = projectedScale(rect)
                let t = context.date.timeIntervalSinceReferenceDate
                let core = project(Glyph.core, in: rect)

                // faint forming glyph ring, slowly rotating
                let ringPhase = reduceMotion ? 0 : (t.truncatingRemainder(dividingBy: 20)) / 20
                var ring = Path(ellipseIn: CGRect(x: core.x - 24 * scale, y: core.y - 24 * scale, width: 48 * scale, height: 48 * scale))
                ring = ring.applying(CGAffineTransform(rotationAngle: reduceMotion ? 0 : ringPhase * 2 * .pi))
                let opPhase = reduceMotion ? 0.4 : 0.15 + 0.35 * abs(sin((t.truncatingRemainder(dividingBy: 4)) / 4 * 2 * .pi))
                ctx.stroke(ring, with: .color(AndromedaTheme.accent.opacity(opPhase)), style: StrokeStyle(lineWidth: 1 * scale, dash: [3 * scale, 5 * scale]))

                // four braiding threads converging on the core
                let threads: [(from: CGPoint, control: CGPoint, color: Color)] = [
                    (CGPoint(x: 20, y: 30), CGPoint(x: 70, y: 40), AndromedaTheme.primary),
                    (CGPoint(x: 20, y: 90), CGPoint(x: 70, y: 80), AndromedaTheme.signal),
                    (CGPoint(x: 180, y: 30), CGPoint(x: 130, y: 40), AndromedaTheme.accent),
                    (CGPoint(x: 180, y: 90), CGPoint(x: 130, y: 80), AndromedaTheme.partial),
                ]
                for t2 in threads {
                    let period = 2.4
                    let phase = reduceMotion ? 1.0 : (t.truncatingRemainder(dividingBy: period)) / period
                    var p = Path()
                    p.move(to: project(t2.from, in: rect))
                    p.addQuadCurve(to: core, control: project(t2.control, in: rect))
                    ctx.stroke(
                        p.trimmedPath(from: 0, to: max(0.05, phase)),
                        with: .color(t2.color.opacity(reduceMotion ? 0.8 : 0.4 + 0.4 * phase)),
                        lineWidth: 2 * scale
                    )
                }

                // resolved summit star (4-point sparkle) at the core
                let starPhase = reduceMotion ? 1.0 : 0.5 + 0.5 * abs(sin((t.truncatingRemainder(dividingBy: 2.4)) / 2.4 * 2 * .pi))
                let s = (9 * scale) * CGFloat(reduceMotion ? 1 : 0.85 + 0.3 * starPhase)
                var star = Path()
                star.move(to: CGPoint(x: core.x, y: core.y - s))
                star.addLine(to: CGPoint(x: core.x + s * 0.36, y: core.y - s * 0.36))
                star.addLine(to: CGPoint(x: core.x + s, y: core.y))
                star.addLine(to: CGPoint(x: core.x + s * 0.36, y: core.y + s * 0.36))
                star.addLine(to: CGPoint(x: core.x, y: core.y + s))
                star.addLine(to: CGPoint(x: core.x - s * 0.36, y: core.y + s * 0.36))
                star.addLine(to: CGPoint(x: core.x - s, y: core.y))
                star.addLine(to: CGPoint(x: core.x - s * 0.36, y: core.y - s * 0.36))
                star.closeSubpath()
                var starCtx = ctx
                starCtx.addFilter(.shadow(color: AndromedaTheme.primary.opacity(0.8), radius: 5 * scale))
                starCtx.fill(star, with: .color(AndromedaTheme.primary.opacity(reduceMotion ? 1 : 0.5 + 0.5 * starPhase)))
            }
            .accessibilityLabel("Consolidating — two memory threads braid into one")
        }
    }
}

// MARK: - 4. EngramTimeline — beads of experience laid down left to right

struct AndromedaEngramTimeline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let beads: [Double] = [24, 52, 80, 108, 136, 164]

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                let scale = projectedScale(rect)
                let t = context.date.timeIntervalSinceReferenceDate

                var track = Path()
                track.move(to: project(CGPoint(x: 14, y: 60), in: rect))
                track.addLine(to: project(CGPoint(x: 186, y: 60), in: rect))
                ctx.stroke(track, with: .color(AndromedaTheme.border), lineWidth: 1.5 * scale)

                let fillPhase = reduceMotion ? 1.0 : min(1, (t.truncatingRemainder(dividingBy: 4)) / 4 * 1.3)
                ctx.stroke(track.trimmedPath(from: 0, to: fillPhase), with: .color(AndromedaTheme.primary), lineWidth: 1.5 * scale)

                for (i, x) in beads.enumerated() {
                    let period = 0.6
                    let cycle = 3.4 + period
                    let delay = Double(i) * 0.5
                    let phase = reduceMotion ? 1.0 : max(0, min(1, ((t - delay).truncatingRemainder(dividingBy: cycle)) / period))
                    let center = project(CGPoint(x: x, y: 60), in: rect)
                    let r = (5.5 * scale) * (reduceMotion ? 1 : CGFloat(0.2 + 0.8 * sin(phase * .pi / 2)))
                    let color = i == beads.count - 1 ? AndromedaTheme.signal : AndromedaTheme.primary
                    ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(color))

                    // connecting tick + label dot above each bead
                    let tickTop = project(CGPoint(x: x, y: 46), in: rect)
                    let tickBottom = project(CGPoint(x: x, y: 54.5), in: rect)
                    var tick = Path(); tick.move(to: tickBottom); tick.addLine(to: tickTop)
                    ctx.stroke(tick, with: .color(AndromedaTheme.primary.opacity(0.4)), lineWidth: 0.8 * scale)
                    let dot = project(CGPoint(x: x, y: 46), in: rect)
                    let dr = 1.5 * scale
                    ctx.fill(Path(ellipseIn: CGRect(x: dot.x - dr, y: dot.y - dr, width: dr * 2, height: dr * 2)), with: .color(AndromedaTheme.primary.opacity(0.5)))
                }
            }
            .accessibilityLabel("Episodic memory — beads laid down along a timeline")
        }
    }
}

// MARK: - 5. ConstellationGraph — edges draw and nodes ignite into meaning

struct AndromedaConstellationGraph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                let scale = projectedScale(rect)
                let t = context.date.timeIntervalSinceReferenceDate
                let core = project(Glyph.core, in: rect)
                let nodes = Glyph.nodes(cyan: AndromedaTheme.primary, green: AndromedaTheme.signal, amber: AndromedaTheme.partial)

                for (i, node) in nodes.enumerated() {
                    let period = 1.1, cycle = period + 2.6
                    let delay = Double(i) * 0.16
                    let phase = reduceMotion ? 1.0 : max(0, min(1, ((t - delay).truncatingRemainder(dividingBy: cycle)) / period))
                    var edge = Path()
                    edge.move(to: core)
                    edge.addLine(to: project(node.0, in: rect))
                    ctx.stroke(edge.trimmedPath(from: 0, to: max(0.02, phase)), with: .color(node.1.opacity(0.55)), lineWidth: 1.2 * scale)
                }

                let breathPhase = reduceMotion ? 0.5 : (t.truncatingRemainder(dividingBy: 3)) / 3
                let ringR = (12 * scale) * CGFloat(reduceMotion ? 1 : 0.92 + 0.16 * sin(breathPhase * 2 * .pi))
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: core.x - ringR, y: core.y - ringR, width: ringR * 2, height: ringR * 2)),
                    with: .color(AndromedaTheme.primary.opacity(reduceMotion ? 0.7 : 0.5 + 0.5 * sin(breathPhase * 2 * .pi))),
                    lineWidth: 1.5 * scale
                )
                let coreR = 4.5 * scale
                var coreCtx = ctx
                coreCtx.addFilter(.shadow(color: AndromedaTheme.primary.opacity(0.7), radius: 5 * scale))
                coreCtx.fill(Path(ellipseIn: CGRect(x: core.x - coreR, y: core.y - coreR, width: coreR * 2, height: coreR * 2)), with: .color(AndromedaTheme.primary))

                for (i, node) in nodes.enumerated() {
                    let period = 0.7, cycle = period + 3.0
                    let delay = 0.4 + Double(i) * 0.16
                    let phase = reduceMotion ? 1.0 : max(0, min(1, ((t - delay).truncatingRemainder(dividingBy: cycle)) / period))
                    let p = project(node.0, in: rect)
                    let r = (5 * scale) * CGFloat(reduceMotion ? 1 : sin(phase * .pi / 2))
                    var nodeCtx = ctx
                    nodeCtx.addFilter(.shadow(color: node.1.opacity(0.6), radius: 4 * scale))
                    nodeCtx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(node.1))
                }
            }
            .accessibilityLabel("Semantic memory — a knowledge graph lights into a constellation")
        }
    }
}

// MARK: - 6. CrystalForm — particles converge and lock into a faceted crystal

struct AndromedaCrystalForm: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let particles: [(x: Double, y: Double, accent: Bool, delay: Double)] = (0..<8).map { i in
        let a = Double(i) / 8 * .pi * 2
        return (x: 100 + cos(a) * 78, y: 60 + sin(a) * 44, accent: i % 3 == 0, delay: Double(i) * 0.12)
    }

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                let scale = projectedScale(rect)
                let t = context.date.timeIntervalSinceReferenceDate
                let core = project(Glyph.core, in: rect)

                if !reduceMotion {
                    for p in particles {
                        let period = 2.2, cycle = period + 1.2
                        let phase = max(0, ((t - p.delay).truncatingRemainder(dividingBy: cycle)) / period)
                        guard phase <= 1 else { continue }
                        let start = project(CGPoint(x: p.x, y: p.y), in: rect)
                        let x = start.x + (core.x - start.x) * phase
                        let y = start.y + (core.y - start.y) * phase
                        let r: CGFloat = 2 * scale
                        let opacity = sin(phase * .pi)
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color((p.accent ? AndromedaTheme.signal : AndromedaTheme.primary).opacity(opacity)))
                    }
                }

                let crystalPhase = reduceMotion ? 1.0 : {
                    let cycle = 3.4
                    let phase = (t.truncatingRemainder(dividingBy: cycle)) / cycle
                    if phase < 0.5 { return 0.0 }
                    if phase < 0.7 { return (phase - 0.5) / 0.2 }
                    return 1.0
                }()

                func gp(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: core.x + x * scale, y: core.y + y * scale) }
                var gem = Path()
                gem.move(to: gp(0, -20)); gem.addLine(to: gp(16, -6)); gem.addLine(to: gp(10, 18))
                gem.addLine(to: gp(-10, 18)); gem.addLine(to: gp(-16, -6)); gem.closeSubpath()
                ctx.fill(gem, with: .color(AndromedaTheme.accent.opacity(0.14 * crystalPhase)))
                var gemCtx = ctx
                gemCtx.addFilter(.shadow(color: AndromedaTheme.primary.opacity(0.6 * crystalPhase), radius: 5 * scale))
                gemCtx.stroke(gem, with: .color(AndromedaTheme.primary.opacity(crystalPhase)), lineWidth: 1.6 * scale)

                var facets = Path()
                facets.move(to: gp(0, -20)); facets.addLine(to: gp(0, 18))
                facets.move(to: gp(-16, -6)); facets.addLine(to: gp(16, -6))
                facets.move(to: gp(0, -20)); facets.addLine(to: gp(-10, 18))
                facets.move(to: gp(0, -20)); facets.addLine(to: gp(10, 18))
                ctx.stroke(facets, with: .color(AndromedaTheme.primary.opacity(0.5 * crystalPhase)), lineWidth: 0.8 * scale)

                if !reduceMotion {
                    let glintCycle = 2.8 + 0.6
                    let glintPhase = max(0, min(1, (t.truncatingRemainder(dividingBy: glintCycle)) / 0.6))
                    var glint = Path()
                    glint.move(to: gp(-8, -10)); glint.addLine(to: gp(-4, -14))
                    ctx.stroke(glint, with: .color(AndromedaTheme.foreground.opacity(sin(glintPhase * .pi))), style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round))
                }
            }
            .accessibilityLabel("Crystallizing — particles lock into a memory crystal")
        }
    }
}

// MARK: - 7. RecallPulse — a search pulse retrieves the answer node

struct AndromedaRecallPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                let scale = projectedScale(rect)
                let t = context.date.timeIntervalSinceReferenceDate
                let core = project(Glyph.core, in: rect)
                let target = project(CGPoint(x: 156, y: 60), in: rect)
                let nodes = Glyph.nodes(cyan: AndromedaTheme.primary, green: AndromedaTheme.signal, amber: AndromedaTheme.partial)

                for node in nodes {
                    var edge = Path(); edge.move(to: core); edge.addLine(to: project(node.0, in: rect))
                    ctx.stroke(edge, with: .color(AndromedaTheme.border.opacity(0.4)), lineWidth: 1 * scale)
                }
                for node in nodes {
                    let p = project(node.0, in: rect)
                    let r = 4 * scale
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(AndromedaTheme.mutedForeground.opacity(0.4)))
                }

                if !reduceMotion {
                    for i in 0..<2 {
                        let period = 2.4
                        let delay = Double(i) * 1.2
                        let phase = max(0, ((t - delay).truncatingRemainder(dividingBy: period)) / period)
                        let r = (4 + 66 * phase) * scale
                        ctx.stroke(
                            Path(ellipseIn: CGRect(x: core.x - r, y: core.y - r, width: r * 2, height: r * 2)),
                            with: .color(AndromedaTheme.primary.opacity(0.6 * (1 - phase))),
                            lineWidth: 1.2 * scale
                        )
                    }
                }

                let coreR = 5 * scale
                var coreCtx = ctx
                coreCtx.addFilter(.shadow(color: AndromedaTheme.primary.opacity(0.6), radius: 5 * scale))
                coreCtx.fill(Path(ellipseIn: CGRect(x: core.x - coreR, y: core.y - coreR, width: coreR * 2, height: coreR * 2)), with: .color(AndromedaTheme.primary))

                let answerPhase = reduceMotion ? 1.0 : {
                    let period = 2.4, delay = 1.0
                    let raw = (t - delay).truncatingRemainder(dividingBy: period) / period
                    return max(0, raw)
                }()
                let answerR = (6 * scale) * CGFloat(reduceMotion ? 1 : 1 + 0.5 * sin(answerPhase * .pi))
                var answerCtx = ctx
                answerCtx.addFilter(.shadow(color: AndromedaTheme.signal.opacity(0.7), radius: 6 * scale))
                answerCtx.fill(
                    Path(ellipseIn: CGRect(x: target.x - answerR, y: target.y - answerR, width: answerR * 2, height: answerR * 2)),
                    with: .color(AndromedaTheme.signal.opacity(reduceMotion ? 1 : 0.4 + 0.6 * abs(sin(answerPhase * .pi))))
                )

                if !reduceMotion {
                    let cycle = 1.0 + 1.4, delay = 1.3
                    let phase = max(0, min(1, ((t - delay).truncatingRemainder(dividingBy: cycle)) / 1.0))
                    let x = target.x + (core.x - target.x) * phase
                    let y = target.y + (core.y - target.y) * phase
                    let r: CGFloat = 2.4 * scale
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(AndromedaTheme.signal.opacity(sin(phase * .pi))))
                }
            }
            .accessibilityLabel("Recall — a pulse retrieves the answer node")
        }
    }
}

// MARK: - Previews (one per scene, per swift-skill's #Preview-per-state rule)

#Preview("Dream Field") { AndromedaDreamField().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("REM Wave (EEG)") { AndromedaRemWave().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("Braid Merge") { AndromedaBraidMerge().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("Engram Timeline") { AndromedaEngramTimeline().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("Constellation Graph") { AndromedaConstellationGraph().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("Crystal Form") { AndromedaCrystalForm().frame(width: 240, height: 144).background(AndromedaTheme.card) }
#Preview("Recall Pulse") { AndromedaRecallPulse().frame(width: 240, height: 144).background(AndromedaTheme.card) }
