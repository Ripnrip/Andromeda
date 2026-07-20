# BIN-26b Proof — LaunchEntity Observe UI + Day-1 Telemetry

**Status:** PASS  
**Date:** 2026-07-15  
**Branch:** `feat/launch-entity-observe-ui`  
**Package:** `Packages/MemoryKit`  
**Observe-first:** mock launchctl only — no kickstart / bootstrap / unload

## What was proven

1. **`LaunchEntityRegistry.refresh()` telemetry** — after status resolve, emits `LaunchEntityRefreshTelemetry` with counts by status (`running` / `stopped` / `n/a`), `isolatedMiniFlagged` when the Mini tunnel lane is present, and `displaySummary` for console/logs. `refreshStatuses()` stays silent (no pulse).
2. **Injectable sinks** — `NullLaunchEntityTelemetrySink` (hermetic), `PrintingLaunchEntityTelemetrySink` (day-1 breadcrumb), `RecordingLaunchEntityTelemetrySink` (tests).
3. **`LaunchEntityRosterView`** — visible SwiftUI playbill with four states: `loading` / `empty` / `hub-full` / `satellite-na`. Marquee + telemetry strip + entity rows make the roster impossible to ignore; Mini lane shows `NON-HIVE` / isolated chip.
4. **Preview matrix** — 12 `#Preview`s covering light/dark × all four states + Dynamic Type (`.accessibility3`) + reduce-motion variants.
5. **SnapshotTesting catalog** — 12 PNGs under `Tests/MemoryKitTests/__Snapshots__/LaunchEntityRosterSnapshotTests/` (`LaunchEntityRoster.*`). macOS hosts SwiftUI via `NSHostingView` (SwiftUI `.image(layout:)` is iOS/tvOS-only).

## Commands run

Isolated worktree build (parallel MemoryKit agents were mutating the main checkout):

```bash
cd /tmp/memorykit-26b-wt/Packages/MemoryKit
SNAPSHOT_TESTING_RECORD=1 swift test --build-path /tmp/memorykit-26b-wt-build --filter 'LaunchEntity'
# then verify without record:
swift test --build-path /tmp/memorykit-26b-wt-build --filter 'LaunchEntity'
```

Swift: Apple Swift 6.2, target `arm64-apple-macos`.

## Test output summary

| Layer | Result |
|-------|--------|
| Swift Testing (`LaunchEntity*` suites) | **23/23 PASS** |
| XCTest SnapshotTesting (`LaunchEntityRosterSnapshotTests`) | **12/12 PASS** |
| Snapshot PNGs | **12** |

Suites:

| Suite | Proves |
|-------|--------|
| `🚀 LaunchEntity Registry Suite` | catalog + observe (existing) |
| `📡 Launch Entity Refresh Telemetry Suite` | refresh pulse + Mini flag + silent refreshStatuses |
| `🎪 Launch Entity Roster View Suite` | states / apply(registry) / fixtures / reduce-motion |
| `LaunchEntityRosterSnapshotTests` | pixel catalog light/dark/a11y/reduce-motion |

## Evidence artifacts

- Log (verify): `/tmp/memorykit-26b-verify.out`
- Snapshots: `Tests/MemoryKitTests/__Snapshots__/LaunchEntityRosterSnapshotTests/LaunchEntityRoster.*.png` (12)
- Sources:
  - `Sources/MemoryKit/Telemetry/LaunchEntityRefreshTelemetry.swift`
  - `Sources/MemoryKit/Registry/LaunchEntityRegistry.swift` (`refresh()`)
  - `Sources/MemoryKit/UI/LaunchEntityRosterView.swift`
- Tests:
  - `Tests/MemoryKitTests/LaunchEntityRefreshTelemetryTests.swift`
  - `Tests/MemoryKitTests/LaunchEntityRosterViewTests.swift`
  - `Tests/MemoryKitTests/LaunchEntityRosterSnapshotTests.swift`

## Remaining gaps / stubs

- Live `launchctl print` adapter still Null/Mock — Andromeda console boundary next.
- Kickstart / bootstrap / unload still intentionally absent.
- Roster is proof-quality UI (not yet wired into multibrain-bar MenuBarExtra host).

## Fixes applied during this proof

- Restored `AnimaStorageError: Equatable` so `RetrievalServiceError` synthesizes Equatable (package build unblock).
- macOS SnapshotTesting path uses `NSHostingView` + `.image(size:)` instead of iOS-only SwiftUI layout strategy.
