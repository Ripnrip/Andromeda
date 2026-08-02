# PROOF 31 — Swift Fleet Observe (LaunchEntity × health × :8286)

**Date:** 2026-07-17  
**Lane:** MemoryKit (multibrain + Andromeda dual-home) + MultibrainBar  
**Rule:** Observe in Swift — no Python cron patches.

## What shipped

1. **`LiveLaunchctlObserver`** — real `launchctl list <label>` → `LaunchObservation` (PID + `LastExitStatus`)
2. **`LaunchEntityAttention`** — `ok` / `idle` / `degraded` / `critical` / `n/a` (cron idle ≠ red)
3. **`IndexServerHealthClient`** — sync GET `http://127.0.0.1:8286/health` (1.5s, satellite skip)
4. **`FleetObserveComposer`** — joins LaunchEntity ↔ `health.json` checks:
   - `job.nightly` ↔ `dead_man`
   - `svc.ladybug.serve` ↔ `ladybug_query` (+ live probe override)
   - `svc.letta*` ↔ `letta_api`
5. **Roster UI** — row why + headline why; compact mode for the bar
6. **MultibrainBar** — `MemoryBridge.refreshHiveStatus()` calls `FleetObserveComposer.observeLive()`; menu embeds `LaunchEntityRosterView(compact: true)`

## Tests

```bash
cd Packages/MemoryKit && swift test --filter 'FleetObserve|LaunchEntity|HealthSnapshot'
# → 40 tests, 5 suites, passed
```

Key cases:
- Cron idle + exit 0 + green health → `IDLE` (not critical)
- `dead_man` fail → `job.nightly` CRITICAL with why
- Live `/health` fail overrides stale green `ladybug_query`
- Non-zero `lastExit` → DEGRADED
- Satellite index probe → skipped n/a

## Dual-home

Mirrored into `~/Developer/Andromeda/Packages/MemoryKit` (same files).  
Bar depends on `~/Developer/multibrain/Packages/MemoryKit`.

## Intentionally not done (still fleet SoT)

- Python `consolidate.py` / `run-nightly.sh` still *execute* the dream batch under launchd
- MemoryKit LaunchEntity remains **Observe-only** (kickstart stays in MultibrainBar)

## Operator verify

1. Rebuild / relaunch MultibrainBar
2. Open menu → Launch Entities roster shows live statuses + why on yellow/red
3. Hive chrome `failureSummary` prefers joined why (nightly / index-server)
