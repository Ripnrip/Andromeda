# BIN-26 Proof — LaunchEntity Registry

**Status:** PASS  
**Date:** 2026-07-15  
**Branch:** `anima-memory`  
**Package:** `Packages/MemoryKit`  
**Observe-first:** mock launchctl only — no kickstart / bootstrap / unload

## What was proven

1. **Catalog seeds** — nine `com.multibrain.*` entities (nightly, health, letta, letta-bridge, letta-shim, index-server, claude-mem-worker, dreamcatcher, retro) plus Mac Mini VNC tunnel as isolated / non-hive.
2. **Entity shape** — each row carries stable `slug` + `kind` + `plistPath` + `schedule` + `status` (`running` / `stopped` / `n/a`) + `hostRole` (`hub` | `satellite` | `isolated`).
3. **Visible watchdogs** — dreamcatcher (1800s) and claude-mem-worker (60s) are first-class roster entries, not silent daemons.
4. **Ops-only retro** — `job.weekly_retro` points at `ops/com.multibrain.retro.plist`, `schedule == .opsTemplateOnly`, never fakes running.
5. **Mac Mini isolation** — `tunnel.mac-mini-vnc` is `hostRole: .isolated` and excluded from `hiveEntities()`.
6. **Read-only observe** — `MockLaunchctlObserver` flips running/stopped; `NullLaunchctlObserver` never fabricates green; no mutation API in BIN-26.
7. **Satellite honesty** — hub KeepAlive services report `.notApplicable` when `observingHostRole == .satellite`.

## Commands run

Primary proof used a TCA-free scratch package (identical Registry sources) because parallel MemoryKit agents were saturating shared `.build` locks:

```bash
# Standalone mirror of Registry sources (same Swift as MemoryKit/Registry/)
cd /tmp/LaunchEntityProof && swift test
```

Equivalent in-package filter (when `.build` is free):

```bash
cd /Users/admin/Developer/multibrain/Packages/MemoryKit
swift test --filter LaunchEntityRegistryTests
```

Swift: Apple Swift 6.2 (`swiftlang-6.2.0.19.9`), target `arm64-apple-macosx14.0`.

## Test output summary

| Result | Count |
|--------|------:|
| PASS   | 11 |
| FAIL   | 0 |

Suite: `🚀 LaunchEntity Registry Suite` — **passed** (~0.064s runtime after build).

| Test | Proves |
|------|--------|
| `📜 Catalog seeds known com.multibrain.* entities` | 9 multibrain labels + Mini tunnel |
| `🌙 Nightly is cron @ 02:30 hub dream batch` | slug/kind/schedule/plist |
| `🛡️ Dreamcatcher + claude-mem-worker are visible watchdogs` | no silent watchdogs |
| `📜 Retro is ops-only template (not installed)` | ops path + opsTemplateOnly |
| `🧊 Mac Mini tunnel is isolated / non-hive` | isolated lane excluded from hive |
| `👁️ Mock launchctl maps running / stopped without kickstart` | observe-only |
| `🛰️ Satellite honesty — hub services report n/a` | Letta/Ladybug n/a off-hub |
| `🧊 Isolated observer does not invent hive membership` | Mini stays isolated |
| `🌙 Null observer leaves entities stopped (no fake green)` | fail-closed status |
| `🎭 Entity identity + Codable round-trip` | console/n8n serialization |
| `📜 Schedule display summaries` | human labels for roster |

## Evidence artifacts

- Log: `/tmp/memorykit-launch-entity-proof.log`
- Tests: `Tests/MemoryKitTests/LaunchEntityRegistryTests.swift`
- Sources:
  - `Sources/MemoryKit/Registry/LaunchEntity.swift`
  - `Sources/MemoryKit/Registry/LaunchEntityRegistry.swift`

## Remaining gaps / stubs

- Live `launchctl print` adapter not wired (Null/Mock only) — Andromeda console boundary next.
- Kickstart / bootstrap / unload intentionally absent (visibility before control).
- Adjacent agents (`com.qdrant.server`, Multica, Hermes tunnel) not in seed list yet — surface-area §G lists them; hive SoT seed is `com.multibrain.*` + Mini isolated lane.

## Fixes applied during this proof

None to Registry sources — suite passed on first green run after recreate (parallel agents briefly removed the Registry directory mid-session; sources restored and re-proven).
