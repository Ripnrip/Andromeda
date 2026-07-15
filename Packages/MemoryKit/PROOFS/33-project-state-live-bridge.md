# Proof 33 — Live `project.state` → Linear∪Multica Bridge

**Status:** PASS (Multica live; Linear live via dotenv/`LINEAR_API_KEY`)  
**Date:** 2026-07-15  
**Branch:** `feat/project-state-live-bridge`  
**Package:** `Packages/MemoryKit`  
**Capability IDs:** `project.state.list` · `get` · `create` · `update`  
**Linear:** BIN-39 (follow-on BIN-34 / BIN-37)  
**Multica:** HAB-56 (follow-on HAB-48 / HAB-51)

## What was proven

1. **`LiveMulticaProjectProvider`** — Habitat HTTP list/create (`:3637` + `~/.multica` token); update via `multica` CLI (HTTP PATCH returns 405).
2. **`LiveLinearProjectProvider`** — GraphQL adapter ready; requires `LINEAR_API_KEY` (unset on Studio → soft Multica-only path, no fake green).
3. **`ProjectStateBridgeFactory.makeStudioBridge()`** — env + Multica config loader; never logs tokens.
4. **Fan-out create** — Linear first when keyed → Multica with `Linear: BIN-*` description; Multica-only when Linear unwired.
5. **Fan-out update** — patches both trackers when provenance known after merge.
6. **Title sanitization** — strips `BIN-*` / `HAB-*` / `[Linear …]` from client titles so Codable JSON stays brand-neutral.
7. **Curtain intact** — client JSON has no `provenance`, no tracker URLs, no Linear/Multica brand strings.

## Commands run

```bash
cd Packages/MemoryKit
swift test --filter ProjectStateSurfaceTests
MULTICA_LIVE=1 swift test --filter LiveMulticaProjectStateTests
```

## Test output summary

| Suite | Result | Count |
|-------|--------|------:|
| `🎭 Project State Capability Rituals` | PASS | 11 |
| `🌐 Live Multica project.state` (`MULTICA_LIVE=1`) | PASS | 2 |
| Snapshots (filter overlap) | PASS | 4 |
| **Live+unit ProjectState** | **PASS** | **13** |

Live Studio: merged **27** Habitat issues into brand-neutral `project.state` items; create landed as HAB-61 (cancelled after smoke).

## Evidence artifacts

- Sources:
  - `Sources/MemoryKit/ProjectState/LiveProjectProviders.swift`
  - `Sources/MemoryKit/ProjectState/OperatorProjectStateBridge.swift`
- Tests:
  - `Tests/MemoryKitTests/ProjectStateSurfaceTests.swift`
  - `Tests/MemoryKitTests/LiveMulticaProjectStateTests.swift`
- Logs: `/tmp/memorykit-ps-rerun.log`

## Residuals / human follow-ups

- `LINEAR_API_KEY` loads from process env **or** `~/Developer/multibrain/.env` / `~/.multibrain/.env` (process env wins; values never logged).
- Optional: set `LINEAR_TEAM_ID` / `LINEAR_PROJECT_ID` in the same dotenv if defaults need override.
- Cancel leftover probe issues HAB-54…HAB-61 if any remain open (smoke probes).
- Dual-home sync into Andromeda `Packages/MemoryKit` after Linear dotenv fix lands.

## Linear dotenv verification (2026-07-15)

| Check | Result |
|-------|--------|
| Dotenv unit parse (synthetic key) | PASS |
| Factory wires LiveLinear when key present | PASS |
| Live GraphQL list (`LiveLinearProjectStateTests`) | PASS — 30 brand-neutral items |
| Soft-skip when key absent | still honest (NullLinear) |
