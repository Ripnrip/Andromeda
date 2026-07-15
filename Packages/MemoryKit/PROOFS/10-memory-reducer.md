# Task 10 Proof — TCA MemoryReducer + TestStore

**Status:** PASS  
**Date:** 2026-07-15  
**Branch:** `anima-memory`  
**Package:** `Packages/MemoryKit`  
**Spec surface:** `syncStatus`, connection health, recent captures, visibility, materialization

## What was proven

1. **`MemoryReducer` `@Reducer` + `@ObservableState`** owns Anima's Layer-07 control plane: `syncStatus`, `connectionHealth`, `recentCaptures`, `activeVisibility`, `materializationStatus`.
2. **Visibility** dials through `VisibilityLevel` (= `VisibilityClass`) — public / friends / private / internal — shared with Security gates (no duplicate taxonomy).
3. **Sync** transitions idle → syncing → success/failed; duplicate `triggerSync` while `.syncing` is a no-op (no second effect).
4. **Materialization** streams progress events then success path *or* fail-closed `.failed(message)`.
5. **Connection health** probes Letta / Ladybug / Qdrant in parallel, then emits `connectionHealthResponse` in **deterministic alphabetical order** (Ladybug → Letta → Qdrant) — no sleep-timing flake.
6. **Recent captures** update via `databaseDidUpdate` snapshots; capture ingest calls `databaseClient.insertCapture`.
7. **Effect hygiene:** `.cancellable(id:cancelInFlight:)` on capture / sync / materialization / health effects.
8. **Name collision avoided:** TCA per-service pulse remains `HealthStatus` (healthy/unhealthy); fleet headline lanterns are `FleetHealthStatus` (green/yellow/red). `ConnectionHealthStatus` is a typealias for call-site clarity.

## Commands run

```bash
cd /Users/admin/Developer/multibrain/Packages/MemoryKit
# Prefer shared .build when free; otherwise isolate from parallel SwiftPM lock contention:
swift test --filter MemoryReducerTests \
  --scratch-path .build/reducer-scratch \
  --cache-path .build/reducer-cache
```

Swift: Apple Swift 6.2 (`swiftlang-6.2.0.19.9`), target `arm64-apple-macosx26.0`.

Log: `/tmp/memorykit-reducer-proof.log` (+ stderr `/tmp/memorykit-reducer-proof.err` on isolated runs).

## Test output summary

| Result | Count |
|--------|------:|
| PASS   | 10 |
| FAIL   | 0 |

Suite: `🎭 Anima Memory Reducer Test Stage ✨`

| Test | Proves |
|------|--------|
| `🌙 Fresh MemoryReducer.State…` | default idle / private / empty |
| `💅 Shift Active Visibility Cloak…` | public → friends → internal |
| `📥 Ingest and persist…` | capture → databaseClient |
| `☁️ Perform successful synchronization…` | syncing → success(Date) |
| `☁️ Handle failed celestial synchronization…` | syncing → failed(SyncError) |
| `🌙 Ignore duplicate sync triggers…` | guard while syncing |
| `📝 Progressively project…` | progress stream → success path |
| `🌩️ Materialization failure…` | progress → failed(message) |
| `📡 Query Letta, Ladybug, and Qdrant…` | parallel probes, alpha order |
| `📥 React immediately when background…` | recentCaptures feed |

## TCA dependency / CI weight — skip strategy

`swift-composable-architecture` pulls a large SwiftSyntax / Sharing / ConcurrencyExtras graph (~100+ compile units on cold scratch). That is **intentionally kept**:

- **Prefer green TestStore tests** (this proof) over skipping.
- **Cold CI / lock contention:** use isolated `--scratch-path` / `--cache-path` (as above) so parallel MemoryKit tasks do not serialize on `.build`.
- **If CI wall-clock is unacceptable:** keep `MemoryReducer.swift` compiling in the library target, and gate the test target with an env skip:

```bash
# Optional CI escape hatch (document-only; not enabled by default)
if [ "${MEMORYKIT_SKIP_TCA_TESTS:-}" = "1" ]; then
  echo "SKIP MemoryReducerTests — MEMORYKIT_SKIP_TCA_TESTS=1"
  exit 0
fi
swift test --filter MemoryReducerTests
```

Do **not** remove the TCA dependency solely for CI speed — Andromeda's control plane is TCA by design (`svc.memory.reducer` / `AnimaMemoryFeature` in `docs/ANDROMEDA-SURFACE-AREA.md`).

## Evidence artifacts

- Sources: `Sources/MemoryKit/TCA/MemoryReducer.swift`
- Tests: `Tests/MemoryKitTests/MemoryReducerTests.swift`
- Proof: `PROOFS/10-memory-reducer.md`
- Log: `/tmp/memorykit-reducer-proof.log`

## Remaining gaps / stubs

- Live `CloudKitSyncEngine` / vault materializer / health HTTP clients are still dependency stubs (`liveValue` returns Date / empty stream / `.unknown`).
- `databaseClient.observeCaptures` is not yet wired to an onAppear `.task` — UI injects via `databaseDidUpdate` for now.
- Andromeda mirror: synced on same branch for this milestone.

## Fixes applied during this proof

- Renamed/aliased connection pulse vs fleet headline to stop `HealthStatus` collisions with Telemetry.
- `VisibilityLevel` → typealias of `VisibilityClass`.
- Deterministic alphabetical health response ordering.
- Added cancel-in-flight effect IDs.
- Expanded TestStore coverage: defaults, duplicate sync guard, materialization failure, internal visibility.
