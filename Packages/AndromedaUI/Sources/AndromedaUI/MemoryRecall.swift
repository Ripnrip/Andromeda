import SwiftUI
#if canImport(Combine)
import Combine
#endif

// MARK: - Event-driven memory: pulse + sweeping skeleton
// The SwiftUI counterparts to the Control Bar's memory.recall event.

/// A sweeping skeleton row — a teal sheen crossing a redacted line.
/// Use several at staggered delays for a "loading working set" panel.
public struct RecallSkeletonRow: View {
    public var width: CGFloat
    public var delay: Double
    @State private var phase: CGFloat = -1
    public init(width: CGFloat = 200, delay: Double = 0) {
        self.width = width; self.delay = delay
    }
    public var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.andromedaTeal.opacity(0.10))
            .frame(width: width, height: 11)
            .overlay(
                LinearGradient(colors: [.clear, .andromedaGlow.opacity(0.55), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 70)
                    .offset(x: phase * (width + 70))
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .onAppear {
                withAnimation(.linear(duration: 1.2).delay(delay).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

/// Concentric rings that expand and fade — fire once per "memory added"
/// event by toggling `trigger`. Sits behind a glyph.
public struct MemoryPulse: View {
    public var trigger: Bool
    public var color: Color
    public init(trigger: Bool, color: Color = .andromedaTeal) {
        self.trigger = trigger; self.color = color
    }
    public var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle().strokeBorder(color, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .scaleEffect(trigger ? 2.6 : 0.55)
                    .opacity(trigger ? 0 : 0.85)
                    .animation(
                        .easeOut(duration: 1.1)
                            .delay(Double(i) * 0.4)
                            .repeatForever(autoreverses: false),
                        value: trigger
                    )
            }
        }
    }
}

/// A recalled memory line, salience-ranked.
public struct RecalledMemory: Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let meta: String
    public let live: Bool
    public init(_ label: String, _ meta: String, live: Bool = false) {
        self.label = label; self.meta = meta; self.live = live
    }
}

/// The full memory.recall experience: tap to recall → the core pulses and a
/// skeleton sweep plays while the working set is searched, then the ranked
/// rows resolve in. Theme-aware (dark void / light observatory).
public struct MemoryRecallControl: View {
    public var memories: [RecalledMemory]
    @State private var recalling = false
    @State private var pulse = false
    @State private var revealed = false

    public init(memories: [RecalledMemory] = MemoryRecallControl.sample) {
        self.memories = memories
    }

    public static let sample = [
        RecalledMemory("prefers concise, direct answers", "salience 0.92 · 2m ago", live: true),
        RecalledMemory("deploy target · node “atlas”", "salience 0.81 · 14m ago"),
        RecalledMemory("tone · warm, technical", "salience 0.74 · 1h ago"),
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if recalling {
                VStack(alignment: .leading, spacing: 9) {
                    RecallSkeletonRow(width: 208, delay: 0)
                    RecallSkeletonRow(width: 164, delay: 0.2)
                    RecallSkeletonRow(width: 128, delay: 0.4)
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(memories.enumerated()), id: \.element.id) { i, m in
                        row(m)
                            .opacity(revealed ? 1 : 0)
                            .offset(y: revealed ? 0 : 5)
                            .animation(.spring(duration: 0.4, bounce: 0.3).delay(Double(i) * 0.07), value: revealed)
                    }
                }
            }
        }
        .padding(15)
        .frame(width: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.andromedaTeal.opacity(0.16)))
        )
        .onAppear(perform: recall)
    }

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                MemoryPulse(trigger: pulse)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.andromedaTeal)
                    .shadow(color: .andromedaTeal.opacity(pulse ? 0.8 : 0.3), radius: pulse ? 7 : 3)
            }
            .frame(width: 26, height: 26)
            Text("memory.recall")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.andromedaTeal)
            Spacer()
            if recalling {
                ProgressRing().frame(width: 13, height: 13)
            }
            Button(action: recall) {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.andromedaMuted)
        }
    }

    private func row(_ m: RecalledMemory) -> some View {
        HStack(spacing: 10) {
            Circle().fill(m.live ? Color.andromedaLive : Color.andromedaTeal)
                .frame(width: 7, height: 7)
                .shadow(color: m.live ? .andromedaLive : .andromedaTeal, radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.label).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(m.meta).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
    }

    /// Fire the event: pulse the core + sweep the skeleton, then resolve.
    private func recall() {
        revealed = false
        withAnimation { recalling = true }
        pulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { recalling = false }
            pulse = false
            withAnimation { revealed = true }
        }
    }
}

/// A small indeterminate ring used in the recall header.
struct ProgressRing: View {
    @State private var spin = false
    var body: some View {
        Circle().trim(from: 0, to: 0.7)
            .stroke(Color.andromedaTeal, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
    }
}

// MARK: - Previews

#Preview("MemoryRecall · both") {
    HStack(spacing: 0) {
        ZStack { AndromedaSurface(); MemoryRecallControl() }
            .frame(width: 300, height: 240).environment(\.colorScheme, .dark)
        ZStack { AndromedaSurface(); MemoryRecallControl() }
            .frame(width: 300, height: 240).environment(\.colorScheme, .light)
    }
    .fixedSize()
}

#Preview("RecallSkeletonRow") { SchemePair { RecallSkeletonRow(width: 150) } }
#Preview("MemoryPulse") {
    SchemePair { ZStack { MemoryPulse(trigger: true); Circle().fill(Color.andromedaTeal).frame(width: 12, height: 12) } }
}
