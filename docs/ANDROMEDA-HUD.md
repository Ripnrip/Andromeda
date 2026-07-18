# Andromeda HUD — Modern Floating Control Surface

**Status:** Foundation (BIN-55 epic)  
**Linear:** [BIN-55](https://linear.app/binary-bros/issue/BIN-55) · [BIN-56](https://linear.app/binary-bros/issue/BIN-56) · [BIN-57](https://linear.app/binary-bros/issue/BIN-57) · [BIN-58](https://linear.app/binary-bros/issue/BIN-58) · [BIN-59](https://linear.app/binary-bros/issue/BIN-59) · [BIN-60](https://linear.app/binary-bros/issue/BIN-60)

Modern macOS floating HUD that replaces opaque floating-bar chrome with a visible, draggable, capability-safe control surface. Inspired by Openscreen, Screendrop, and Ice.

## Module

`AndromedaHUD` (root Swift package target)

| File | Role |
| --- | --- |
| `AndromedaHUDModel` | `@MainActor` `@Observable` state — expansion, snap, health, Ask AI ledger |
| `HUDGeometry` / `HUDSnapEngine` | Portable Ice-style menu-bar snap math (Linux-testable) |
| `HUDSearchRouter` | Routes Ask AI text → `memory.*` / `infer.write` (no tracker brands) |
| `HUDPerformanceBudget` | Sub-16ms / sub-50ms latency budgets (BIN-59) |
| `HUDPopMotion` | Pop-inspired spring + decay (portable; **no** ObjC Pop link) |
| `AndromedaHUDView` | Modern SwiftUI pill + expandable search (AppKit platforms) |
| `AndromedaHUDWindowController` | Borderless `NSPanel`, drag handle, floating level (BIN-60) |

## Motion (Pop-inspired, not Pop-linked)

[facebookarchive/pop](https://github.com/facebookarchive/pop) is archived Objective-C. Andromeda keeps the **feel** (spring expand, velocity decay on drag release) in Swift:

- `HUDPopMotion.expand` / `.snap` — bounciness/speed → SwiftUI `Animation.spring`
- `HUDSnapEngine.settleWithDecay` — coast with exponential decay, then Ice snap
- Reduce Motion → short ease-in-out, no bounce / no scale pop

## Capability curtain

Clients see only:

- `memory.recall` / `memory.store` / `memory.journal`
- `infer.write`

Never Linear, Multica, Habitat, or provider brands in HUD chrome or search tips.

## Form factor

1. **Collapsed pill** — drag handle, health glyph, Andromeda brand, Ask AI button; ultra-thin material + dark wash.
2. **Expanded panel** — Screendrop-style search field; verbs `recall`, `store`, `journal`, or free-form Ask AI.
3. **Snap** — release near the menu bar docks flush underneath; otherwise floats and clamps to the visible frame.

## Tests

```console
swift test --filter AndromedaHUDTests
```

- Logic tests (snap, search, model, budgets) run on Linux and macOS.
- Point-Free SnapshotTesting catalog (`Tests/AndromedaHUDTests/AndromedaHUDSnapshotTests.swift`) requires macOS AppKit; goldens under `__Snapshots__/`.
- Record goldens on a Mac: `SNAPSHOT_TESTING_RECORD=all swift test --filter AndromedaHUDSnapshotTests`.

## Visibility

The HUD is an explicit operator surface — not a LaunchAgent, not a hidden watchdog. Present/dismiss goes through `AndromedaHUDWindowController`.

## Out of scope (follow-on)

- Live `memory.*` / gateway wiring (stub ledger only today)
- Menu-bar status item host app target
- CoreHaptics / multi-display edge cases beyond metrics conversion
