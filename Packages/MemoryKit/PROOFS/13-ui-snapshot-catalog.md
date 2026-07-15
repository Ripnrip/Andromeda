# Task 13 Proof — UI Snapshot Catalog (CommandCenter + FloatingPet)

**Status:** PASS  
**Date:** 2026-07-15  
**Branch:** `feat/memorykit-ui-snapshots`  
**Package:** `Packages/MemoryKit`  
**Scope:** Pixel-perfect SnapshotTesting catalog + comprehensive `#Preview` matrix

## What was proven

1. **`pointfreeco/swift-snapshot-testing` (≥1.18)** added to `Package.swift` alongside TCA; `MemoryKitTests` links `SnapshotTesting`.
2. **CommandCenter `#Preview` catalog** — 16 variants: states `healthy` / `degraded` / `syncing` / `emptyIntents` × light/dark × `.medium` / `.accessibility2`.
3. **FloatingPet `#Preview` catalog** — representative ambient × reduceMotion × scheme × Dynamic Type coverage (full matrix in tests).
4. **XCTest snapshot suites** (macOS host):
   - `CommandCenterSnapshots` — **16** PNGs (4 states × 2 schemes × 2 type sizes)
   - `FloatingPetSnapshots` — **32** PNGs (4 ambient × 2 reduceMotion × 2 schemes × 2 type sizes)
5. **macOS hosting path** — SnapshotTesting’s SwiftUI `.image(layout:)` is iOS/tvOS-only; catalog hosts via `NSHostingView` + `NSView` `.image` strategy.
6. **Record → verify** — `SNAPSHOT_TESTING_RECORD=all` wrote `__Snapshots__`; `SNAPSHOT_TESTING_RECORD=never` re-run **passed** (0 failures).
7. **Build unblocker** — `AnimaStorageError: Equatable` so `RetrievalServiceError` can synthesize `Equatable` under Swift 6.

## Matrix

| Surface | States | Axes | Count |
|---------|--------|------|------:|
| CommandCenter | healthy, degraded, syncing, emptyIntents | light/dark × medium/a11y2 | 16 |
| FloatingPet | idle, syncing, dreaming, degraded | × motion/reduceMotion × light/dark × medium/a11y2 | 32 |
| **Total PNGs** | | | **48** |

## Commands run

```bash
cd /tmp/memorykit-ui-snapshots-wt/Packages/MemoryKit   # isolated worktree
SNAPSHOT_TESTING_RECORD=all swift test \
  --filter 'CommandCenterSnapshots|FloatingPetSnapshots' \
  --scratch-path /tmp/mk-snap-wt-scratch \
  --cache-path /tmp/mk-snap-wt-cache

SNAPSHOT_TESTING_RECORD=never swift test \
  --filter 'CommandCenterSnapshots|FloatingPetSnapshots' \
  --scratch-path /tmp/mk-snap-wt-scratch \
  --cache-path /tmp/mk-snap-wt-cache
```

Swift: Apple Swift 6.2+, target `arm64-apple-macos`. Host macOS required (AppKit `NSHostingView`).

## Test output summary (verify pass)

| Suite | Result | Runtime |
|-------|--------|---------|
| `CommandCenterSnapshots` | PASS (1 test, 0 failures) | ~0.286s |
| `FloatingPetSnapshots` | PASS (1 test, 0 failures) | ~0.091s |

```text
Executed 2 tests, with 0 failures (0 unexpected) in 0.377 seconds.
```

## Evidence artifacts

- Log (record): `/tmp/memorykit-ui-snapshots-proof.log`
- Log (verify): `/tmp/memorykit-ui-snapshots-verify.log`
- Tests: `Tests/MemoryKitTests/Snapshots/{CommandCenter,FloatingPet}Snapshots.swift`
- Support: `Tests/MemoryKitTests/Snapshots/SnapshotCatalogSupport.swift`
- PNGs: `Tests/MemoryKitTests/Snapshots/__Snapshots__/{CommandCenter,FloatingPet}Snapshots/`
- Sources: `Sources/MemoryKit/UI/{CommandCenterView,FloatingPetView}.swift`
- Dep: `Package.swift` → `swift-snapshot-testing`

## Re-record

```bash
SNAPSHOT_TESTING_RECORD=all swift test --filter 'CommandCenterSnapshots|FloatingPetSnapshots'
# then commit updated __Snapshots__ PNGs
SNAPSHOT_TESTING_RECORD=never swift test --filter 'CommandCenterSnapshots|FloatingPetSnapshots'
```

## Remaining gaps / stubs

- No iOS UIImage SwiftUI strategy in this catalog (package platforms include iOS; snapshots are macOS-hosted).
- Intent ledger still not rendered in CommandCenter chrome — `emptyIntents` is badge/state emptiness, not a visible list.
- Parallel agent worktrees may still race the primary checkout; prefer this branch’s worktree for snapshot runs.

## Tracking

- Linear: comment on BIN-25 (UI snapshot catalog follow-on)
- Multica: HAB link under Anima Memory / Andromeda when created
