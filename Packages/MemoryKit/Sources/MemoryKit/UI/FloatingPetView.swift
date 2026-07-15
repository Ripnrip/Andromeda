/**
 * 🎭 The FloatingPetView - The Ambient Desktop Familiar
 *
 * "A tiny constellation perched at the edge of the glass—
 * breathing when the hive is calm, pulsing when satellites sync,
 * dreaming when the materializer walks the vault by night,
 * and storming only when health itself forgets to hum."
 *
 * - The Theatrical Virtuoso of Phase-4 Delight
 */

import Foundation
import SwiftUI

// MARK: - Ambient State

/// 🌟 The FloatingPetAmbientState - Four moods of the standing companion
public enum FloatingPetAmbientState: String, CaseIterable, Equatable, Sendable, Codable {
    case idle
    case syncing
    case dreaming
    case degraded

    /// 🎨 VoiceOver-friendly label for the seeker of wisdom
    public var accessibilityLabel: String {
        switch self {
        case .idle:
            return "Anima pet idle"
        case .syncing:
            return "Anima pet syncing"
        case .dreaming:
            return "Anima pet dreaming"
        case .degraded:
            return "Anima pet degraded"
        }
    }

    /// 💎 Static sprite key when motion is cloaked (reduce-motion / proof stub)
    public var staticSpriteName: String {
        switch self {
        case .idle: return "pet.idle.static"
        case .syncing: return "pet.syncing.static"
        case .dreaming: return "pet.dreaming.static"
        case .degraded: return "pet.degraded.static"
        }
    }

    /// ✨ Animated sprite keys when the stage is allowed to dance
    public var animatedSpriteNames: [String] {
        switch self {
        case .idle:
            return ["pet.idle.breathe.0", "pet.idle.breathe.1"]
        case .syncing:
            return ["pet.syncing.pulse.0", "pet.syncing.pulse.1", "pet.syncing.pulse.2"]
        case .dreaming:
            return ["pet.dreaming.zzz.0", "pet.dreaming.zzz.1"]
        case .degraded:
            return ["pet.degraded.storm.0", "pet.degraded.storm.1"]
        }
    }

    /// 🌊 Color cue for status chrome (proof stub — not a full theme system)
    public var statusTintName: String {
        switch self {
        case .idle: return "green"
        case .syncing: return "cyan"
        case .dreaming: return "indigo"
        case .degraded: return "red"
        }
    }
}

// MARK: - Pet-local lifecycle signals
// Kept local so the UI stub does not collide with fleet vs connection health types.

/// 🌟 Sync pipeline signal as seen by the familiar
public enum FloatingPetSyncSignal: Equatable, Sendable {
    case idle
    case syncing
    case failed(String)
}

/// 🌟 Dream / materialization signal
public enum FloatingPetDreamSignal: Equatable, Sendable {
    case idle
    case dreaming(progress: Double)
    case failed(String)
}

/// 🌟 Per-service connection health for pet derivation (not fleet health.json)
public enum FloatingPetServiceHealth: Equatable, Sendable {
    case unknown
    case healthy
    case unhealthy(String)
}

// MARK: - Presentation

/// 🌟 How the familiar appears — dance or still portrait
public enum FloatingPetPresentation: Equatable, Sendable {
    case animated(frames: [String], intensity: Double)
    case `static`(frame: String)

    public var isAnimated: Bool {
        if case .animated = self { return true }
        return false
    }

    public var primaryFrame: String {
        switch self {
        case .animated(let frames, _):
            return frames.first ?? "pet.idle.static"
        case .static(let frame):
            return frame
        }
    }
}

// MARK: - Model (@MainActor)

/**
 * 🎭 The FloatingPetModel - Observable mood board for the desktop familiar
 *
 * Isolates all view-facing pet state on the main actor so SwiftUI never
 * chases ambient status across concurrency borders. Reduce-motion is an
 * injectable preference so tests can prove the static fallback without
 * spinning an AccessibilitySettings circus. 🎪
 */
@MainActor
@Observable
public final class FloatingPetModel {
    /// 🌙 Current ambient mood of the companion
    public var ambientState: FloatingPetAmbientState

    /// 🌊 When true, intense animation frames yield to a clean static graphic
    public var reduceMotion: Bool

    /// 🔍 Optional human-readable reason (e.g. RED health check name)
    public var statusDetail: String?

    public init(
        ambientState: FloatingPetAmbientState = .idle,
        reduceMotion: Bool = false,
        statusDetail: String? = nil
    ) {
        self.ambientState = ambientState
        self.reduceMotion = reduceMotion
        self.statusDetail = statusDetail
    }

    /// ✨ Whether the pet should run sprite-frame animation
    public var shouldAnimate: Bool {
        !reduceMotion
    }

    /// 🎨 Resolved presentation — reduce-motion always wins
    public var presentation: FloatingPetPresentation {
        if reduceMotion {
            return .static(frame: ambientState.staticSpriteName)
        }
        let intensity: Double
        switch ambientState {
        case .idle: intensity = 0.25
        case .syncing: intensity = 0.85
        case .dreaming: intensity = 0.55
        case .degraded: intensity = 1.0
        }
        return .animated(frames: ambientState.animatedSpriteNames, intensity: intensity)
    }

    /// ♿ Combined accessibility announcement
    public var accessibilityLabel: String {
        if let statusDetail, !statusDetail.isEmpty {
            return "\(ambientState.accessibilityLabel): \(statusDetail)"
        }
        return ambientState.accessibilityLabel
    }

    /// 🌟 Transition ritual — updates mood + optional detail on the main stage
    public func transition(to mysticalNextState: FloatingPetAmbientState, detail: String? = nil) {
        print("🌐 ✨ PET AMBIENT AWAKENS! → \(mysticalNextState.rawValue)")
        ambientState = mysticalNextState
        statusDetail = detail
    }

    /**
     * 🔮 Derive ambient mood from pet-local lifecycle signals.
     *
     * Priority (highest first): degraded → dreaming → syncing → idle.
     * Degraded wins so a RED service never hides behind a sync pulse.
     */
    public static func resolveAmbientState(
        sync: FloatingPetSyncSignal,
        dream: FloatingPetDreamSignal,
        connectionHealth: [String: FloatingPetServiceHealth]
    ) -> FloatingPetAmbientState {
        let hasUnhealthy = connectionHealth.values.contains { status in
            if case .unhealthy = status { return true }
            return false
        }
        let syncFailed: Bool
        if case .failed = sync {
            syncFailed = true
        } else {
            syncFailed = false
        }
        if hasUnhealthy || syncFailed {
            return .degraded
        }
        if case .dreaming = dream {
            return .dreaming
        }
        if case .syncing = sync {
            return .syncing
        }
        return .idle
    }

    /// 🎪 Apply derived mood from lifecycle signals onto the main-actor model
    public func applyLifecycle(
        sync: FloatingPetSyncSignal,
        dream: FloatingPetDreamSignal,
        connectionHealth: [String: FloatingPetServiceHealth]
    ) {
        let next = Self.resolveAmbientState(
            sync: sync,
            dream: dream,
            connectionHealth: connectionHealth
        )
        let detail: String?
        switch next {
        case .degraded:
            if let unhealthy = connectionHealth.first(where: {
                if case .unhealthy = $0.value { return true }
                return false
            }) {
                if case .unhealthy(let reason) = unhealthy.value {
                    detail = "\(unhealthy.key): \(reason)"
                } else {
                    detail = unhealthy.key
                }
            } else if case .failed(let reason) = sync {
                detail = reason
            } else {
                detail = "degraded"
            }
        case .dreaming:
            detail = "materializing"
        case .syncing:
            detail = "cloud sync"
        case .idle:
            detail = nil
        }
        transition(to: next, detail: detail)
    }
}

// MARK: - SwiftUI View

/**
 * 🎭 FloatingPetView - Standing state-reactive companion (proof-quality stub)
 *
 * Thin SwiftUI surface over `FloatingPetModel`. Real MenuBarExtra hosting
 * and CoreHaptics hooks land in Phase 4 product wiring — this stub proves
 * MainActor isolation, ambient states, and the reduce-motion static path.
 */
@MainActor
public struct FloatingPetView: View {
    @Bindable private var model: FloatingPetModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// 🌟 When true, Environment reduce-motion merges into the model each body pass
    private let honorSystemReduceMotion: Bool

    public init(model: FloatingPetModel, honorSystemReduceMotion: Bool = true) {
        self.model = model
        self.honorSystemReduceMotion = honorSystemReduceMotion
    }

    public var body: some View {
        let effectiveReduce = honorSystemReduceMotion
            ? (model.reduceMotion || systemReduceMotion)
            : model.reduceMotion

        return petChrome(effectiveReduceMotion: effectiveReduce)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.accessibilityLabel)
            .accessibilityAddTraits(.isImage)
            .onAppear {
                if honorSystemReduceMotion, systemReduceMotion {
                    model.reduceMotion = true
                }
            }
            .onChange(of: systemReduceMotion) { _, newValue in
                guard honorSystemReduceMotion else { return }
                if newValue {
                    model.reduceMotion = true
                }
            }
    }

    // 🎨 The painted familiar — static glyph or gentle pulse
    @ViewBuilder
    private func petChrome(effectiveReduceMotion: Bool) -> some View {
        let presentation = effectiveReduceMotion
            ? FloatingPetPresentation.static(frame: model.ambientState.staticSpriteName)
            : model.presentation

        ZStack {
            Circle()
                .fill(tint(for: model.ambientState).opacity(0.22))
                .frame(width: 56, height: 56)

            Text(emojiGlyph(for: model.ambientState))
                .font(.system(size: 28))
                .modifier(PetPulseModifier(isAnimating: presentation.isAnimated))

            // 💎 Proof-visible sprite identity (tests assert via model; preview sees it)
            Text(presentation.primaryFrame)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .offset(y: 36)
        }
        .frame(width: 72, height: 88)
        .help(model.accessibilityLabel)
    }

    private func tint(for state: FloatingPetAmbientState) -> Color {
        switch state {
        case .idle: return .green
        case .syncing: return .cyan
        case .dreaming: return .indigo
        case .degraded: return .red
        }
    }

    private func emojiGlyph(for state: FloatingPetAmbientState) -> String {
        switch state {
        case .idle: return "🌙"
        case .syncing: return "✨"
        case .dreaming: return "💭"
        case .degraded: return "🌩️"
        }
    }
}

// MARK: - Pulse shim (proof stub — no CoreHaptics / MenuBarExtra host yet)

/// 🌊 Soft opacity cue when animation is allowed; identity under reduce-motion
private struct PetPulseModifier: ViewModifier {
    let isAnimating: Bool

    func body(content: Content) -> some View {
        content.opacity(isAnimating ? 0.92 : 1.0)
    }
}

#if DEBUG
// MARK: - Preview Catalog (ambient × reduceMotion × light/dark × Dynamic Type)

/// 🌟 Shared preview stage dressing for the FloatingPet catalog
@MainActor
enum FloatingPetPreviewCatalog {
    static func model(
        _ state: FloatingPetAmbientState,
        reduceMotion: Bool
    ) -> FloatingPetModel {
        let detail: String?
        switch state {
        case .idle: detail = nil
        case .syncing: detail = "cloud sync"
        case .dreaming: detail = "materializing"
        case .degraded: detail = "letta_api"
        }
        return FloatingPetModel(
            ambientState: state,
            reduceMotion: reduceMotion,
            statusDetail: detail
        )
    }

    @ViewBuilder
    static func staged(
        _ state: FloatingPetAmbientState,
        reduceMotion: Bool,
        scheme: ColorScheme,
        typeSize: DynamicTypeSize
    ) -> some View {
        FloatingPetView(
            model: model(state, reduceMotion: reduceMotion),
            honorSystemReduceMotion: false
        )
        .environment(\.colorScheme, scheme)
        .environment(\.dynamicTypeSize, typeSize)
        .padding(24)
        .background(scheme == .dark ? Color.black : Color.white)
    }
}

#Preview("Pet · idle · motion · light · medium") {
    FloatingPetPreviewCatalog.staged(.idle, reduceMotion: false, scheme: .light, typeSize: .medium)
}

#Preview("Pet · idle · reduceMotion · light · medium") {
    FloatingPetPreviewCatalog.staged(.idle, reduceMotion: true, scheme: .light, typeSize: .medium)
}

#Preview("Pet · idle · motion · dark · medium") {
    FloatingPetPreviewCatalog.staged(.idle, reduceMotion: false, scheme: .dark, typeSize: .medium)
}

#Preview("Pet · idle · reduceMotion · dark · a11y2") {
    FloatingPetPreviewCatalog.staged(.idle, reduceMotion: true, scheme: .dark, typeSize: .accessibility2)
}

#Preview("Pet · syncing · motion · light · medium") {
    FloatingPetPreviewCatalog.staged(.syncing, reduceMotion: false, scheme: .light, typeSize: .medium)
}

#Preview("Pet · syncing · reduceMotion · dark · medium") {
    FloatingPetPreviewCatalog.staged(.syncing, reduceMotion: true, scheme: .dark, typeSize: .medium)
}

#Preview("Pet · syncing · motion · light · a11y2") {
    FloatingPetPreviewCatalog.staged(.syncing, reduceMotion: false, scheme: .light, typeSize: .accessibility2)
}

#Preview("Pet · dreaming · motion · light · medium") {
    FloatingPetPreviewCatalog.staged(.dreaming, reduceMotion: false, scheme: .light, typeSize: .medium)
}

#Preview("Pet · dreaming · reduceMotion · dark · medium") {
    FloatingPetPreviewCatalog.staged(.dreaming, reduceMotion: true, scheme: .dark, typeSize: .medium)
}

#Preview("Pet · dreaming · motion · dark · a11y2") {
    FloatingPetPreviewCatalog.staged(.dreaming, reduceMotion: false, scheme: .dark, typeSize: .accessibility2)
}

#Preview("Pet · degraded · motion · light · medium") {
    FloatingPetPreviewCatalog.staged(.degraded, reduceMotion: false, scheme: .light, typeSize: .medium)
}

#Preview("Pet · degraded · reduceMotion · light · medium") {
    FloatingPetPreviewCatalog.staged(.degraded, reduceMotion: true, scheme: .light, typeSize: .medium)
}

#Preview("Pet · degraded · motion · dark · a11y2") {
    FloatingPetPreviewCatalog.staged(.degraded, reduceMotion: false, scheme: .dark, typeSize: .accessibility2)
}

#Preview("Pet · degraded · reduceMotion · dark · a11y2") {
    FloatingPetPreviewCatalog.staged(.degraded, reduceMotion: true, scheme: .dark, typeSize: .accessibility2)
}
#endif
