import Foundation

/**
 Pop-inspired spring + decay dynamics for the Andromeda HUD.

 Facebook's [Pop](https://github.com/facebookarchive/pop) (archived) pioneered
 physics-based UI interactions — spring bounce and velocity decay. Andromeda
 does **not** link the ObjC Pop framework; we keep the feel in portable Swift
 that SwiftUI / AppKit can consume without a legacy dependency.
 */

/// Spring recipe expressed in Pop-flavored bounciness/speed plus SwiftUI-ready response/damping.
public struct HUDSpringParameters: Equatable, Sendable, Codable {
    /// Pop-style bounciness (0…20). Higher → more overshoot.
    public var bounciness: Double
    /// Pop-style speed (0…20). Higher → snappier settle.
    public var speed: Double
    /// SwiftUI `Animation.spring` response (seconds).
    public var response: Double
    /// SwiftUI damping fraction (1.0 = critically damped).
    public var dampingFraction: Double

    public init(
        bounciness: Double,
        speed: Double,
        response: Double,
        dampingFraction: Double
    ) {
        self.bounciness = min(max(bounciness, 0), 20)
        self.speed = min(max(speed, 0), 20)
        self.response = max(0.01, response)
        self.dampingFraction = min(max(dampingFraction, 0.05), 1.5)
    }

    /// Map Pop bounciness/speed into approximate SwiftUI spring parameters.
    public static func fromPop(bounciness: Double, speed: Double) -> HUDSpringParameters {
        let b = min(max(bounciness, 0), 20)
        let s = min(max(speed, 0), 20)
        // Faster Pop speed → shorter response; more bounciness → less damping.
        let response = max(0.18, 0.55 - (s / 20) * 0.32)
        let damping = max(0.55, 1.05 - (b / 20) * 0.45)
        return HUDSpringParameters(
            bounciness: b,
            speed: s,
            response: response,
            dampingFraction: damping
        )
    }
}

/// Decay coast parameters (Pop `POPDecayAnimation` analogue).
public struct HUDDecayParameters: Equatable, Sendable, Codable {
    /// Per-second exponential deceleration (higher → stops sooner). Typical Pop feel ≈ 2.0…5.0.
    public var deceleration: Double
    /// Velocity below which coasting ends (pts/s).
    public var restSpeed: Double
    /// Hard cap on simulated coast duration (seconds).
    public var maxDuration: Double

    public init(
        deceleration: Double = 3.2,
        restSpeed: Double = 12,
        maxDuration: Double = 0.45
    ) {
        self.deceleration = max(0.1, deceleration)
        self.restSpeed = max(0.1, restSpeed)
        self.maxDuration = max(0.05, maxDuration)
    }
}

/// Named motion tokens for HUD interactions.
public enum HUDPopMotion: Sendable {
    /// Expand / collapse Ask AI panel — Paper-like spring.
    public static let expand = HUDSpringParameters.fromPop(bounciness: 12, speed: 14)

    /// Menu-bar snap settle — slightly less bouncy so dock feels intentional.
    public static let snap = HUDSpringParameters.fromPop(bounciness: 8, speed: 16)

    /// Health glyph pulse intensity (subtle).
    public static let pulse = HUDSpringParameters.fromPop(bounciness: 6, speed: 10)

    /// Drag-release decay before snap resolution.
    public static let dragDecay = HUDDecayParameters()

    /// Displacement if velocity coasts forever under exponential decay:
    /// ∫ v0·e^(-d·t) dt from 0…∞ = v0 / d.
    public static func decayDisplacement(
        velocity: Double,
        deceleration: Double = HUDPopMotion.dragDecay.deceleration
    ) -> Double {
        guard deceleration > 0 else { return 0 }
        return velocity / deceleration
    }

    /**
     Coast a point under Pop-style exponential velocity decay, then return the
     projected origin (no clamping). Uses discrete steps for deterministic tests.
     */
    public static func coast(
        from origin: HUDPoint,
        velocity: HUDPoint,
        parameters: HUDDecayParameters = .init(),
        step: Double = 1.0 / 120.0
    ) -> HUDPoint {
        var x = origin.x
        var y = origin.y
        var vx = velocity.x
        var vy = velocity.y
        var elapsed = 0.0
        let dt = max(1.0 / 240.0, step)
        let damp = exp(-parameters.deceleration * dt)

        while elapsed < parameters.maxDuration {
            let speed = (vx * vx + vy * vy).squareRoot()
            if speed < parameters.restSpeed { break }
            x += vx * dt
            y += vy * dt
            vx *= damp
            vy *= damp
            elapsed += dt
        }
        return HUDPoint(x: x, y: y)
    }

    /**
     Single damped-spring integration step toward `target`.

     Uses a critically-scaled harmonic oscillator derived from response + dampingFraction
     (SwiftUI spring vocabulary) so unit tests can assert overshoot / settle without AppKit.
     */
    public static func stepSpring(
        position: Double,
        velocity: Double,
        target: Double,
        parameters: HUDSpringParameters,
        dt: Double
    ) -> (position: Double, velocity: Double) {
        // ω ≈ 2π / response; damping ratio from dampingFraction.
        let omega = (2 * Double.pi) / parameters.response
        let zeta = parameters.dampingFraction
        let x = position - target
        let acceleration = (-2 * zeta * omega * velocity) - (omega * omega * x)
        let newVelocity = velocity + acceleration * dt
        let newPosition = position + newVelocity * dt
        return (newPosition, newVelocity)
    }

    /// Integrate a spring until near rest or `maxSteps` — returns final position.
    public static func settleSpring(
        from start: Double,
        to target: Double,
        parameters: HUDSpringParameters,
        dt: Double = 1.0 / 120.0,
        maxSteps: Int = 480,
        positionEpsilon: Double = 0.35,
        velocityEpsilon: Double = 2.0
    ) -> Double {
        var position = start
        var velocity = 0.0
        for _ in 0..<maxSteps {
            let stepped = stepSpring(
                position: position,
                velocity: velocity,
                target: target,
                parameters: parameters,
                dt: dt
            )
            position = stepped.position
            velocity = stepped.velocity
            if abs(position - target) < positionEpsilon, abs(velocity) < velocityEpsilon {
                return target
            }
        }
        return position
    }
}

// MARK: - Snap + decay composition

public extension HUDSnapEngine {
    /**
     Project a drag release with Pop-style decay coast, then settle/snap.

     - Parameters:
       - proposedOrigin: Window origin at mouse-up.
       - velocity: pts/s in AppKit global coordinates (y-up).
       - size: Current chrome size.
       - screen: Visible frame + snap distance.
       - preferSnap: When true, menu-bar proximity still docks after coast.
     */
    static func settleWithDecay(
        proposedOrigin: HUDPoint,
        velocity: HUDPoint,
        size: HUDPoint,
        screen: HUDScreenMetrics,
        preferSnap: Bool = true,
        decay: HUDDecayParameters = HUDPopMotion.dragDecay
    ) -> (origin: HUDPoint, mode: HUDSnapMode, coasted: HUDPoint) {
        let coasted = HUDPopMotion.coast(
            from: proposedOrigin,
            velocity: velocity,
            parameters: decay
        )
        let settled = settle(
            proposedOrigin: coasted,
            size: size,
            screen: screen,
            preferSnap: preferSnap
        )
        return (settled.origin, settled.mode, coasted)
    }
}
