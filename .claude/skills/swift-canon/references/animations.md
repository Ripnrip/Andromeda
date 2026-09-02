# Animations

> Provenance note: patterns below marked **[VK]** are battle-tested in
> VibeKit (`~/Developer/VibeKit`, the living pattern library); **[ML]**
> in Morphling (`~/Developer/Morphling`, floating shape-morphing HUD).
> Full component inventory: VibeKit `UI-LESSONS.md`.

## Core rules

- `.animation(_:value:)` — **always** pass `value:`
- `withAnimation` for event-driven changes (taps, gestures)
- Prefer **transforms** (`scale`, `offset`, `rotation`) over `frame` animation
- Transitions paired with animation **outside** conditional structure
- Later `.animation` in tree wins over earlier (implicit override)
- **[VK] Reduce Motion everywhere or it's not done**: every animated view
  reads `@Environment(\.accessibilityReduceMotion)` and passes `nil`
  animation or instant-set when true. See the `reduceMotion ? nil : .spring(...)`
  idiom — it appears in every VibeKit tab.

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

## Spring vocabulary [VK]

Named, reusable spring recipes (motion.dev feel, native):

| Feel | Spring | Used for |
|---|---|---|
| Snappy tap | `.spring(response: 0.25, dampingFraction: 0.45)` | icon bounce on tap |
| Playful settle | `.spring(response: 0.3, dampingFraction: 0.5)` | drag spring-back |
| UI reveal | `.spring(response: 0.4, dampingFraction: 0.75)` | HUD summon/dismiss |
| Layout relayout | `.spring(response: 0.45, dampingFraction: 0.8)` | grid↔list switch |
| Counter roll-up | `.spring(response: 1.2, dampingFraction: 0.85)` | numeric settle, no wobble |

Bounce-with-recover pattern (tap feedback that returns on its own):

```swift
withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { bounce = true }
Task {
    try? await Task.sleep(for: .milliseconds(180))
    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { bounce = false }
}
```

## Drag with spring-back [VK]

```swift
.gesture(
    DragGesture()
        .onChanged { offset = $0.translation }
        .onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { offset = .zero } }
)
```

Always add `.accessibilityHint("Draggable; springs back when released")` —
drag-only interactions are invisible to VoiceOver otherwise.

## Animated layout switch (grid ↔ list) [VK]

Same `ForEach` identity inside both layouts; a single `.animation(..., value: grid)`
on the container morphs between `LazyVGrid` and `VStack` — no transitions needed.
Do NOT give items new ids per layout or the morph becomes remove+insert.

## Transitions

```swift
.transition(.asymmetric(
    insertion: .scale(scale: 0.92).combined(with: .opacity),
    removal: .opacity
))
```

**[VK] HUD summon transition** — scale-from-slightly-larger for overlay panels:

```swift
.transition(reduceMotion ? .opacity : .asymmetric(
    insertion: .scale(scale: 1.06).combined(with: .opacity),
    removal: .opacity
))
```

## Text & symbol motion [VK]

- Animated counters: `Text` + `.contentTransition(.numericText())` +
  `.monospacedDigit()` (`.system(design: .rounded)` for stat displays),
  spring roll-up on appear:
  ```swift
  .contentTransition(.numericText())
  .onAppear { withAnimation(.spring(response: 1.2, dampingFraction: 0.85)) { value = Double(target) } }
  ```
  Keep an `.accessibilityLabel("\(target)")` so VoiceOver reads the final value,
  not the animation frames.
- Staged task lists: each row gets `.contentTransition(.numericText())` /
  symbolEffect progress states as it advances (checkmark pop, spinner, done).
- Stagger-by-index for waves: `.delay(Double(i) * 0.15)` on repeatForever
  animations (AI loading dots).
- Glitch text: timer-driven 120ms `glitching` toggle over Task.sleep loop —
  never let a glitch loop run without cancellation.

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

## Shape morphing (custom Shape) [ML]

Dynamic organic shapes = parameterized `Shape` + animated parameters.
`BlobShape` (Morphling): radius modulated by `wildness` (0 circle → 1 wild
star), `sides`, and time-`phase`; animate the **parameters**, and SwiftUI
interpolates the path. Frame size changes ride the same spring as the shape.

```swift
struct BlobShape: Shape {
    var wildness: CGFloat   // 0.0 = circle … 1.0 = wild abstract star
    var sides: Int          // 3 triangle-ish … 32+ = round
    var phase: CGFloat      // animated over time for organic wobble
    func path(in rect: CGRect) -> Path {
        // polar polygon: r * (1 - wildness*0.5*(0.5+0.5*sin(3t+phase…)))
        //                * (1 + wildness*0.35*sin(sides*t + phase*1.7))
    }
}
// usage: animate wildness/sides together — circle → abstract → card all morph
.animation(.spring(response: 0.55, dampingFraction: 0.62), value: form)
```

Also set `.contentShape(BlobShape(...))` with the same parameters so the
hit region follows the morph.

**`animatableData` is required or params jump, not morph.** `Shape` defaults
to empty animation data — stored properties are NOT auto-animatable. Expose
every interpolatable parameter, and represent integer-ish params (like side
count) as `CGFloat` so they interpolate:

```swift
extension BlobShape {
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(wildness, AnimatablePair(sides, phase)) }
        set {
            wildness = newValue.first
            sides = Int(newValue.second.first.rounded())
            phase = newValue.second.second
        }
    }
}
// store `sides` as CGFloat in the Shape; snap with .rounded() in the setter
```

## Escalating morph theater (sequenced form chain) [ML]

The "dance between forms" pattern — orb → wild dance → snap to target:

```swift
func escalate(to target: Form) async {
    withAnimation(.easeIn(duration: 0.5)) { form = .dance; wildness = 0.85 }
    burstParticles()
    try? await Task.sleep(for: .milliseconds(1300))   // dance (timer animates phase)
    withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
        form = target; wildness = target == .orb ? 0.12 : 0.3
    }
    popParticles(); beamSweepNow()
    if target == .card {                              // scanline "thinking" shimmer
        scanline = true
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation { scanline = false }
    }
}
```

Rules: continuous idle (breathing orb, wobble timer @30fps advancing `phase`)
+ discrete event escalation + celebration punctuation (particles, beam sweep,
confetti). Ask the user which pop/beam "razzle-dazzle" level they want before
building celebration effects — it's a taste call, not a default.

## Floating HUD overlay (macOS) [ML]

- Borderless `NSPanel` (`.nonactivatingPanel`, `.floating` level,
  `collectionBehavior` `[.canJoinAllSpaces, .stationary]`) hosting SwiftUI —
  floats over all windows/spaces like a companion.
- Overlay content sits on `ignoresSafeArea` gradient backdrop; summon/dismiss
  via asymmetric scale+opacity transition (above).

## Completion (iOS 17+)

Use `.transaction(value:)` for animation completion reexecution.

## Performance

- No per-frame layout animation
- `symbolEffect(.rotate, isActive:)` for spinners (iOS 17+ / macOS 14+)
- **[ML]** continuous ambient loops (wobble/breathing) via one 30fps
  `Timer` mutating a phase `@State` — cheap, pausable, and everything
  (shape, shimmer offset, glow pulse) derives from that one value.
- **[VK]** video is the proof artifact for animation work — screenshots
  don't prove motion (canon: UI builds deliver video/screenshot proof).
  Fragility note: `simctl recordVideo` must be SIGINT'd at the real pid and
  waited on; zombie recordVideo wedges simulator IO — screenshot-frame
  diffing is the fallback.

## Reduce Motion

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
// nil animation or static fallback when true
```

See `motion-haptics.md`.
