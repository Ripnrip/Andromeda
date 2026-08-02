# PROOF 42 — Andromeda HUD / MemoryKit test + snapshot catalog

**Date:** 2026-07-18 (~13:35–13:40 EDT)  
**Lane:** HUD / Bars / Memory audit surface  
**SoT:** Andromeda `PROOFS/` (this file) · mirror `~/Developer/multibrain/PROOFS/42-test-and-snapshot-catalog-2026-07-18.md`  
**Related:** [PROOF 39](./39-andromeda-hud-dogfood-2026-07-18.md) · [PROOF 41 scorecard](./41-audit-scorecard-40-agent-2026-07-18.md) · [PROOF 41 hang](./41-hud-hang-timeout-dogfood-2026-07-18.md)  
**Honesty rule:** report live pass/fail; do not hide red.

---

## CORRECTION — 2026-07-18 ~14:05 EDT · HUD "15/15 green" was LOCAL-ONLY, not on PR #8

The HUD snapshot rows in this catalog (`HUDViewSnapshotTests` 10 + `HUDResultsViewSnapshotTests` 5 = 15 PNGs) reflect the **local `main` working tree's `AndromedaHUDCore` implementation** — genuinely green *there*, but that suite is **untracked and not on any PR**. A verifying audit on a clean checkout of PR #8 (`origin/cursor/andromeda-hud-modern-swiftui-67c4`) found:

- PR #8's HUD is a **different** implementation (`Sources/AndromedaHUD/AndromedaHUDView`) whose snapshot suite is `AndromedaHUDSnapshotTests` (6 tests), **not** `HUDViewSnapshotTests`/`HUDResultsViewSnapshotTests`.
- The 15 PNGs pushed to PR #8 @ `97de0a3` were **orphaned** (named for the local suite, which doesn't exist on the branch); `AndromedaHUDSnapshotTests` had no goldens → **6/6 FAIL** (`No reference was found on disk`) on clean checkout.
- **Fixed on PR #8 (`8c9c4a6`, no force):** recorded 6 real hermetic `AndromedaHUDSnapshotTests` goldens + removed the 15 orphans. Clean `/tmp` checkout: `swift build` OK · `AndromedaHUDSnapshotTests` **6/6** · full suite **6 XCTest + 47 swift-testing** green.

So the local `AndromedaHUDCore` 15-PNG catalog below is a truthful record of the **local** tree; it is **not** what ships on PR #8. See PROOF 41 CORRECTION + BIN-58 comment `d9c6cc98` / BIN-83 comment `f7a553a6`.

---

## Update — 2026-07-18 ~13:45 EDT · CommandCenter RED → GREEN

The one RED in this catalog (`CommandCenterSnapshots` 16/16) is **resolved**.

- **Root cause:** stale baselines after an *intended* header copy rebrand in `CommandCenterView.swift` (uncommitted in both trees): title `Anima · MemoryKit` → `Andromeda · Memory`, corner tag `stub` → `home` (static literal, **not** hostname), a11y label updated. All 16 diffs isolated to the header text region; body/badges/buttons pixel-identical. **Not nondeterminism.**
- **Hermeticity verified before re-record:** injected fixture models (no live health/sync), no `SyncStatus.success(date)` fixture (⇒ no timestamp ever rendered), `home` is a static string not the host. Deterministic ⇒ re-record was correct, not a paper-over.
- **Fix:** `SNAPSHOT_TESTING_RECORD=all swift test --filter CommandCenterSnapshots` in multibrain SoT, then mirrored 16 PNGs to Andromeda dual-home.
- **Green proof:** multibrain SoT `swift test --filter CommandCenter` → snapshot **1/1 pass, 0 failures** + `CommandCenterView` unit **10/10**; Andromeda dual-home snapshot **1/1 pass**; `diff -rq` on both `__Snapshots__/CommandCenterSnapshots` trees → **clean (identical)**.
- **Tracking:** logged root cause + green proof on **BIN-31** (MemoryKit UI snapshot catalog; stays Done). No dedicated CommandCenter re-record ticket existed (cf. HUD's BIN-83). Baselines left uncommitted for operator review; no commit/push.

**Net after update:** entire PROOF-42 pixel catalog is GREEN (0 outstanding RED).

---

## Executive verdict

| Area | Result | Notes |
|------|--------|-------|
| **AndromedaHUDTests** (Swift Testing + XCTest) | **PASS with 1 flake** | Full filter: 34/35 Swift Testing + **6/6** `HUDPerformanceTests`. Debounce flake failed under parallel load; **8/8** green on solo re-run. |
| **HUD snapshots** (`HUDView` + `HUDResultsView`) | **PASS** | **15/15** PNG baselines asserted green |
| **AndromedaHomeTests** | **PASS** | **11/11** Swift Testing + **12/12** snapshot XCTest |
| **MemoryKit dual-home** (Capture / Retrieval / Health / LocalProcessRunner) | **PASS** | **32/32** Swift Testing |
| **MemoryKit UI snapshots** (Roster / MCP / ProjectState / FloatingPet) | **PASS** | 12+4+4 XCTest + FloatingPet matrix **PASS** |
| **MemoryKit CommandCenterSnapshots** | **PASS** (re-recorded) | Was **16/16** stale (header rebrand); re-recorded + green — see § Update |
| Full package / non-HUD Andromeda targets | **NOT RUN** | Isolated build paths used; see § Not run |

**Net:** HUD audit surface is green for unit + HUD/Home pixel catalogs. Dual-home Capture/Retrieval/Health/runner green. CommandCenter catalog baselines were **stale/red** at first run (honest gap vs PROOF 41 “snap catalog present”) and are now **re-recorded + green** (see § Update at top).

---

## How this was run

Isolated build paths (avoid Andromeda `.build` lock contention noted in PROOF 41):

```bash
# Andromeda — HUD
cd ~/Developer/Andromeda
swift test --build-path /tmp/andromeda-proof42-build --filter AndromedaHUDTests
swift test --build-path /tmp/andromeda-proof42-build --filter MemorySearchViewModelTests   # debounce retry
swift test --build-path /tmp/andromeda-proof42-build --filter AndromedaHomeTests

# MemoryKit SoT (multibrain)
cd ~/Developer/multibrain/Packages/MemoryKit
swift test --build-path /tmp/memorykit-proof42-build \
  --filter 'HealthSnapshotTests|RetrievalService|LocalProcessRunner|ProjectStatePanelSnapshot|LaunchEntityRosterSnapshot|CommandCenterSnapshots|FloatingPetSnapshots|MCPRegistrySnapshot|CaptureService'
```

Raw logs: `/tmp/andromeda-proof42-hud.txt`, `…-home.txt`, `…-vm.txt`, `/tmp/memorykit-proof42.txt`, `…-cc-pet.txt`.

---

## 1. AndromedaHUDTests — suite results

### Swift Testing (full `--filter AndromedaHUDTests`)

| Suite | Tests | Result |
|-------|------:|--------|
| `HUDCommand` | 3 | **PASS** |
| `Andromeda HUD project.state` (`HUDProjectStateTests`) | 9 | **PASS** |
| `HUDSelectionNavigation` | 4 | **PASS** |
| `MemorySearchViewModel` | 3 | **FAIL** (1) → **PASS** on retry |
| `HUDModel recent + fleet` | 5 | **PASS** |
| `Andromeda HUD Snapshots` (`HUDViewSnapshotTests`) | 7 (+ arg cases → 10 PNGs) | **PASS** |
| `HUDResultsView Snapshots` | 4 (+ arg cases → 5 PNGs) | **PASS** |
| **Subtotal (first run)** | **35** | **34 PASS · 1 FAIL** |

**Failure (first run only):**

| Test | File | Issue |
|------|------|-------|
| `Debounce cancels superseded keystrokes` | `MemorySearchViewModelTests.swift:56` | `Expectation failed: (vm.isSearching → true) == false` under parallel suite load |

**Retry:** `swift test --filter MemorySearchViewModelTests` → **8/8 PASS** (both `MemorySearchViewModel` + `HUDModel recent + fleet`). Treat as timing flake, not product regression.

### XCTest

| Suite | Tests | Result |
|-------|------:|--------|
| `HUDPerformanceTests` | 6 | **PASS** |

| Case |
|------|
| `testHUDViewRenderPerformance` |
| `testHUDViewExpandCollapseMemoryAllocation` |
| `testHUDMemoryLeaks` |
| `testSubmitQueryParsePathPerformance` |
| `testSubmitEmptyCreateTitleCompletesQuickly` |
| `testResultsPanelEmptyErrorRenderPerformance` |

### HUD unit inventory (source counts)

| File | Style | Cases |
|------|-------|------:|
| `HUDCommandTests.swift` | `@Test` | 3 |
| `HUDProjectStateTests.swift` | `@Test` | 9 |
| `HUDSelectionNavigationTests.swift` | `@Test` | 4 |
| `MemorySearchViewModelTests.swift` | `@Test` | 8 (3 VM + 5 model) |
| `HUDPerformanceTests.swift` | XCTest | 6 |
| `HUDViewSnapshotTests.swift` | `@Test` | 7 |
| `HUDResultsViewSnapshotTests.swift` | `@Test` | 4 |
| **Total methods** | | **41** |

Aligned with PROOF 39 unit inventory (30 non-snapshot + 11 snapshot methods); performance + snapshots included here.

---

## 2. AndromedaHomeTests — suite results

| Suite | Style | Tests | Result |
|-------|-------|------:|--------|
| `AndromedaMemoryCommand` | Swift Testing | 4 | **PASS** |
| `AndromedaHome fleet pulse` | Swift Testing | 4 | **PASS** |
| `AndromedaHome project.state` | Swift Testing | 3 | **PASS** |
| `AndromedaHomeSnapshotTests` | XCTest | 12 | **PASS** |
| **Total** | | **23** | **PASS** |

---

## 3. MemoryKit dual-home (multibrain SoT)

### Unit / service (Swift Testing) — **32/32 PASS**

| Suite | Tests | Result |
|-------|------:|--------|
| `🩺 Health Snapshot / Agent Telemetry (BIN-27)` | 11 | **PASS** |
| `🔍 The Recall Memory Retrieval Rituals` | 10 | **PASS** |
| `📥 The Store Memory Capture Rituals` | 9 | **PASS** |
| `LocalProcessRunner` | 2 | **PASS** (timeout + large-stdout drain — hang fix proof) |

### UI snapshot XCTest

| Suite | Tests | PNG baselines | Result |
|-------|------:|--------------:|--------|
| `LaunchEntityRosterSnapshotTests` | 12 | 12 | **PASS** |
| `MCPRegistrySnapshotTests` | 4 | 4 | **PASS** |
| `ProjectStatePanelSnapshotTests` | 4 | 4 | **PASS** |
| `FloatingPetSnapshots` (`testFloatingPetCatalogMatrix`) | 1 | 32 | **PASS** |
| `CommandCenterSnapshots` (`testCommandCenterCatalogMatrix`) | 1 | 16 | **PASS** (re-recorded 07-18) |

**CommandCenter detail (resolved):** all 16 named baselines (`cc-healthy-*`, `cc-degraded-*`, `cc-syncing-*`, `cc-emptyIntents-*` × light/dark × medium/a11y2) mismatched at first run due to an intended header copy rebrand (`Anima · MemoryKit`/`stub` → `Andromeda · Memory`/`home`), not nondeterminism. Re-recorded via `SNAPSHOT_TESTING_RECORD=all` after verifying hermeticity; now green. See § Update at top.

**Dual-home PNG trees:** Andromeda `Packages/MemoryKit/.../__Snapshots__` vs multibrain SoT — **identical** (only `.DS_Store` differs under Snapshots/).

---

## 4. Snapshot catalog (every PNG)

### A. HUD — `Tests/AndromedaHUDTests/__Snapshots__/` · **15 PNGs**

#### `HUDViewSnapshotTests` · 10

| Case / method | Named PNG |
|---------------|-----------|
| `idleSnapshots` | `Dark.png`, `Light.png` |
| `extraLargeDynamicTypeSnapshot` | `Dark_ExtraLargeDynamicType.png` |
| `collapsedWithQuerySnapshots` | `Dark_Collapsed_Query.png`, `Light_Collapsed_Query.png` |
| `expandedSnapshots` | `Dark_Expanded_Results.png`, `Light_Expanded_Results.png` |
| `emptyOutcomeA11ySnapshot` | `Dark_Empty_A11y3.png` |
| `failedOutcomeSnapshot` | `Light_Failed.png` |
| `recentQueriesSnapshot` | `Dark_RecentQueries.png` |

Paths: `…/HUDViewSnapshotTests/<method>.<name>.png`

#### `HUDResultsViewSnapshotTests` · 5

| Case / method | Named PNG |
|---------------|-----------|
| `visibleSnapshots` | `HUDResultsView-visible-dark.png`, `…-visible-light.png` |
| `hiddenSnapshot` | `HUDResultsView-hidden.png` |
| `visibleReduceMotionSnapshot` | `HUDResultsView-visible-dark-reduceMotion.png` |
| `visibleDynamicTypeSnapshot` | `HUDResultsView-visible-dark-a11y3.png` |

**Honesty (PROOF 39):** `*reduceMotion*` PNG is dark visible layout; macOS cannot inject `.accessibilityReduceMotion` into snapshot host — runtime still honors Environment.

### B. Home — `Tests/AndromedaHomeTests/__Snapshots__/AndromedaHomeSnapshotTests/` · **12 PNGs**

| Case | PNG |
|------|-----|
| healthy | `AndromedaHome_healthy_light/dark.png`, `…_healthy_a2_light.png` |
| syncing | `…_syncing_light/dark.png`, `…_syncing_reduceMotion_light.png` |
| degraded | `…_degraded_light/dark.png`, `…_degraded_reduceMotion_dark.png` |
| recalled | `…_recalled_light/dark.png`, `…_recalled_a2_dark.png` |

### C. MemoryKit SoT — **68 PNGs**

| Suite dir | Count | Status when asserted |
|-----------|------:|----------------------|
| `Snapshots/__Snapshots__/CommandCenterSnapshots` | 16 | **GREEN** (re-recorded 07-18) |
| `Snapshots/__Snapshots__/FloatingPetSnapshots` | 32 | **GREEN** |
| `__Snapshots__/LaunchEntityRosterSnapshotTests` | 12 | **GREEN** |
| `__Snapshots__/MCPRegistrySnapshotTests` | 4 | **GREEN** |
| `__Snapshots__/ProjectStatePanelSnapshotTests` | 4 | **GREEN** |
| **Total** | **68** | 68 green (16 CommandCenter re-recorded 07-18) |

#### CommandCenter (16) — green after re-record

`cc-{healthy,degraded,syncing,emptyIntents}-{light,dark}-{medium,a11y2}.png`

#### FloatingPet (32) — green

`pet-{idle,syncing,dreaming,degraded}-{motion,reduceMotion}-{light,dark}-{medium,a11y2}.png`

#### LaunchEntityRoster (12) — green

`loading` / `empty` / `hubFull` / `satelliteNA` × light/dark + Dynamic Type XXXL + reduceMotion variants

#### MCPRegistry (4) — green

`empty-dark/light`, `sprawl-dark/light`

#### ProjectStatePanel (4) — green

`light`, `dark`, `empty`, `loading`

---

## 5. Cross-links to prior proofs

| Proof | Claim still true? |
|-------|-------------------|
| **41 hang** — Working `"test"` cleared; LocalProcessRunner drain | **Yes** — `LocalProcessRunner` 2/2 PASS this run |
| **41 scorecard** — HUDPerformance 6/6 | **Yes** |
| **41** — BIN-83 snapshots / HUD 15 PNGs | **Yes** — HUD 15/15 asserted green |
| **41** — HUDProjectState 9/9 | **Yes** |
| **41** — debounce 8/8 | **Yes after retry**; first parallel run flaked 1 debounce case |
| **39** — unit inventory 30 + 15 PNGs | **Yes** (inventory); green run claimed here |
| **41** — CommandCenter/MemoryKit UI “catalog present” | Catalog **on disk**; CommandCenter re-recorded + **assert GREEN** (07-18 update) |

---

## 6. Not run (explicit)

- Full `swift test` for Andromeda package (all targets)
- AndromedaCore / Gateway / AutoCache / CLI tests
- Full MemoryKit package (CloudKit, Merkle, Qdrant, Ladybug, Obsidian, LaunchEntity non-snapshot unit sprawl, etc.)
- Live HUD AX dogfood / `open -a` (forbidden this task)
- ~~Snapshot **re-record** for CommandCenter~~ — **DONE 07-18** (16 baselines re-recorded, dual-home mirrored, green; see § Update)

---

## 7. Totals rollup

| Bucket | Pass | Fail | Flake→pass | Not run |
|--------|-----:|-----:|-----------:|---------|
| AndromedaHUD Swift Testing | 34 | 0* | 1 debounce | — |
| AndromedaHUD XCTest perf | 6 | 0 | — | — |
| AndromedaHome | 23 | 0 | — | — |
| MemoryKit unit (filtered) | 32 | 0 | — | rest of package |
| MemoryKit UI snapshot XCTest | 22 methods green† | 0 (CommandCenter re-recorded 07-18) | — | — |
| **PNG baselines on disk** | **95** (15+12+68) | 0 (16 CommandCenter re-recorded 07-18) | — | — |

\*First HUD filter reported 1 fail; retry cleared.  
†LaunchEntity 12 + MCP 4 + ProjectState 4 + FloatingPet 1 + CommandCenter 1 = 22 XCTest methods green (CommandCenter re-recorded 07-18, 16 assertions now green).

---

## 8. Operator next actions (optional)

1. ~~Re-record CommandCenter~~ — **DONE 07-18** (`SNAPSHOT_TESTING_RECORD=all swift test --filter CommandCenterSnapshots` in MemoryKit SoT, mirrored dual-home, green). Operator: review/commit the uncommitted baselines if desired.
2. Optionally harden debounce test timing / isolate from parallel load.
3. Keep HUD/Home snapshot filters in CI smoke:  
   `AndromedaHUDTests` + `AndromedaHomeTests`.

---

*Generated 2026-07-18 for 40-agent audit closeout. No Changelog/TODO edits. No commit.*
