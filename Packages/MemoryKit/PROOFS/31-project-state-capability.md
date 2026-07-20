# Proof 31 — `project.state` Capability Curtain

**Status:** PASS  
**Date:** 2026-07-15  
**Branch:** `feat/project-state-capability`  
**Package:** `Packages/MemoryKit`  
**Capability IDs:** `project.state.list` · `project.state.get` · `project.state.create` · `project.state.update`

## What was proven

1. **`ProjectStateSurface` protocol** — four client-facing CRUD verbs with stable capability ID comments; no Linear/Multica brands in the API.
2. **`ProjectState` public shape** — `id`, `title`, `status`, `items` only. Optional `provenance` is operator-internal and **stripped from Codable** (no `BIN-*` / `HAB-*` / `linear.com` in client JSON).
3. **`InMemoryProjectStateStore`** — actor-backed list/get/create/update for tests and offline demos.
4. **`OperatorProjectStateBridge` stub** — injects `LinearProjectProvider` + `MulticaProjectProvider` protocols; merges mock fragments into brand-neutral items with opaque SHA256 item IDs; TODOs mark live Linear∪Multica wiring.
5. **`ProjectStatePanel`** — SwiftUI panel + light/dark `#Preview`s; chrome says `project.state`, never tracker names.
6. **SnapshotTesting (4)** — light / dark / empty / loading via `NSHostingController` (macOS; SnapshotTesting SwiftUI `.image` is iOS/tvOS-only).
7. **Build unblocker** — `AnimaStorageError: Equatable` so `RetrievalServiceError` synthesizes Equatable again.

## Commands run

```bash
cd /tmp/multibrain-project-state/Packages/MemoryKit   # worktree of feat/project-state-capability
swift test --filter 'ProjectState' \
  --scratch-path /tmp/mk-ps-scratch \
  --cache-path /tmp/mk-ps-cache
```

Swift: Apple Swift 6.2, target `arm64-apple-macosx14.0`.

## Test output summary

| Suite | Result | Count |
|-------|--------|------:|
| `ProjectStatePanelSnapshotTests` (XCTest) | PASS | 4 |
| `🎭 Project State Capability Rituals ✨` (Swift Testing) | PASS | 7 |
| **Total** | **PASS** | **11** |

| Test | Proves |
|------|--------|
| list sorted by title | `project.state.list` |
| get + not-found | `project.state.get` |
| create + update | `project.state.create` / `update` |
| Codable strips provenance | no tracker IDs/URLs in client JSON |
| no URL fields on public types | structural curtain |
| operator bridge merge | Linear+Multica mocks → brand-neutral items |
| null providers soft path | empty Andromeda board when unwired |
| snapshots light/dark/empty/loading | UI stills |

## Evidence artifacts

- Log: `/tmp/memorykit-project-state-proof2.log`
- Snapshots: `Tests/MemoryKitTests/__Snapshots__/ProjectStatePanelSnapshotTests/`
- Sources:
  - `Sources/MemoryKit/ProjectState/`
  - `Sources/MemoryKit/UI/ProjectStatePanel.swift`

## Remaining gaps / stubs

- Live Linear GraphQL + Multica Habitat HTTP not wired — protocols + mocks only.
- Create/update on the bridge stay cache-local until provider fan-out lands.
- Dual-home copy into `~/Developer/Andromeda/Packages/MemoryKit` deferred until MemoryKit is battle-tested live.
