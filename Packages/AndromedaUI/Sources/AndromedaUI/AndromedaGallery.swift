import SwiftUI

// MARK: - Registry

/// A named specimen in the library — the gallery, the snapshot sweep, and
/// the docs all read from this one list so nothing drifts.
public struct AndromedaSpecimen: Identifiable {
    public let id = UUID()
    public let name: String
    public let group: AndromedaGroup
    public let view: AnyView
    public init(_ name: String, group: AndromedaGroup = .core, _ view: some View) {
        self.name = name
        self.group = group
        self.view = AnyView(view)
    }
}

/// The four shelves of the library.
public enum AndromedaGroup: String, CaseIterable, Identifiable, Sendable {
    case core       = "Core signals"
    case extended   = "Loaders, feedback & ambient"
    case transition = "Transitions, text & texture"
    case wild       = "In the wild"
    case companion  = "Companion HUD motion"

    public var id: String { rawValue }
}

public enum AndromedaCatalogue {
    /// Every animation the package ships, in gallery order.
    @MainActor public static var specimens: [AndromedaSpecimen] {
        core + extended + transitions + wild + companion
    }

    @MainActor public static func specimens(in group: AndromedaGroup) -> [AndromedaSpecimen] {
        specimens.filter { $0.group == group }
    }

    // The eight signals that anchor the control plane.
    @MainActor public static let core: [AndromedaSpecimen] = [
        .init("LivePulse", group: .core, LivePulse()),
        .init("BreathingRing", group: .core, BreathingRing()),
        .init("OrbitingSatellite", group: .core, OrbitingSatellite()),
        .init("RecallWaveform", group: .core, RecallWaveform()),
        .init("ScanSweep", group: .core, ScanSweep()),
        .init("HUDCore", group: .core, HUDCore()),
        .init("FleetConstellation", group: .core, FleetConstellation()),
        .init("ShimmerSkeleton", group: .core, ShimmerSkeleton()),
    ]

    // Loaders, feedback, ambient motion.
    @MainActor public static let extended: [AndromedaSpecimen] = [
        .init("DataStream", group: .extended, DataStream()),
        .init("SignalBars", group: .extended, SignalBars()),
        .init("TypingCaret", group: .extended, TypingCaret()),
        .init("SpinnerArc", group: .extended, SpinnerArc()),
        .init("ProgressFill", group: .extended, ProgressFill()),
        .init("RadarPing", group: .extended, RadarPing()),
        .init("Heartbeat", group: .extended, Heartbeat()),
        .init("DotLoader", group: .extended, DotLoader()),
        .init("Aurora", group: .extended, Aurora()),
        .init("TokenRoll", group: .extended, TokenRoll()),
        .init("RippleTap", group: .extended, RippleTap()),
        .init("SuccessCheck", group: .extended, SuccessCheck()),
        .init("ErrorShake", group: .extended, ErrorShake()),
        .init("BadgePop", group: .extended, BadgePop()),
        .init("RouteTrace", group: .extended, RouteTrace()),
        .init("EdgePulse", group: .extended, EdgePulse()),
        .init("SegmentedLoader", group: .extended, SegmentedLoader()),
        .init("IdleFloat", group: .extended, IdleFloat()),
        .init("AmbientGlow", group: .extended, AmbientGlow()),
        .init("FlipTile", group: .extended, FlipTile()),
        .init("Scanline", group: .extended, Scanline()),
        .init("OrbitCluster", group: .extended, OrbitCluster()),
        .init("ElasticToggle", group: .extended, ElasticToggle()),
        .init("Broadcast", group: .extended, Broadcast()),
        .init("Ignition", group: .extended, Ignition()),
    ]

    // State swaps, text motion, background texture.
    @MainActor public static let transitions: [AndromedaSpecimen] = [
        .init("CrossFade", group: .transition, CrossFade()),
        .init("SlideSwap", group: .transition, SlideSwap()),
        .init("ScalePop", group: .transition, ScalePop()),
        .init("MatchedGeometrySwap", group: .transition, MatchedGeometrySwap()),
        .init("PhaseCycle", group: .transition, PhaseCycle()),
        .init("ExpandCollapse", group: .transition, ExpandCollapse()),
        .init("BlurFade", group: .transition, BlurFade()),
        .init("WordRotate", group: .transition, WordRotate()),
        .init("MorphingText", group: .transition, MorphingText()),
        .init("TabUnderline", group: .transition, TabUnderline()),
        .init("CheckmarkToggle", group: .transition, CheckmarkToggle()),
        .init("ChevronRotate", group: .transition, ChevronRotate()),
        .init("Marquee", group: .transition, Marquee()),
        .init("VerticalMarquee", group: .transition, VerticalMarquee()),
        .init("BorderBeam", group: .transition, RoundedRectangle(cornerRadius: 18)
            .fill(Color.andromedaPanel.opacity(0.8))
            .frame(width: 128, height: 62)
            .borderBeam(cornerRadius: 18)),
        .init("ShimmerSweep", group: .transition, ShimmerSweep()),
        .init("Meteors", group: .transition, Meteors()),
        .init("AnimatedBeam", group: .transition, AnimatedBeam()),
        .init("RetroGrid", group: .transition, RetroGrid()),
        .init("RippleField", group: .transition, RippleField()),
        .init("PulsatingButton", group: .transition, PulsatingButton()),
        .init("GradientText", group: .transition, GradientText()),
        .init("SpinningText", group: .transition, SpinningText(radius: 36)),
        .init("FlickeringGrid", group: .transition, FlickeringGrid()),
    ]

    // Re-tuned from the open SwiftUI animation canon.
    @MainActor public static let wild: [AndromedaSpecimen] = [
        .init("Typewriter", group: .wild, Typewriter()),
        .init("Fireworks", group: .wild, Fireworks()),
        .init("PulsingHeart", group: .wild, PulsingHeart()),
        .init("SlideToUnlock", group: .wild, SlideToUnlock()),
        .init("NumericCrossfade", group: .wild, NumericCrossfade()),
        .init("HueRotation", group: .wild, HueRotation()),
        .init("CharacterFlip", group: .wild, CharacterFlip()),
        .init("DashMarch", group: .wild, DashMarch()),
        .init("SignatureDraw", group: .wild, SignatureDraw()),
        .init("SpringReactions", group: .wild, SpringReactions()),
        .init("LikeBurst", group: .wild, LikeBurst()),
        .init("OvershootBounce", group: .wild, OvershootBounce()),
        .init("PetalBloom", group: .wild, PetalBloom()),
        .init("Jiggle", group: .wild, Jiggle()),
        .init("JelloSquash", group: .wild, JelloSquash()),
        .init("EasingTrio", group: .wild, EasingTrio()),
        .init("Thinking", group: .wild, Thinking()),
        .init("InnerOuterBorder", group: .wild, InnerOuterBorder()),
        .init("IncomingCall", group: .wild, IncomingCall()),
        .init("GlassMorph", group: .wild, GlassMorph()),
        .init("BookmarkTuck", group: .wild, BookmarkTuck()),
        .init("Panel3DSway", group: .wild, Panel3DSway()),
        .init("AnchorHop", group: .wild, AnchorHop()),
        .init("ConfettiBurst", group: .wild, ConfettiBurst()),
        .init("RubberBand", group: .wild, RubberBand()),
        .init("RecallSkeletonRow", group: .wild, RecallSkeletonRow(width: 150)),
        .init("MemoryRecallControl", group: .wild, MemoryRecallControl()),
    ]

    // TimelineView-driven companion HUD motion + Canvas dream/memory scenes.
    @MainActor public static let companion: [AndromedaSpecimen] = [
        .init("Waveform", group: .companion, AndromedaWaveform()),
        .init("HUDShimmerSweep", group: .companion,
              AndromedaShimmerSweep().frame(width: 120, height: 30)),
        .init("OrbitDots", group: .companion, AndromedaOrbitDots()),
        .init("ParticleDrift", group: .companion,
              AndromedaParticleDrift().frame(width: 120, height: 80)),
        .init("BreathingGlow", group: .companion,
              AndromedaBreathingGlow().frame(width: 60, height: 60)),
        .init("RippleRings", group: .companion,
              AndromedaRippleRings().frame(width: 60, height: 60)),
        .init("MarchingSignal", group: .companion, AndromedaMarchingSignal()),
        .init("RotatingRing", group: .companion,
              AndromedaRotatingRing().frame(width: 40, height: 40)),
        .init("VectorGrid", group: .companion, AndromedaVectorGrid()),
        .init("TokenStream", group: .companion, AndromedaTokenStream()),
        .init("HUDProgressFill", group: .companion,
              AndromedaProgressFill().frame(width: 120, height: 8)),
        .init("DreamField", group: .companion,
              AndromedaDreamField().frame(width: 200, height: 120)),
        .init("RemWave", group: .companion,
              AndromedaRemWave().frame(width: 200, height: 120)),
        .init("BraidMerge", group: .companion,
              AndromedaBraidMerge().frame(width: 200, height: 120)),
        .init("EngramTimeline", group: .companion,
              AndromedaEngramTimeline().frame(width: 200, height: 120)),
        .init("ConstellationGraph", group: .companion,
              AndromedaConstellationGraph().frame(width: 200, height: 120)),
        .init("CrystalForm", group: .companion,
              AndromedaCrystalForm().frame(width: 200, height: 120)),
        .init("RecallPulse", group: .companion,
              AndromedaRecallPulse().frame(width: 200, height: 120)),
    ]
}

// MARK: - Gallery

/// A scrolling wall of every specimen, grouped by shelf.
public struct AndromedaGallery: View {
    public init() {}
    private let columns = [GridItem(.adaptive(minimum: 152), spacing: 16)]

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26, pinnedViews: [.sectionHeaders]) {
                ForEach(AndromedaGroup.allCases) { group in
                    Section {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(AndromedaCatalogue.specimens(in: group)) { specimen in
                                AndromedaTile(specimen.name) { specimen.view }
                            }
                        }
                    } header: {
                        HStack(spacing: 10) {
                            Text(group.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.andromedaInk)
                            Text("\(AndromedaCatalogue.specimens(in: group).count)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Color.andromedaMuted)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(AndromedaSurface().opacity(0.96))
                    }
                }
            }
            .padding(18)
        }
        .background(AndromedaSurface().ignoresSafeArea())
    }
}

/// A wall of the joined surfaces — each composite at its natural size.
public struct AndromedaCompositeGallery: View {
    public init() {}
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ForEach(AndromedaComposites.all) { composite in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(composite.name)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.andromedaMuted)
                        composite.view
                            .frame(width: composite.size.width, height: composite.size.height)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.andromedaTeal.opacity(0.12)))
                    }
                }
            }
            .padding(24)
        }
        .background(AndromedaSurface().ignoresSafeArea())
    }
}

#Preview("Gallery · dark")   { AndromedaGallery().preferredColorScheme(.dark) }
#Preview("Gallery · light")  { AndromedaGallery().preferredColorScheme(.light) }
#Preview("Gallery · frozen") { AndromedaGallery().andromedaFrozen().preferredColorScheme(.dark) }
#Preview("Composites")       { AndromedaCompositeGallery().preferredColorScheme(.dark) }
