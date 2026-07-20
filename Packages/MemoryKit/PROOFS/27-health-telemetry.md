# BIN-27 Proof — Health Telemetry (`HealthSnapshot`)

**Status:** PASS  
**Date:** 2026-07-15  
**Branch:** `anima-memory`  
**Package:** `Packages/MemoryKit`  
**Entity:** `telemetry.health_json` → `HealthSnapshot` (Andromeda console + future n8n)

## What was proven

1. **§9 shape decode** — Studio green fixture parses `status`, `checked_at`, `last_success`, nine named checks, and `baselines` (`notes_7d_avg` / `obs_7d_avg`).
2. **Satellite honesty** — `ok: null` and/or `status: "n/a"` (Book-style Ladybug/Letta/graph skips) never join `failingCheckNames` and do **not** force derived red.
3. **Fail closed on corruption** — empty / truncated / non-object / garbage JSON → `FleetHealthStatus.unknown`; `isGreen` is always false (never a forged green).
4. **Missing file** — load from a non-existent temp path → unknown (no live `~/.multibrain` required).
5. **Mixed failures** — only literal `ok: false` contributes; n/a siblings stay out of the red list.
6. **Naming** — fleet headline is `FleetHealthStatus` (green/yellow/red/unknown), distinct from TCA `HealthStatus` (healthy/unhealthy) so console entities do not collide.

## Commands run

```bash
cd /Users/admin/Developer/multibrain/Packages/MemoryKit
swift test --build-path /tmp/memorykit-bin27-build --filter HealthSnapshotTests
```

Swift: Apple Swift 6.2 (`swiftlang-6.2.0.19.9`), target `arm64-apple-macosx26.0`.

## Test output summary

| Result | Count |
|--------|------:|
| PASS   | 11 |
| FAIL   | 0 |

Suite: `🩺 Health Snapshot / Agent Telemetry (BIN-27)` — **passed**.

Covered cases:

| Test | Proves |
|------|--------|
| `🟢 Studio green fixture…` | §9 happy path, 9 checks |
| `🛰️ Satellite n/a checks…` | null/n/a ≠ failure / ≠ red |
| `🛰️ ok:null alone…` | null without status field still n/a |
| `🔴 Only ok:false contributes…` | mixed red + n/a sibling |
| `💥 Corrupt JSON yields unknown…` | never fake green |
| `🔮 Missing status field…` | fail closed |
| `🔮 Garbage status string…` | unknown |
| `📂 Missing file path…` | no live home required |
| `📂 Fixture file round-trip…` | disk load via temp fixture |
| `🟡 Yellow headline…` | yellow + needsAttention |
| `💎 Unknown factory…` | static unknown never green |

## Evidence artifacts

- Log: `/tmp/memorykit-health-telemetry-proof.log`
- Tests: `Tests/MemoryKitTests/HealthSnapshotTests.swift`
- Sources:
  - `Sources/MemoryKit/Telemetry/HealthSnapshot.swift`
  - `Sources/MemoryKit/Telemetry/HealthSnapshotLoader.swift`

## Remaining gaps / stubs

- Loader does not yet watch `health.json` via FSEvents / Combine (console poll wiring is Andromeda/n8n follow-up).
- Does not invoke `healthcheck.py` — read-only Observe spine over the existing Python SoT.
- Andromeda mirror: synced on same branch for this milestone.

## Fixes applied during this proof

- Named fleet status `FleetHealthStatus` to avoid colliding with TCA connection `HealthStatus`.
- ISO8601 formatter built per-call (Sendable-safe under Swift 6).
