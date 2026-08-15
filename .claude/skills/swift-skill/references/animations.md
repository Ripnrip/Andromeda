# Animations

## Core rules

- `.animation(_:value:)` — **always** pass `value:`
- `withAnimation` for event-driven changes (taps, gestures)
- Prefer **transforms** (`scale`, `offset`, `rotation`) over `frame` animation
- Transitions paired with animation **outside** conditional structure
- Later `.animation` in tree wins over earlier (implicit override)

## Implicit vs explicit

```swift
withAnimation(.spring(duration: 0.35)) {
    isExpanded.toggle()
}
```

```swift
.scaleEffect(scale)
.animation(.easeInOut(duration: 0.55), value: scale)
```

## Transitions

```swift
.transition(.asymmetric(
    insertion: .scale(scale: 0.92).combined(with: .opacity),
    removal: .opacity
))
```

## Phase & keyframe (iOS 17+)

```swift
.phaseAnimator([false, true], trigger: isActive) { content, phase in
    content.scaleEffect(phase ? 1.1 : 1.0)
} animation: { _ in .easeInOut(duration: 0.5) }
```

```swift
.keyframeAnimator(initialValue: Values(), trigger: mood) { content, values in
    content.scaleEffect(values.scale)
} keyframes: { _ in
    KeyframeTrack(\.scale) {
        LinearKeyframe(1.08, duration: 0.55)
        LinearKeyframe(1.0, duration: 0.55)
    }
}
```

## Animatable

Custom `Animatable` requires explicit `animatableData`.

## Completion (iOS 17+)

Use `.transaction(value:)` for animation completion reexecution.

## Performance

- No per-frame layout animation
- `symbolEffect(.rotate, isActive:)` for spinners (iOS 17+ / macOS 14+)

## Reduce Motion

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
// nil animation or static fallback when true
```

See `motion-haptics.md`.
