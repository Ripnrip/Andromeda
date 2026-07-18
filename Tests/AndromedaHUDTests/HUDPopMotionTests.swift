import Testing
@testable import AndromedaHUD

/// Pop-inspired spring + decay proofs — portable dynamics, no ObjC Pop link.
@Suite("HUD Pop motion")
struct HUDPopMotionTests {
    @Test("Pop bounciness maps to lower damping / snappier response")
    func testFromPopMapping() {
        let soft = HUDSpringParameters.fromPop(bounciness: 2, speed: 4)
        let lively = HUDSpringParameters.fromPop(bounciness: 16, speed: 18)
        #expect(lively.dampingFraction < soft.dampingFraction)
        #expect(lively.response < soft.response)
        #expect(HUDPopMotion.expand.bounciness == 12)
        #expect(HUDPopMotion.snap.speed == 16)
    }

    @Test("Decay displacement equals velocity over deceleration")
    func testDecayDisplacement() {
        let d = HUDPopMotion.decayDisplacement(velocity: 320, deceleration: 3.2)
        #expect(abs(d - 100) < 0.001)
        #expect(HUDPopMotion.decayDisplacement(velocity: 0) == 0)
    }

    @Test("Coast projects forward then stops under rest speed")
    func testCoastProjectsForward() {
        let start = HUDPoint(x: 100, y: 200)
        let coasted = HUDPopMotion.coast(
            from: start,
            velocity: HUDPoint(x: 600, y: 0),
            parameters: HUDDecayParameters(deceleration: 4, restSpeed: 20, maxDuration: 0.5)
        )
        #expect(coasted.x > start.x)
        #expect(abs(coasted.y - start.y) < 0.001)
    }

    @Test("Spring settle approaches target and can overshoot when bouncy")
    func testSpringSettleAndOvershoot() {
        let bouncy = HUDSpringParameters.fromPop(bounciness: 18, speed: 12)
        var position = 0.0
        var velocity = 0.0
        var sawOvershoot = false
        for _ in 0..<240 {
            let stepped = HUDPopMotion.stepSpring(
                position: position,
                velocity: velocity,
                target: 100,
                parameters: bouncy,
                dt: 1.0 / 120.0
            )
            position = stepped.position
            velocity = stepped.velocity
            if position > 100 { sawOvershoot = true }
        }
        #expect(sawOvershoot)
        let settled = HUDPopMotion.settleSpring(from: 0, to: 100, parameters: HUDPopMotion.snap)
        #expect(abs(settled - 100) < 1.0)
    }

    @Test("settleWithDecay coasts then clamps into visible frame")
    func testSettleWithDecay() {
        let screen = HUDScreenMetrics(
            visibleFrame: HUDRect(x: 0, y: 0, width: 1440, height: 900),
            snapDistance: 28
        )
        let size = HUDSnapEngine.collapsedSize
        let proposed = HUDPoint(x: 40, y: 400)
        let result = HUDSnapEngine.settleWithDecay(
            proposedOrigin: proposed,
            velocity: HUDPoint(x: 800, y: 0),
            size: size,
            screen: screen
        )
        #expect(result.coasted.x > proposed.x)
        #expect(result.origin.x >= 0)
        #expect(result.origin.x <= 1440 - size.x)
        #expect(result.mode == .floating)
    }

    @Test("Fast upward flick near menu bar still snaps after decay")
    func testDecayThenMenuBarSnap() {
        let screen = HUDScreenMetrics(
            visibleFrame: HUDRect(x: 0, y: 0, width: 1440, height: 900),
            snapDistance: 48
        )
        let size = HUDSnapEngine.collapsedSize
        // Start just outside the snap band; upward velocity coasts into the dock zone.
        let proposed = HUDPoint(x: 200, y: screen.menuBarDockY - size.y - 70)
        let result = HUDSnapEngine.settleWithDecay(
            proposedOrigin: proposed,
            velocity: HUDPoint(x: 0, y: 900),
            size: size,
            screen: screen,
            decay: HUDDecayParameters(deceleration: 2.0, restSpeed: 8, maxDuration: 0.8)
        )
        #expect(result.coasted.y > proposed.y)
        #expect(result.mode == .menuBar)
        #expect(abs(result.origin.y - (screen.menuBarDockY - size.y)) < 0.001)
    }
}
