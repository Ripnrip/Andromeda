# Task 12 Proof — Floating Pet UI (`FloatingPetView`)

**Status:** PASS  
**Date:** 2026-07-15  
**Branch:** `anima-memory`  
**Package:** `Packages/MemoryKit`  
**Form:** proof-quality stub (MenuBarExtra host + CoreHaptics deferred to Phase 4 product wiring)

## What was proven

1. **`FloatingPetAmbientState` vocabulary** — `idle` / `syncing` / `dreaming` / `degraded` with unique VoiceOver labels, static sprite keys, and animated frame lists.
2. **`@MainActor` `FloatingPetModel`** — `@Observable` mood board; transitions and lifecycle projection stay on the main actor.
3. **Reduce-motion path** — when `reduceMotion == true`, `presentation` is always `.static(frame:)` (no animated intensity), including for syncing/dreaming/degraded.
4. **Lifecycle derivation priority** — degraded (unhealthy service or sync failure) wins over dreaming and syncing; otherwise dreaming → syncing → idle.
5. **`FloatingPetView`** — SwiftUI surface constructs on `@MainActor`, honors injectable reduce-motion (tests disable system Environment merge via `honorSystemReduceMotion: false`).

## Commands run

```bash
cd /Users/admin/Developer/multibrain/Packages/MemoryKit
swift test --filter FloatingPetViewTests \
  --scratch-path /tmp/memorykit-pet-scratch \
  --cache-path /tmp/memorykit-pet-cache
```

Swift: Apple Swift 6.2, target `arm64-apple-macos`.

Isolated scratch used to avoid SwiftPM `.build` lock contention from parallel MemoryKit agents.

## Test output summary

| Result | Count |
|--------|------:|
| PASS   | 12 |
| FAIL   | 0 |

Suite: `🔮 Floating Pet Ambient Suite` — **passed** (~0.032s runtime after build).

Covered cases:

| Test | Proves |
|------|--------|
| Ambient vocabulary | four moods present |
| Accessibility labels | unique per mood |
| Default model | idle + animatable |
| Reduce-motion static path | syncing/dreaming/degraded freeze |
| Transition ritual | MainActor mood + detail update |
| Animation intensity | idle 0.25 / degraded 1.0 |
| Resolve idle/syncing/dreaming | signal → mood mapping |
| Resolve degraded priority | unhealthy/sync-fail beats dream/sync |
| applyLifecycle | projects detail strings |
| View constructs | SwiftUI body materializes |

```text
Test run with 12 tests in 1 suite passed after 0.032 seconds.
```

## Evidence artifacts

- Log: `/tmp/memorykit-floating-pet-proof.log`
- Tests: `Tests/MemoryKitTests/FloatingPetViewTests.swift`
- Source: `Sources/MemoryKit/UI/FloatingPetView.swift`

## Remaining gaps / stubs

- No live `MenuBarExtra` / always-on-top window host (Phase 4 product shell in `multibrain-bar`).
- No CoreHaptics on state actions yet.
- Sprite names are logical keys — no asset catalog / Lottie frames wired.
- Pet-local lifecycle signals (`FloatingPetSyncSignal` / `FloatingPetDreamSignal` / `FloatingPetServiceHealth`) deliberately avoid coupling to TCA/fleet health type churn during parallel landings; adapter mapping can land when MemoryReducer + HealthSnapshot stabilize.
- Andromeda mirror: synced on same branch when feasible.

## Design notes

Reduce-motion is injectable on the model so Swift Testing can prove the static fallback without AccessibilitySettings. The view optionally merges `@Environment(\.accessibilityReduceMotion)` when `honorSystemReduceMotion` is true (default for product use).
