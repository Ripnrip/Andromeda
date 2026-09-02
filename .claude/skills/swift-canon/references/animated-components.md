# Animated Component Patterns [VK]

> Extracted from VibeKit (`~/Developer/VibeKit`) — the living SwiftUI pattern
> library built Sep 1, 2026 from web-animation references (motion.dev,
> Bklit charts, Kokonut components, Manus staged flows). Each pattern here
> has a working, Reduce-Motion-guarded implementation in VibeKit's
> `ComponentsTab.swift` / `MotionTab.swift` / `ChartsTab.swift` /
> `ManusTab.swift` / `HUDTab.swift`. Proof videos: `~/kanban-assets/vibekit-proof/`.

## Component inventory

| Component | Key techniques | Source tab |
|---|---|---|
| TypewriterText | Task.sleep char loop, cancellable, a11y label = full text | Components |
| GlitchText | 120ms timer toggle over async loop; layered offset/blur | Components |
| SwooshText | per-word stagger: blur 8→0, opacity, offset y 14→0 on appear | Components |
| AILoadingDots | repeatForever autoreverse + `.delay(Double(i) * 0.15)` stagger | Components |
| AnimatedCounter | `.contentTransition(.numericText())` + spring roll-up (response 1.2) | Components |
| SpringyCard | hover/press `scaleEffect` + shadow, separate springs per state | Motion |
| DraggableChip | `DragGesture` + spring-back to zero on end | Motion |
| LayoutSwitcher | grid↔list morph via shared identity + one container animation | Motion |
| LiveChart | TimelineView-driven streaming series (Swift Charts) | Charts |
| StagedProgress | enum stage machine → checkmark pop / spinner / completion card | Manus |

## Typewriter (character-by-character)

```swift
struct TypewriterText: View {
    let text: String
    @State private var shown = ""
    var body: some View {
        Text(shown)
            .task {
                for ch in text {
                    try? await Task.sleep(for: .milliseconds(28))
                    shown.append(ch)
                }
            }
            .accessibilityLabel(text)   // VoiceOver gets full text instantly
    }
}
```

`.task` gives auto-cancellation on disappear — prefer it over Timer loops
for one-shot reveal animations.

## Per-word swoosh entrance

Split sentence into words, `ForEach(words.indices, id: \.self)`, each word
`.blur(radius: appeared ? 0 : 8).opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14)`,
flip `appeared` once in `onAppear` with `.easeOut(duration: 0.5)`.
Guard Reduce Motion: set `appeared = true` without animation.

## Staggered infinite loop (AI dots)

```swift
Circle()
    .offset(y: phase ? -6 : 3)
    .animation(
        .easeInOut(duration: 0.4).repeatForever(autoreverses: true)
            .delay(Double(i) * 0.15),
        value: phase
    )
// .onAppear { phase = true }
```

The per-index `.delay` inside the animation modifier is what creates the wave.

## Staged progress flow (build/pairing/sync UI)

Model stages as an enum + index; each row renders its state with
symbolEffect/contentTransition as it advances; final stage triggers a
completion card transition (`.scale.combined(with: .opacity)`).
This is the "perceived performance" pattern for any multi-step wait
(pairing, sync, deploy). Launch args (`-autoBuild`) can drive a full
self-demo for video proof without GUI automation.

## Hover & press springs (cards)

Separate springs for separate state changes — fast for press
(response 0.25), softer for hover (response 0.3):

```swift
.scaleEffect(hover ? 1.04 : 1)
.scaleEffect(pressed ? 0.96 : 1)
.shadow(color: .black.opacity(hover ? 0.18 : 0.08), radius: hover ? 14 : 6, y: 4)
.animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.55), value: hover)
.animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.5), value: pressed)
```

## Live streaming chart (Swift Charts)

`TimelineView(.animation(minimumInterval: 1/30))` appending to a ring
buffer of points; `Chart` + `AreaMark`/`LineMark` redraws per tick.
Keep the buffer fixed-size (drop oldest) so memory stays flat and the
x-axis window slides instead of compressing.

## Rules that cut across all components

1. Every animation gated on `accessibilityReduceMotion` (nil animation /
   instant set / static fallback).
2. Interactive custom views get real accessibility labels/hints — the
   animated value is not the accessible value.
3. Infinite loops live in `.task`/`.onAppear` with cancellation paths;
   never an unmanaged `Timer` on a view that can disappear.
4. New components land in VibeKit first (with a Card + caption), get
   video proof, then migrate into product repos.
