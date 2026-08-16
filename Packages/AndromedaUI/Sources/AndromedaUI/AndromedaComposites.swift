import SwiftUI

// MARK: - Composites
// Individual primitives are the vocabulary; these are the sentences.
// Each composite is a real control-plane surface assembled only from
// shipped primitives — no bespoke one-offs.

// MARK: Ambient backdrop

/// The layered Andromeda backdrop: surface, aurora, meteors, grid horizon.
/// Wrap any composite in it to get the full depth of the control plane.
public struct AndromedaAmbientBackdrop<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    public var body: some View {
        ZStack {
            AndromedaSurface()
            Aurora().opacity(0.55).blur(radius: 6)
            Meteors(count: 4).opacity(0.35)
            RetroGrid().opacity(0.3).frame(maxHeight: .infinity, alignment: .bottom)
            content
        }
    }
}

// MARK: HUD capsule

/// The compact HUD: core, live recall waveform, the capability being
/// written, and fleet health — the thing that sits above every space.
public struct AndromedaHUDCapsule: View {
    public var capability: String
    public var fleet: Int
    public init(capability: String = "infer.write", fleet: Int = 3) {
        self.capability = capability; self.fleet = fleet
    }
    public var body: some View {
        HStack(spacing: 13) {
            HUDCore()
                .frame(width: 44, height: 44)
            Divider().frame(height: 26).overlay(Color.andromedaTeal.opacity(0.16))
            RecallWaveform()
            TypingCaret(capability)
            Divider().frame(height: 26).overlay(Color.andromedaTeal.opacity(0.16))
            HStack(spacing: 7) {
                AmbientGlow()
                VStack(alignment: .leading, spacing: 1) {
                    Text("fleet · \(fleet)")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.andromedaInk)
                    Text("healthy")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.andromedaMuted)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 20).fill(Color.andromedaPanel.opacity(0.92))
                .shadow(color: .black.opacity(0.5), radius: 28, y: 16)
        )
        .borderBeam(cornerRadius: 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Andromeda HUD, \(capability), fleet \(fleet) healthy")
    }
}

// MARK: Status strip

/// The six pillars in one strip, each carrying its own health signal.
public struct AndromedaStatusStrip: View {
    public var pillars: [BarPillar]
    public init(pillars: [BarPillar] = BarPillar.all) { self.pillars = pillars }
    public var body: some View {
        HStack(spacing: 4) {
            HUDCoreGlyph(size: 32)
            Divider().frame(height: 30).overlay(Color.andromedaTeal.opacity(0.16))
            ForEach(pillars) { PillarButton($0) }
            Divider().frame(height: 30).overlay(Color.andromedaTeal.opacity(0.16))
            FleetStatus()
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 20).fill(Color.andromedaPanel.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.andromedaTeal.opacity(0.18)))
                .shadow(color: .black.opacity(0.45), radius: 26, y: 14)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capability strip")
    }
}

// MARK: Loading board

/// Every "we're working" signal in one panel, so the set stays coherent.
public struct AndromedaLoadingBoard: View {
    public var progress: Double
    public init(progress: Double = 0.62) { self.progress = progress }
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                SpinnerArc()
                SegmentedLoader()
                DotLoader()
            }
            ProgressFill(value: progress)
            VStack(alignment: .leading, spacing: 7) {
                ForEach([132.0, 108.0, 84.0], id: \.self) { w in
                    ShimmerSkeleton().frame(width: w, height: 8)
                }
            }
            DataStream()
        }
        .padding(20)
        .frame(width: 230, alignment: .leading)
        .background(cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Work in progress, \(Int(progress * 100)) percent")
    }
}

// MARK: Feedback row

/// The full outcome vocabulary — nothing else may report success or failure.
public struct AndromedaFeedbackRow: View {
    public init() {}
    public var body: some View {
        HStack(spacing: 22) {
            VStack(spacing: 9) { SuccessCheck(); caption("done") }
            VStack(spacing: 9) { ErrorShake(); caption("failed") }
            VStack(spacing: 9) { BadgePop(); caption("arrived") }
            VStack(spacing: 9) { RippleTap(); caption("tapped") }
        }
        .padding(20)
        .background(cardBackground)
        .accessibilityElement(children: .contain)
    }
    private func caption(_ s: String) -> some View {
        Text(s).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(Color.andromedaMuted)
    }
}

// MARK: Memory panel

/// Recall in flight: the kind being read, the layer being scanned, and the
/// write log draining behind it.
public struct AndromedaMemoryPanel: View {
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                AndromedaCore(size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    GradientText("Memory")
                    WordRotate()
                }
                Spacer(minLength: 0)
                MorphingText()
            }
            HStack(alignment: .top, spacing: 16) {
                Scanline()
                VerticalMarquee()
            }
            HStack(spacing: 14) {
                SignalBars()
                Heartbeat()
            }
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .background(cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Memory panel")
    }
}

// MARK: Fleet board

/// Nodes, links, and reach — the runtime seen from above.
public struct AndromedaFleetBoard: View {
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                LivePulse(size: 10)
                Text("fleet.pulse")
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.andromedaInk)
                Spacer(minLength: 0)
                Text("3 nodes")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.andromedaMuted)
            }
            HStack(spacing: 18) {
                OrbitCluster()
                VStack(spacing: 14) {
                    Broadcast()
                    AnimatedBeam()
                }
            }
            HStack(spacing: 16) {
                FleetConstellation()
                RouteTrace()
            }
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .background(cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fleet board, 3 nodes")
    }
}

// MARK: Console

/// The joined surface: ambient backdrop, HUD capsule, and the three boards
/// side by side — the whole system in one frame.
public struct AndromedaConsole: View {
    public init() {}
    public var body: some View {
        AndromedaAmbientBackdrop {
            VStack(spacing: 26) {
                AndromedaHUDCapsule()
                HStack(alignment: .top, spacing: 20) {
                    AndromedaMemoryPanel()
                    VStack(spacing: 20) {
                        AndromedaFeedbackRow()
                        AndromedaLoadingBoard()
                    }
                    AndromedaFleetBoard()
                }
                AndromedaStatusStrip()
            }
            .padding(34)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Andromeda console")
    }
}

// MARK: - Shared card chrome

private var cardBackground: some View {
    RoundedRectangle(cornerRadius: 18)
        .fill(Color.andromedaPanel.opacity(0.82))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.andromedaTeal.opacity(0.14)))
}

// MARK: - Composite registry

/// Composites, named — the gallery and the snapshot sweep read from here.
public struct AndromedaComposite: Identifiable {
    public let id = UUID()
    public let name: String
    public let size: CGSize
    public let view: AnyView
    public init(_ name: String, _ size: CGSize, _ view: some View) {
        self.name = name; self.size = size; self.view = AnyView(view)
    }
}

public enum AndromedaComposites {
    @MainActor public static var all: [AndromedaComposite] {
        [
            .init("HUDCapsule",   CGSize(width: 520, height: 120), AndromedaHUDCapsule()),
            .init("StatusStrip",  CGSize(width: 640, height: 120), AndromedaStatusStrip()),
            .init("LoadingBoard", CGSize(width: 280, height: 340), AndromedaLoadingBoard()),
            .init("FeedbackRow",  CGSize(width: 480, height: 160), AndromedaFeedbackRow()),
            .init("MemoryPanel",  CGSize(width: 370, height: 340), AndromedaMemoryPanel()),
            .init("FleetBoard",   CGSize(width: 370, height: 400), AndromedaFleetBoard()),
            .init("Console",      CGSize(width: 1180, height: 720), AndromedaConsole()),
        ]
    }
}

// MARK: - Previews

#Preview("HUD capsule · dark")   { AndromedaAmbientBackdrop { AndromedaHUDCapsule() }.frame(width: 520, height: 140).preferredColorScheme(.dark) }
#Preview("HUD capsule · light")  { AndromedaAmbientBackdrop { AndromedaHUDCapsule() }.frame(width: 520, height: 140).preferredColorScheme(.light) }
#Preview("Status strip")         { AndromedaAmbientBackdrop { AndromedaStatusStrip() }.frame(width: 660, height: 130).preferredColorScheme(.dark) }
#Preview("Loading board")        { AndromedaAmbientBackdrop { AndromedaLoadingBoard() }.frame(width: 300, height: 360).preferredColorScheme(.dark) }
#Preview("Feedback row")         { AndromedaAmbientBackdrop { AndromedaFeedbackRow() }.frame(width: 500, height: 180).preferredColorScheme(.dark) }
#Preview("Memory panel")         { AndromedaAmbientBackdrop { AndromedaMemoryPanel() }.frame(width: 380, height: 360).preferredColorScheme(.dark) }
#Preview("Fleet board")          { AndromedaAmbientBackdrop { AndromedaFleetBoard() }.frame(width: 380, height: 420).preferredColorScheme(.dark) }
#Preview("Console · dark")       { AndromedaConsole().frame(width: 1180, height: 720).preferredColorScheme(.dark) }
#Preview("Console · light")      { AndromedaConsole().frame(width: 1180, height: 720).preferredColorScheme(.light) }
#Preview("Console · frozen")     { AndromedaConsole().andromedaFrozen().frame(width: 1180, height: 720).preferredColorScheme(.dark) }
