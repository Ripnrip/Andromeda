/**
 * 🎭 The FloatingPetView - The Ambient Desktop Familiar
 *
 * Modern SwiftUI: `@Observable` model, phase-friendly pulse, reduce-motion
 * static path, extracted chrome, `.animation(_:value:)`.
 */

import Foundation
import SwiftUI

// MARK: - Ambient State

public enum FloatingPetAmbientState: String, CaseIterable, Equatable, Sendable, Codable {
    case idle
    case syncing
    case dreaming
    case degraded

    public var accessibilityLabel: String {
        switch self {
        case .idle: return "Andromeda pet idle"
        case .syncing: return "Andromeda pet syncing"
        case .dreaming: return "Andromeda pet dreaming"
        case .degraded: return "Andromeda pet degraded"
        }
    }

    public var staticSpriteName: String {
        switch self {
        case .idle: return "pet.idle.static"
        case .syncing: return "pet.syncing.static"
        case .dreaming: return "pet.dreaming.static"
        case .degraded: return "pet.degraded.static"
        }
    }

    public var animatedSpriteNames: [String] {
        switch self {
        case .idle: return ["pet.idle.breathe.0", "pet.idle.breathe.1"]
        case .syncing: return ["pet.syncing.pulse.0", "pet.syncing.pulse.1", "pet.syncing.pulse.2"]
        case .dreaming: return ["pet.dreaming.zzz.0", "pet.dreaming.zzz.1"]
        case .degraded: return ["pet.degraded.storm.0", "pet.degraded.storm.1"]
        }
    }

    public var statusTintName: String {
        switch self {
        case .idle: return "green"
        case .syncing: return "cyan"
        case .dreaming: return "indigo"
        case .degraded: return "red"
        }
    }
}

public enum FloatingPetSyncSignal: Equatable, Sendable {
    case idle
    case syncing
    case failed(String)
}

public enum FloatingPetDreamSignal: Equatable, Sendable {
    case idle
    case dreaming(progress: Double)
    case failed(String)
}

public enum FloatingPetServiceHealth: Equatable, Sendable {
    case unknown
    case healthy
    case unhealthy(String)
}

public enum FloatingPetPresentation: Equatable, Sendable {
    case animated(frames: [String], intensity: Double)
    case `static`(frame: String)

    public var isAnimated: Bool {
        if case .animated = self { return true }
        return false
    }

    public var primaryFrame: String {
        switch self {
        case .animated(let frames, _): return frames.first ?? "pet.idle.static"
        case .static(let frame): return frame
        }
    }
}

// MARK: - Model

@MainActor
@Observable
public final class FloatingPetModel {
    public var ambientState: FloatingPetAmbientState
    public var reduceMotion: Bool
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

    public var shouldAnimate: Bool { !reduceMotion }

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

    public var accessibilityLabel: String {
        if let statusDetail, !statusDetail.isEmpty {
            return "\(ambientState.accessibilityLabel): \(statusDetail)"
        }
        return ambientState.accessibilityLabel
    }

    public func transition(to next: FloatingPetAmbientState, detail: String? = nil) {
        guard ambientState != next || statusDetail != detail else { return }
        ambientState = next
        statusDetail = detail
    }

    public static func resolveAmbientState(
        sync: FloatingPetSyncSignal,
        dream: FloatingPetDreamSignal,
        connectionHealth: [String: FloatingPetServiceHealth]
    ) -> FloatingPetAmbientState {
        let hasUnhealthy = connectionHealth.values.contains {
            if case .unhealthy = $0 { return true }
            return false
        }
        let syncFailed: Bool
        if case .failed = sync { syncFailed = true } else { syncFailed = false }
        if hasUnhealthy || syncFailed { return .degraded }
        if case .dreaming = dream { return .dreaming }
        if case .syncing = sync { return .syncing }
        return .idle
    }

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
        case .dreaming: detail = "materializing"
        case .syncing: detail = "cloud sync"
        case .idle: detail = nil
        }
        transition(to: next, detail: detail)
    }
}

// MARK: - View

@MainActor
public struct FloatingPetView: View {
    @Bindable private var model: FloatingPetModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private let honorSystemReduceMotion: Bool

    @ScaledMetric(relativeTo: .title) private var glyphSize: CGFloat = 28

    public init(model: FloatingPetModel, honorSystemReduceMotion: Bool = true) {
        self.model = model
        self.honorSystemReduceMotion = honorSystemReduceMotion
    }

    public var body: some View {
        let effectiveReduce = honorSystemReduceMotion
            ? (model.reduceMotion || systemReduceMotion)
            : model.reduceMotion

        FloatingPetChrome(
            state: model.ambientState,
            presentation: effectiveReduce
                ? .static(frame: model.ambientState.staticSpriteName)
                : model.presentation,
            glyphSize: glyphSize
        )
        .animation(MemoryKitMotion.animation(reduceMotion: effectiveReduce), value: model.ambientState)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityAddTraits(.isImage)
        .onAppear(perform: syncReduceMotionOnAppear)
        .onChange(of: systemReduceMotion) { _, newValue in
            guard honorSystemReduceMotion, newValue else { return }
            model.reduceMotion = true
        }
    }

    private func syncReduceMotionOnAppear() {
        if honorSystemReduceMotion, systemReduceMotion {
            model.reduceMotion = true
        }
    }
}

// MARK: - Chrome (extracted)

private struct FloatingPetChrome: View {
    let state: FloatingPetAmbientState
    let presentation: FloatingPetPresentation
    let glyphSize: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 56, height: 56)
                .overlay(Circle().fill(tint.opacity(0.22)))
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))

            Text(glyph)
                .font(.system(size: glyphSize))
                .scaleEffect(presentation.isAnimated ? 1.04 : 1.0)
                .opacity(presentation.isAnimated ? 0.92 : 1.0)

            Text(presentation.primaryFrame)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .offset(y: 36)
        }
        .frame(width: 72, height: 88)
        .help(state.accessibilityLabel)
    }

    private var tint: Color {
        switch state {
        case .idle: return .green
        case .syncing: return .cyan
        case .dreaming: return .indigo
        case .degraded: return .red
        }
    }

    private var glyph: String {
        switch state {
        case .idle: return "🌙"
        case .syncing: return "✨"
        case .dreaming: return "💭"
        case .degraded: return "🌩️"
        }
    }
}

#if DEBUG
@MainActor
enum FloatingPetPreviewCatalog {
    static func model(_ state: FloatingPetAmbientState, reduceMotion: Bool) -> FloatingPetModel {
        let detail: String?
        switch state {
        case .idle: detail = nil
        case .syncing: detail = "cloud sync"
        case .dreaming: detail = "materializing"
        case .degraded: detail = "letta_api"
        }
        return FloatingPetModel(ambientState: state, reduceMotion: reduceMotion, statusDetail: detail)
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
        .preferredColorScheme(scheme)
        .environment(\.dynamicTypeSize, typeSize)
        .padding(24)
        .background(scheme == .dark ? Color.black : Color.white)
    }
}

#Preview("Pet · idle · motion · light") {
    FloatingPetPreviewCatalog.staged(.idle, reduceMotion: false, scheme: .light, typeSize: .medium)
}

#Preview("Pet · syncing · reduceMotion · dark") {
    FloatingPetPreviewCatalog.staged(.syncing, reduceMotion: true, scheme: .dark, typeSize: .medium)
}

#Preview("Pet · degraded · a11y2") {
    FloatingPetPreviewCatalog.staged(.degraded, reduceMotion: false, scheme: .dark, typeSize: .accessibility2)
}
#endif
