/**
 * 🎭 FloatingPetViewTests - The Ambient Familiar Quality Ritual
 *
 * "We poke the pocket constellation until every mood answers—
 * idle calm, syncing pulse, dreamwalk hush, storm-red warning—
 * and we verify that reduce-motion cloaks the dance into stillness."
 *
 * - The Theatrical QA Virtuoso of Phase-4 Delight
 */

import Testing
import Foundation
@testable import MemoryKit

@Suite("🔮 Floating Pet Ambient Suite")
@MainActor
struct FloatingPetViewTests {

    // MARK: - Ambient vocabulary

    @Test("🌙 Ambient states include idle/syncing/dreaming/degraded")
    func testAmbientStateVocabulary() {
        let states = FloatingPetAmbientState.allCases
        #expect(states.count == 4)
        #expect(states.contains(.idle))
        #expect(states.contains(.syncing))
        #expect(states.contains(.dreaming))
        #expect(states.contains(.degraded))
    }

    @Test("♿ Accessibility labels are unique per ambient mood")
    func testAccessibilityLabels() {
        let labels = Set(FloatingPetAmbientState.allCases.map(\.accessibilityLabel))
        #expect(labels.count == FloatingPetAmbientState.allCases.count)
        #expect(FloatingPetAmbientState.idle.accessibilityLabel.contains("idle"))
        #expect(FloatingPetAmbientState.degraded.accessibilityLabel.contains("degraded"))
    }

    // MARK: - Model + reduce-motion

    @Test("✨ Default model awakens idle and animatable")
    func testDefaultModel() {
        let model = FloatingPetModel()
        #expect(model.ambientState == .idle)
        #expect(model.reduceMotion == false)
        #expect(model.shouldAnimate == true)
        #expect(model.presentation.isAnimated == true)
        #expect(model.accessibilityLabel == "Andromeda pet idle")
    }

    @Test("🌊 Reduce-motion path forces static presentation")
    func testReduceMotionStaticPath() {
        let model = FloatingPetModel(ambientState: .syncing, reduceMotion: true)
        #expect(model.shouldAnimate == false)
        #expect(model.presentation.isAnimated == false)
        #expect(model.presentation.primaryFrame == FloatingPetAmbientState.syncing.staticSpriteName)

        // Dreaming + degraded must also freeze under the cloak
        model.transition(to: .dreaming)
        #expect(model.presentation == .static(frame: "pet.dreaming.static"))

        model.transition(to: .degraded, detail: "letta_api")
        #expect(model.presentation.isAnimated == false)
        #expect(model.accessibilityLabel == "Andromeda pet degraded: letta_api")
    }

    @Test("🌟 Transition ritual updates ambient mood on MainActor")
    func testTransitionRitual() {
        let model = FloatingPetModel()
        model.transition(to: .syncing, detail: "cloud sync")
        #expect(model.ambientState == .syncing)
        #expect(model.statusDetail == "cloud sync")
        #expect(model.presentation.isAnimated == true)
        #expect(model.presentation.primaryFrame == "pet.syncing.pulse.0")
    }

    @Test("💎 Animated intensity scales by mood when motion is allowed")
    func testAnimationIntensityByState() {
        let model = FloatingPetModel(reduceMotion: false)

        model.transition(to: .idle)
        if case .animated(_, let intensity) = model.presentation {
            #expect(intensity == 0.25)
        } else {
            Issue.record("Expected animated idle presentation")
        }

        model.transition(to: .degraded)
        if case .animated(_, let intensity) = model.presentation {
            #expect(intensity == 1.0)
        } else {
            Issue.record("Expected animated degraded presentation")
        }
    }

    // MARK: - Lifecycle derivation

    @Test("🔮 Resolve: healthy idle when nothing is busy")
    func testResolveIdle() {
        let resolved = FloatingPetModel.resolveAmbientState(
            sync: .idle,
            dream: .idle,
            connectionHealth: ["letta": .healthy]
        )
        #expect(resolved == .idle)
    }

    @Test("✨ Resolve: syncing when CloudKit pipeline is active")
    func testResolveSyncing() {
        let resolved = FloatingPetModel.resolveAmbientState(
            sync: .syncing,
            dream: .idle,
            connectionHealth: [:]
        )
        #expect(resolved == .syncing)
    }

    @Test("💭 Resolve: dreaming when materializer is walking the vault")
    func testResolveDreaming() {
        let resolved = FloatingPetModel.resolveAmbientState(
            sync: .idle,
            dream: .dreaming(progress: 0.4),
            connectionHealth: [:]
        )
        #expect(resolved == .dreaming)
    }

    @Test("🌩️ Resolve: degraded wins over syncing/dreaming")
    func testResolveDegradedPriority() {
        let fromHealth = FloatingPetModel.resolveAmbientState(
            sync: .syncing,
            dream: .dreaming(progress: 0.9),
            connectionHealth: ["qdrant": .unhealthy("connection refused")]
        )
        #expect(fromHealth == .degraded)

        let fromSyncFailure = FloatingPetModel.resolveAmbientState(
            sync: .failed("network disconnected"),
            dream: .dreaming(progress: 0.1),
            connectionHealth: ["letta": .healthy]
        )
        #expect(fromSyncFailure == .degraded)
    }

    @Test("🎪 applyLifecycle projects lifecycle signals onto the pet")
    func testApplyLifecycle() {
        let model = FloatingPetModel()
        model.applyLifecycle(
            sync: .syncing,
            dream: .idle,
            connectionHealth: [:]
        )
        #expect(model.ambientState == .syncing)
        #expect(model.statusDetail == "cloud sync")

        model.applyLifecycle(
            sync: .idle,
            dream: .dreaming(progress: 0.2),
            connectionHealth: ["ladybug": .unhealthy("socket down")]
        )
        #expect(model.ambientState == .degraded)
        #expect(model.statusDetail == "ladybug: socket down")
    }

    @Test("🎭 FloatingPetView constructs on MainActor without drama")
    func testViewConstructs() {
        let model = FloatingPetModel(ambientState: .dreaming, reduceMotion: true)
        let view = FloatingPetView(model: model, honorSystemReduceMotion: false)
        // Touching body forces the SwiftUI graph to materialize once
        _ = view.body
        #expect(model.presentation.isAnimated == false)
    }
}
