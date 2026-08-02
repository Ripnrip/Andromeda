# Andromeda HUD dogfood — 2026-07-18

**Status:** **FAIL / incomplete** — honesty remediation 2026-07-18 ~12:20 EDT after audit.  
**Surface:** `AndromedaHUD` (Swift 6, accessory, ⌘⇧Space)  
**Capabilities (client IDs only):** `memory.recall` · `memory.store` · `infer.write` · `project.state.*`  
**Linear:** [BIN-69](https://linear.app/binary-bros/issue/BIN-69/andromeda-hud-dogfood-proof-dogfood-pass) — reopened; **not Done** until live capability evidence + honest numbers land.

## Audit corrections (this rewrite)

| Prior claim (rejected) | Corrected fact |
|------------------------|----------------|
| Contradictory PIDs `90223` vs `76744` in same proof | Single live PID verified below (or “not running”) |
| “15/15 unit suites passed” | **15** = snapshot **PNG** baselines on disk; **not** unit suites |
| Reduce-motion snapshots proved | Dark-layout PNG only; `.environment(\.accessibilityReduceMotion, …)` does **not** compile on macOS |
| Implied live recall/store/infer/`project.state` dogfood | **NOT YET PROVEN** — no command/output evidence in this proof |
| Gaps → BIN-61.. omitted | Gaps section restored (esp. BIN-83 snapshots; BIN-65 mutate **closed**) |

## Live process (verified 2026-07-18 ~12:18–12:19 EDT)

```text
pgrep -x AndromedaHUD
# → 12088

ps -p 12088 -o pid,etime,command
# → 12088  …  /Users/admin/Applications/AndromedaHUD.app/Contents/MacOS/AndromedaHUD
```

| Fact | Value |
|------|--------|
| Install path | `/Users/admin/Applications/AndromedaHUD.app` (adhoc-signed, `com.andromeda.hud`) |
| Binary | `…/Contents/MacOS/AndromedaHUD` |
| **PID** | **`12088`** (single `pgrep -x AndromedaHUD` at remediation time; earlier session PIDs in prior drafts are obsolete — do not mix) |
| LaunchAgent | `gui/501/com.andromeda.hud` — registered, `RunAtLoad`, **no KeepAlive** |
| ProgramArguments | `/usr/bin/open -a /Users/admin/Applications/AndromedaHUD.app` |
| Plist `EnvironmentVariables` | `HOME` + `PATH` only (no paid vendor keys in plist) |
| codesign | adhoc (`Signature=adhoc`, `Identifier=com.andromeda.hud`) |

**Env honesty note:** plist declares `HOME`+`PATH` only. Because the agent uses `open -a`, inheritance from the login session is a known risk. At remediation:

- PID `12088` (current): paid-vendor stems **ABSENT** (`ps eww` check).
- An earlier same-session PID had inherited `OPENROUTER_API_KEY` / `CEREBRAS_API_KEY` / `GROQ_API_KEY` / `FIRECRAWL_API_KEY` — so “no OpenRouter on HUD path” is **not automatic**; re-verify after every relaunch.

## Dogfood checklist

| # | Item | Proof status |
|---|------|----------------|
| 1 | Escape dismisses results / collapses pill | Code/unit coverage only — **live UI not logged here** |
| 2 | Click-outside / resign-key | Code path claimed — **live UI not logged here** |
| 3 | Debounced live `memory.recall` | Unit tests for ViewModel — **live recall NOT YET PROVEN** |
| 4 | Menu bar status item | Install/surface present — **live click not logged** |
| 5 | Snap to menu bar | Code path — **live not logged** |
| 6 | `project.state create <title>` + `update` | **BIN-65 Done** — create+update wired; unit 9/9 (sibling 7abbd39d) |
| 7 | LaunchAgent | Plist + bootstrap present; RunAtLoad, no KeepAlive, plist env HOME+PATH |
| 8 | Install + adhoc sign | App present at `~/Applications/AndromedaHUD.app` |
| 9 | Empty / error / loading polish | Snapshot/source coverage — **not a live dogfood log** |
| 10 | Enter on recall hit | **NOT YET PROVEN** live |
| 11 | Recent queries | Unit coverage — **live not logged** |
| 12 | Window level toggle | Code path — **live not logged** |
| 13 | Screen + origin restore | Code path — **live not logged** |
| 14 | Fleet pulse chip | Composer wiring — **live pulse not logged** |
| 15 | Perf asserts | `HUDPerformanceTests` exists (6 XCTest methods) — **green run not claimed in this rewrite** |
| 16 | Reduce-motion / Dynamic Type snapshots | **Downgraded** — see below |
| 17 | VoiceOver labels/hints | Source claims — **live VO pass not logged** |
| 18 | No OpenRouter on HUD path | **Plist only**; live PID env was contaminated via `open -a` inheritance |
| 19 | This proof | Honesty rewrite after audit FAIL |
| 20 | Single instance | Verified single PID `12088` at remediation time |

## Capability dogfood — NOT YET PROVEN

BIN-69 bar requires live evidence for:

- `memory.recall`
- `memory.store`
- `infer.write`
- `project.state` list (create+update closed under **BIN-65 Done**; list still needs live dogfood log)

**This proof does not include** typed HUD commands, result panels, or store/hot-store diffs for those verbs. Do **not** treat unit tests or checklist rows as live dogfood.

Remaining bar before Done:

1. Clean-env HUD relaunch (paid keys absent from process env) **or** explicit waiver with operator sign-off
2. Live `memory.recall` with observable hits (local hot store / vault — no paid path required)
3. Live `memory.store` round-trip (local only)
4. Live `infer.write` (local/offline path only; skip if it would hit paid providers)
5. Live `project.state` **list** (client-safe chrome; no tracker brands)
6. Honest unit/snapshot numbers from a real `swift test` invocation (do not invent green)

## Tests & snapshots (source inventory — no invented green run)

Verify filter historically cited:

```bash
cd ~/Developer/Andromeda
swift test --filter 'HUDCommandTests|HUDProjectStateTests|MemorySearchViewModelTests|HUDModelExtrasTests'
```

| Suite named in filter | File present? | `@Test` / `test*` count in source |
|-----------------------|---------------|-------------------------------------|
| `HUDCommandTests` | yes | 3 |
| `HUDProjectStateTests` | yes | 9 |
| `MemorySearchViewModelTests` | yes | 8 |
| `HUDModelExtrasTests` | **no** (missing) | — |

**Filter reality:** 3 present suites · **20** `@Test` cases (not “15/15 suites”).

**Full `Tests/AndromedaHUDTests/` unit (non-snapshot) inventory:**

| Suite file | Tests |
|------------|------:|
| `HUDCommandTests.swift` | 3 |
| `HUDProjectStateTests.swift` | 9 |
| `MemorySearchViewModelTests.swift` | 8 |
| `HUDSelectionNavigationTests.swift` | 4 |
| `HUDPerformanceTests.swift` | 6 |
| **Unit total** | **5 suites · 30 tests** |

**Snapshot PNG baselines on disk:** **15** under `Tests/AndromedaHUDTests/__Snapshots__/`  
(That “15” was previously mislabeled as unit suites.)

| Snapshot suite | `@Test` methods | Notes |
|----------------|----------------:|-------|
| `HUDViewSnapshotTests` | 7 | Includes Dynamic Type / empty / failed / recent |
| `HUDResultsViewSnapshotTests` | 4 | Includes named `*.reduceMotion` PNG |

**This rewrite does not claim** a green snapshot or unit run. Re-record / assert when GUI baselines are intentionally refreshed (see BIN-83):

```bash
SNAPSHOT_TESTING_RECORD=1 swift test --filter 'HUDViewSnapshotTests|HUDResultsViewSnapshotTests'
swift test --filter 'HUDViewSnapshotTests|HUDResultsViewSnapshotTests'
```

### Reduce-motion (downgraded claim)

- Product code may read `@Environment(\.accessibilityReduceMotion)` at **runtime**.
- Snapshot tests **cannot** inject `.environment(\.accessibilityReduceMotion, …)` — not a `WritableKeyPath` under AppKit `NSHostingView` on macOS (see suite docs).
- `visibleReduceMotionSnapshot` / `*.reduceMotion` PNG = **dark visible layout only**, not a forced reduce-motion pixel proof.
- Dynamic Type snapshots (e.g. `accessibility3`) are separate and real layout variants.

## Gaps → polish tickets (BIN-61..)

| Ticket | Status (at remediation) | Why it still matters for dogfood |
|--------|-------------------------|----------------------------------|
| [BIN-65](https://linear.app/binary-bros/issue/BIN-65/andromeda-hud-projectstate-create-update) | **Done** | create + `project.state.update` closed (9/9 tests) — remove from open gaps |
| [BIN-83](https://linear.app/binary-bros/issue/BIN-83/andromeda-hud-snapshot-baseline-re-record-after-expandclick) | **Done** | Hermetic RecentQueries + 11/11 green (sibling f72e2a97) |
| [BIN-58](https://linear.app/binary-bros/issue/BIN-58/andromeda-hud-modern-swiftui-polish-and-snapshottesting) | **In Progress** | Snapshot suite green; **PR #8 merge-ladder** still blocks Done (PNGs must be on branch) |
| [BIN-61](https://linear.app/binary-bros/issue/BIN-61/andromeda-hud-escape-dismiss-polish) | Done | Escape/dismiss — still needs live UI confirmation in a future dogfood log |
| BIN-62..64, BIN-66..68 | Done | Menu item / LaunchAgent / pulse / recent / debounce / window level — unit/code ≠ live dogfood |
| Arrow ↑/↓ (no dedicated BIN) | **Unit PASS** | `HUDArrowKeyMonitor` + `HUDSelectionNavigation` 4/4 (sibling e0281264); live AX optional |

## Bootstrap (operator)

```bash
cd ~/Developer/Andromeda
./scripts/install-and-sign.sh hud

# Or LaunchAgent only after install:
mkdir -p ~/.multibrain/logs ~/Library/LaunchAgents
cp ops/com.andromeda.hud.plist ~/Library/LaunchAgents/
launchctl bootout gui/$(id -u)/com.andromeda.hud 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.andromeda.hud.plist

pgrep -lf AndromedaHUD
launchctl print gui/$(id -u)/com.andromeda.hud | head -40
```

## Hotkeys

| Shortcut | Action |
|----------|--------|
| ⌘⇧Space | Toggle HUD visibility |
| ⌘⇧M | Snap to menu bar |
| Escape | Dismiss results → collapse → hide |
| ↑ / ↓ | Select recall / project.state rows |
| Enter | Activate selection or submit |

Local-only memory targets (when dogfood is eventually run clean): `~/.multibrain/anima-hot.store` + vault `~/Developer/SecondBrain`.
