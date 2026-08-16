import SwiftUI

// MARK: - Dreaming
// One clock drives the whole scene: `TimelineView(.animation)` hands a date to
// every layer, and each layer is a pure function of that time. Nothing here
// holds animation state, so the card can be snapshotted at any instant.

/// The six-channel montage. Every band scrolls at its own rate; the band that
/// leads the current dream state is taller, brighter, and tagged.
public struct EEGMontage: View {
    public var lead: EEGBand
    public var accent: Color
    public var muted: Bool
    public var time: TimeInterval

    public init(lead: EEGBand, accent: Color, muted: Bool = false, time: TimeInterval) {
        self.lead = lead; self.accent = accent; self.muted = muted; self.time = time
    }

    private let labelWidth: CGFloat = 26
    private let tagWidth: CGFloat = 96
    private let leadHeight: CGFloat = 26
    private let trailHeight: CGFloat = 13
    private let gap: CGFloat = 2

    public var body: some View {
        Canvas { ctx, size in
            let trackX = labelWidth + 8
            let trackW = max(10, size.width - labelWidth - tagWidth - 16)
            var y: CGFloat = 0

            for band in EEGBand.allCases {
                let isLead = band == lead
                let h = isLead ? leadHeight : trailHeight
                let mid = y + h / 2
                let amp = (h / 2) * (isLead ? 0.86 : 0.62)
                let phase = time * (isLead ? band.leadRate : band.trailRate)

                var path = Path()
                var x: CGFloat = 0
                while x <= trackW {
                    let u = Double(x / trackW) * 0.5 + phase
                    let p = CGPoint(x: trackX + x, y: mid - CGFloat(band.value(at: u)) * amp)
                    x == 0 ? path.move(to: p) : path.addLine(to: p)
                    x += 2
                }

                let tint = isLead ? accent : Color.andromedaTeal.opacity(0.34)
                ctx.stroke(
                    path,
                    with: .color(tint.opacity(isLead ? (muted ? 0.6 : 0.95) : 0.3)),
                    style: StrokeStyle(lineWidth: isLead ? 1.6 : 0.9, lineCap: .round, lineJoin: .round)
                )

                let symbol = Text(band.symbol)
                    .font(AndromedaFont.mono(isLead ? 11 : 9.5))
                    .foregroundStyle(isLead ? (muted ? Color.andromedaInk : Color.andromedaDreamLucid)
                                            : Color.andromedaDim)
                ctx.draw(ctx.resolve(symbol), at: CGPoint(x: 0, y: mid), anchor: .leading)

                if isLead {
                    let tag = Text(band.tag).font(AndromedaFont.mono(8)).foregroundStyle(accent)
                    ctx.draw(ctx.resolve(tag), at: CGPoint(x: size.width, y: mid), anchor: .trailing)
                }

                y += h + gap
            }
        }
        .frame(height: leadHeight + trailHeight * 5 + gap * 5)
        .animation(.easeInOut(duration: 0.55), value: lead)
        .accessibilityLabel("EEG montage, \(lead.symbol) dominant, \(lead.tag)")
    }
}

/// Drifting motes — the visual temperature of the dream, still when awake.
public struct DreamMoteField: View {
    public var accent: Color
    public var awake: Bool
    public var slow: Bool
    public var time: TimeInterval

    public init(accent: Color, awake: Bool, slow: Bool = false, time: TimeInterval) {
        self.accent = accent; self.awake = awake; self.slow = slow; self.time = time
    }

    public var body: some View {
        Canvas { ctx, size in
            let period = slow ? 8.0 : 5.2
            for i in 0..<14 {
                let seedX = Double((i * 13) % 88) / 100 + 0.06
                let seedY = Double((i * 29) % 70) / 100 + 0.18
                let r = CGFloat(2 + i % 3)
                var x = seedX * size.width
                var y = seedY * size.height
                var alpha = 0.18

                if !awake {
                    let p = ((time / period) + Double(i) * 0.14).truncatingRemainder(dividingBy: 1)
                    let dx = Double((i % 2 == 0) ? 1 : -1) * (12 + Double(i) * 3)
                    x += dx * p
                    y -= (18 + Double(i % 4) * 10) * p
                    alpha = p < 0.45 ? (0.12 + p * 1.5) : (0.8 * (1 - (p - 0.45) / 0.55))
                }

                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(accent.opacity(max(0, alpha))))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The fragment row: captured, loosening, merging, dissolving, or replayed.
public struct DreamFragmentRow: View {
    public var state: DreamState
    public var accent: Color
    public var time: TimeInterval

    public init(state: DreamState, accent: Color, time: TimeInterval) {
        self.state = state; self.accent = accent; self.time = time
    }

    public var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(state.fragments.enumerated()), id: \.element.id) { i, fragment in
                chip(fragment, index: i)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func chip(_ fragment: DreamFragment, index: Int) -> some View {
        let base = Text(fragment.name)
            .font(AndromedaFont.mono(9.5))
            .foregroundStyle(Color.andromedaInk)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(accent.opacity(0.35)))

        switch fragment.treatment {
        case .captured:
            base.opacity(0.6)
        case .loose:
            base.opacity(0.35 + 0.6 * flicker(offset: Double(index) * 0.3, period: 2.4 + Double(index) * 0.5))
        case .merging:
            let p = cycle(3.2)
            let travel = min(1, p / 0.55)
            base
                .offset(x: (index == 0 ? 38 : -38) * travel)
                .opacity(p > 0.7 ? 0 : 1)
        case .pruning:
            let p = cycle(2.2, offset: Double(index) * 0.5)
            base
                .opacity(1 - p)
                .blur(radius: 3 * p)
                .tracking(2 * p)
        case .replaying:
            let b = 0.85 + 0.15 * sin(time * 2.6)
            base
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(accent))
                .shadow(color: accent.opacity(0.6), radius: 12 * b)
                .scaleEffect(b)
        }
    }

    private func cycle(_ period: Double, offset: Double = 0) -> Double {
        ((time + offset) / period).truncatingRemainder(dividingBy: 1)
    }
    private func flicker(offset: Double, period: Double) -> Double {
        0.5 + 0.5 * sin((time + offset) / period * .pi * 2)
    }
}

/// The full Dreaming stage.
public struct DreamingScene: View {
    public var state: DreamState
    public init(state: DreamState) { self.state = state }

    public var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            body(at: t)
        }
    }

    @ViewBuilder
    private func body(at t: TimeInterval) -> some View {
        let accent = state.accent
        let awake = state == .awake

        ZStack(alignment: .top) {
            DreamMoteField(accent: awake ? Color.andromedaTeal.opacity(0.3) : accent,
                           awake: awake, slow: state == .deep, time: t)

            if state == .lucid {
                LucidScanline(accent: accent, time: t)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    PillarLog(state.log, tint: awake ? Color.andromedaMuted : Color.andromedaDreamLucid,
                              typing: state == .hypnagogic || state == .lucid)
                    Text(state.clock)
                        .font(AndromedaFont.mono(9))
                        .foregroundStyle(Color.andromedaDim)
                        .fixedSize()
                }

                DreamFragmentRow(state: state, accent: accent, time: t)
                    .frame(height: 28)
                    .padding(.top, 10)

                Group {
                    if let event = state.event {
                        Text(event)
                            .font(AndromedaFont.mono(9.5))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(accent))
                            .scaleEffect(state == .rem ? sealScale(t) : 1)
                    }
                }
                .frame(height: 24, alignment: .center)
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(state.ledger) { line in
                        Text(line.text)
                            .font(AndromedaFont.mono(8.5))
                            .foregroundStyle(awake && line.status != .pending
                                             ? Color.andromedaMuted : line.tint)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 5)

                Spacer(minLength: 6)

                EEGMontage(lead: state.leadBand, accent: accent, muted: awake, time: t)
                    .hueDrift(14, period: 5, active: state == .rem)

                ConsolidationMeter(progress: state.consolidation, accent: accent)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
    }

    /// REM's merge badge lands with a spring each cycle.
    private func sealScale(_ t: TimeInterval) -> CGFloat {
        let p = (t / 3.2).truncatingRemainder(dividingBy: 1)
        guard p > 0.6 else { return 1.5 }
        let k = (p - 0.6) / 0.4
        return 1.5 - 0.55 * CGFloat(k) + 0.05 * CGFloat(sin(k * .pi))
    }
}

/// The lucid cursor — a slow bar of light crossing the stage.
public struct LucidScanline: View {
    public var accent: Color
    public var time: TimeInterval
    public init(accent: Color, time: TimeInterval) { self.accent = accent; self.time = time }

    public var body: some View {
        GeometryReader { geo in
            let p = (time / 3.4).truncatingRemainder(dividingBy: 1)
            LinearGradient(colors: [.clear, accent.opacity(0.14), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 70)
                .offset(x: -70 + (geo.size.width + 140) * p)
        }
        .allowsHitTesting(false)
    }
}

/// How far the night's consolidation has run.
public struct ConsolidationMeter: View {
    public var progress: Double
    public var accent: Color
    public init(progress: Double, accent: Color) { self.progress = progress; self.accent = accent }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.andromedaTeal.opacity(0.09))
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.35), accent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * progress))
                    .shadow(color: accent.opacity(0.7), radius: 6)
            }
        }
        .frame(height: 3)
        .animation(.easeInOut(duration: 0.9), value: progress)
        .accessibilityLabel("Consolidation \(Int(progress * 100)) percent")
    }
}
