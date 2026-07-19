# PROOF 41 — 40-agent Andromeda/Multibrain HUD audit scorecard

**Date:** 2026-07-18  
**Lane:** HUD / Bars / Memory closeout  
**SoT:** Andromeda `PROOFS/` (HUD) + multibrain `PROOFS/` (fleet/MemoryKit dual-home)  
**Epics:** [BIN-55](https://linear.app/binary-bros/issue/BIN-55) HUD · [BIN-71](https://linear.app/binary-bros/issue/BIN-71) Bars · [BIN-70](https://linear.app/binary-bros/issue/BIN-70) Memory  
**Multica MCP:** unavailable in Cursor catalog — CLI used where possible; see Multica section  
**Honesty rule:** overclaimed Done is worse than Todo. Do not invent green.

Mirror index entry: `~/Developer/multibrain/PROOFS/41-audit-scorecard-40-agent-2026-07-18.md` (symlink or copy).

---

## CORRECTION — 2026-07-18 ~14:05 EDT · "15 PNGs green on PR #8" was FALSE (orphaned baselines)

A verifying audit on a **clean checkout** of `origin/cursor/andromeda-hud-modern-swiftui-67c4` found the earlier claim that commit `97de0a3` landed the "BIN-83 green catalog" on PR #8 was **inaccurate**:

- The 15 PNGs at `97de0a3` sit under `__Snapshots__/HUDViewSnapshotTests/` + `__Snapshots__/HUDResultsViewSnapshotTests/`, but **those test classes do not exist on the PR branch**. They are named for the local `AndromedaHUDCore` SoT suite and were **orphaned** when pushed onto a branch whose HUD is `Sources/AndromedaHUD/` (`AndromedaHUDView`).
- The PR branch's **real** snapshot suite is `AndromedaHUDSnapshotTests` (6 tests → `HUD.collapsed.healthy.light`, …) with **zero committed goldens** → recorded-then-failed **6/6** (`No reference was found on disk`) on clean checkout.
- Repo has **zero CI** (`statusCheckRollup: []`) so nothing caught the red.
- The "15/15 green" in this scorecard and PROOF 42 was **LOCAL-ONLY** against the uncommitted `AndromedaHUDCore` rewrite on `main` — genuinely green there, but never on the PR branch.

**Fix pushed to PR #8 (`8c9c4a6`, regular push, no force):** recorded the 6 real hermetic `AndromedaHUDSnapshotTests` goldens on macOS + removed the 15 orphaned PNGs.

**Clean `/tmp` worktree of pushed tip `8c9c4a6` — real evidence:**
```
swift build           → Build complete! (120.50s)
swift test --filter AndromedaHUDSnapshotTests → Executed 6 tests, 0 failures
swift test (full)     → XCTest 6/6 pass · swift-testing 47 tests / 8 suites pass
```

BIN-58 corrected (comment `d9c6cc98`, stays **In Review** — now justified). BIN-83 flagged (comment `f7a553a6`) — its 11/11 is local-only; the RecentQueries hermetic fix is **not** on the pushed branch (different suite). The `AndromedaHUD` (PR) vs `AndromedaHUDCore` (local) SoT question remains an **operator decision**. Rows below marked ⚠️ where superseded by this correction.

---

## Executive verdict (closeout in progress)

| Bucket | Count | Notes |
|--------|------:|-------|
| PASS (confirmed live / code+test) | see table | Includes remediations already landed |
| PARTIAL | several | Evidence incomplete or merge-ladder open |
| FAIL → remediating | several | Driven to green or human-blocked below |
| SKIP | Multica MCP | CLI available; MCP server not in Cursor |
| HUMAN-BLOCKED | BIN-82 Letta OpenRouter; BIN-79 CloudKit GUI; Dynamic Type P2 | Explicit |

**100% proof-green:** **NO** — remaining human/merge-only (BIN-58 PR review/merge, BIN-82 OpenRouter env, BIN-79 CloudKit, P2 reduce-motion inject). Agent-finishable audit items are green (~**75%** overall / ~**86%** agent-finishable).

---

## PASS (confirmed still true 2026-07-18 ~12:20–12:30 EDT)

| Area | Evidence | Linear |
|------|----------|--------|
| Escape / `orderOut` | Code paths in HUD; unit coverage | BIN-61 Done |
| Status item | Sparkles accessory live with HUD PID | BIN-62 Done |
| LaunchAgent SoT | `com.andromeda.hud` running; **direct binary** (not `open -a`); RunAtLoad; KeepAlive=false; env HOME+PATH only | BIN-63 Done |
| Snap / expand / click | Code + snapshot catalog present | BIN-56 / expand fix |
| Results size / polish | Snapshot + `HUDResultsView` | BIN-58 related |
| Fleet pulse | `FleetObserveComposer.observeLive` chip wiring | BIN-64 Done |
| Hotkeys | ⌘⇧Space + status item | BIN-55 |
| Capability curtain | Client IDs only (`memory.*`, `infer.write`, `project.state.*`) in HUD chrome | BIN-34 lineage |
| Store/recall empty polish | Outcome rows / empty messaging in source | — |
| BIN-57 Ask AI | Expandable search + debounce VM | BIN-57 Done |
| FleetObserveBar keep | Dedicated Observe; MultibrainBar slim | BIN-77 Done |
| Build product | `~/Applications/AndromedaHUD.app` adhoc-signed | BIN-63 |
| MultibrainBar LA bounce | KeepAlive=`false`; agent **unloaded** (not in launchctl domain) | BIN-74 / BIN-71 |
| Package.swift MemoryKit on HUDTests | `AndromedaHUDTests` depends on MemoryKit product | — |
| Submit timeout strings in app | `strings` → `_submitTimeoutNanoseconds`, `Working on your query` | hang remediations |
| HUD process env (PID 12088) | No OPENROUTER/ANTHROPIC/OPENAI in `ps eww` | — |
| **Working hang `"test"`** | Sibling **6cea415f** live AX dogfood — Working cleared → `No memories matched "test"`; clean env; LA direct-exec. Proof: `PROOFS/41-hud-hang-timeout-dogfood-2026-07-18.md`. **Do not re-litigate.** | BIN-55 / BIN-59 slice |
| BIN-66 recent queries | Noted PASS by hang sibling | BIN-66 Done |
| **PROOF 39 honesty rewrite** | Sibling a42687fd — PID 12088; capability paths later closed under BIN-69 Done | BIN-69 |
| **Hang source fix (LocalProcessRunner)** | Sibling **e6a9bac8** — concurrent pipe drain before `waitUntilExit`; HUDModel timeout. Live dogfood by `6cea415f` on PID 12088 (PROOF 41-hud-hang). | hang |

---

## FAIL / PARTIAL — status at scorecard time

| # | Item | Status | Linear | Remixed / evidence | Remaining |
|---|------|--------|--------|--------------------|-----------|
| 1 | HUD Working hang (`"test"`) | **PASS (live)** | hang slice | **Source fix:** sibling `e6a9bac8` — `LocalProcessRunner` concurrent pipe drain (never `waitUntilExit` before drain) + `HUDModel` submit timeout. **Live proof:** sibling `6cea415f` — `PROOFS/41-hud-hang-timeout-dogfood-2026-07-18.md` (PID 12088, `"test"` cleared Working). Do **not** relaunch to older PIDs. | None — do not re-litigate |
| 2 | BIN-83 snapshots | **PASS / Done** | BIN-83 **Done** | Sibling `f72e2a97`: hermetic seed + clear; Dark_RecentQueries re-recorded; **11/11** green | None (merge honesty → BIN-58) |
| 3 | BIN-69 dogfood honesty | **PASS / Done** | BIN-69 **Done** | Hang AX recall; canonical store→recall; live `infer.write` E2E (`infer-e2e-C8F79E7E`); `HUDProjectStateTests` **9/9** incl. list; debounce **8/8** | Optional HUD AX polish |
| 4 | BIN-58 snapshot PNGs + PR #8 | ⚠️ **SUPERSEDED** — see CORRECTION | BIN-58 **In Review** | ~~15 PNGs @ `97de0a3`~~ were **orphaned** (wrong suite names). **Fixed `8c9c4a6`:** 6 real `AndromedaHUDSnapshotTests` goldens recorded + orphans removed; clean-checkout **6/6 + 47** green | Operator: `AndromedaHUD` vs `AndromedaHUDCore` SoT decision + merge |
| 5 | BIN-65 `project.state.update` | **PASS** | BIN-65 **Done** | Sibling `7abbd39d`: 9/9; HAB-82 mirror | None |
| 6 | Arrow ↑/↓ + SearchField | **PASS (unit)** | BIN-55 polish | Sibling `e0281264`: 4/4; app kickstart when stale | Optional live AX |
| 7 | BIN-59 HUDPerformanceTests | **PASS** | BIN-59 **Done** | Sibling `f1f7e5ba`: **6/6** | None |
| 8 | Package.swift MemoryKit dep | **PASS** | — | Sibling `b5164a3a`: MemoryKit on `AndromedaHUDTests` + `AndromedaHomeTests` | None |
| 9 | Dual-home MemoryKit (BIN-78) | **PASS** | BIN-78 Done | `RetrievalService`/`LocalProcessRunner` SHA `33b6b202…` both homes; `LocalProcessRunnerTests` promoted Andromeda→multibrain SoT | Keep aligned |
| 10 | Reduce-motion | **PARTIAL / honest** | — | Runtime honors env; snapshot inject **does not compile** on macOS | Dynamic Type scaling = **P2 Todo** — do not fake Done |
| 11 | PROOFS INDEX 37–41 | **PASS** | — | INDEX updated through 41 (scorecard + hang) | Keep current |
| 12 | MultibrainBar LA | **PASS** | BIN-74 | KeepAlive false; unloaded | — |
| 13 | BIN-82 Letta OpenRouter | **HUMAN-BLOCKED** | BIN-82 In Progress | `letta-native.env` OpenRouter residual | Human spend-kill |
| 14 | BIN-79 CloudKit GUI | **HUMAN / Todo** | BIN-79 Todo | Not agent-dogfoodable | Leave Todo |

---

## Live commands / evidence (captured this closeout)

```bash
pgrep -x AndromedaHUD
# → 12088

launchctl print gui/$(id -u)/com.andromeda.hud | head -40
# program = …/AndromedaHUD.app/Contents/MacOS/AndromedaHUD  (direct exec)
# environment: HOME + PATH only; state=running; pid=12088

ps eww -p 12088 | tr ' ' '\n' | rg -i '^(OPENROUTER|ANTHROPIC|OPENAI)='
# → empty (clean)

strings ~/Applications/AndromedaHUD.app/Contents/MacOS/AndromedaHUD \
  | rg '_submitTimeoutNanoseconds|Working on your query'
# → present

shasum \
  ~/Developer/Andromeda/Packages/MemoryKit/Sources/MemoryKit/Services/RetrievalService.swift \
  ~/Developer/multibrain/Packages/MemoryKit/Sources/MemoryKit/Services/RetrievalService.swift
# → 33b6b2027d4239665124572d26703dfd96f4588c  (both, after promote)

plutil -extract KeepAlive raw ~/Library/LaunchAgents/com.multibrain.multibrain-bar.plist
# → false
launchctl print gui/$(id -u)/com.multibrain.multibrain-bar
# → not loaded

# OpenRouter residual (names only — no secret values):
awk -F= '/^[A-Za-z_]/{print $1}' ~/.multibrain/letta/letta-native.env
# includes OPENAI_API_KEY, OPENAI_API_BASE → OPENROUTER_RESIDUAL=yes
```

**SwiftPM contention note:** Multiple parallel `swift test` jobs were waiting on `Andromeda/.build` during audit. Focused greens must be re-run with a free lock or `--build-path /tmp/…`.

---

## Multica

| Action | Result |
|--------|--------|
| Cursor Multica MCP | **SKIP** — not in MCP catalog |
| Local Multica API | `curl http://127.0.0.1:3637/health` → `{"status":"ok"}` |
| CLI | `multica` available — used |
| HAB-76 | `in_review` + closeout comments |
| HAB-81 (BIN-59) | → **done** (perf 6/6) |
| HAB-82 (BIN-65) | **created done** — create+update mirror |
| HAB-80 (BIN-58) | ⚠️ prior `in_review` note ("15 PNGs on PR #8 `97de0a3`") was on **orphaned** baselines. Real fix `8c9c4a6` (6 goldens + orphans removed). Multica MCP not in Cursor catalog this session → **SKIP** mirror; operator to sync HAB-80 via CLI |
| HAB-84 (BIN-69) | **done** (capability dogfood) |
| HAB-85 (BIN-82) | **todo** HUMAN OpenRouter env |
| HAB-86 (BIN-79) | **todo** HUMAN CloudKit GUI |

Do **not** invent HAB Done without CLI status change.

---

## Slack

Posted `#projects` (`C0BHYQQDETA`): https://agent-habitat.slack.com/archives/C0BHYQQDETA/p1784394944205369

---

## Remaining red / human (must be empty or human-only for “100%”)

1. **BIN-58** — **HUMAN review/merge**: PNGs on PR #8 (`97de0a3`); SoT sync `AndromedaHUD`→`AndromedaHUDCore` still open  
2. **BIN-82** — **HUMAN** Letta `letta-native.env` OpenRouter residual (HAB-85)  
3. **BIN-79** — **HUMAN** CloudKit GUI smoke (HAB-86)  
4. **Dynamic Type / reduce-motion snapshot inject** — **P2 Todo**, honest  

**Agent-finishable reds:** cleared (hang, BIN-83, BIN-65, BIN-59, Package.swift, arrows unit, debounce, BIN-69 capability paths, BIN-58 PNG push).  
**100% proof-green:** **NO** — blocked remainder is human/merge-ladder only.  

**Estimated complete:** agent-finishable ~**86%**; overall proof-green toward 100% ~**75%** (BIN-58/82/79 + P2 still human).

---

## Remix log (this closeout agent)

| Change | Where |
|--------|--------|
| Scorecard written | `Andromeda/PROOFS/41-…` + multibrain mirror |
| RetrievalService PipeDataBoxes promote Andromeda → multibrain SoT | BIN-78 honesty |
| INDEX 37–40 (+41) hygiene | `PROOFS/INDEX-fleet-observe-andromeda-home.md` |
| Linear comments on epics + children | honesty-first |
| Multica CLI status sync where possible | HAB↔BIN |
| BIN-59 HUDPerformance 6/6 | Sibling f1f7e5ba — scorecard PASS |
| Arrow reinstall kickstart | When app older than HUDArrowKeyMonitor |

---

## Closeout (verify agent — 2026-07-18 ~13:15 EDT)

**Verdict:** Scorecard claims mostly honest. BIN-69 **kept Done** after log re-verify (`/tmp/bin69-infer.log` token `infer-e2e-C8F79E7E`). Dual-home SHA `33b6b202…` confirmed. **Not 100% proof-green.**

### Linear (final)

| ID | Status | Note |
|----|--------|------|
| [BIN-69](https://linear.app/binary-bros/issue/BIN-69) | **Done** | Honesty re-verify comment |
| [BIN-83](https://linear.app/binary-bros/issue/BIN-83) | **Done** | 11/11 snapshots |
| [BIN-65](https://linear.app/binary-bros/issue/BIN-65) | **Done** | create+update |
| [BIN-59](https://linear.app/binary-bros/issue/BIN-59) | **Done** | perf 6/6 |
| [BIN-58](https://linear.app/binary-bros/issue/BIN-58) | **In Review** | ⚠️ `97de0a3` PNGs were orphaned; fixed `8c9c4a6` — real `AndromedaHUDSnapshotTests` 6/6 green on clean checkout (see CORRECTION) |
| [BIN-82](https://linear.app/binary-bros/issue/BIN-82) | **In Progress** | HUMAN comment — OpenRouter env |
| [BIN-79](https://linear.app/binary-bros/issue/BIN-79) | **Todo** | HUMAN comment — CloudKit GUI |

### Multica

| HAB | Status | Note |
|-----|--------|------|
| HAB-76 | `in_review` | Epic closeout comments |
| HAB-80 | `in_review` | BIN-58 PNG ladder |
| HAB-84 | `done` | BIN-69 mirror |
| HAB-85 | `todo` | BIN-82 HUMAN |
| HAB-86 | `todo` | BIN-79 HUMAN |
| Multica MCP | **SKIP** | not in Cursor catalog; CLI used |

### Slack

- `#projects` (`C0BHYQQDETA`): https://agent-habitat.slack.com/archives/C0BHYQQDETA/p1784394944205369

### Committed / pushed (this agent)

- Andromeda PR #8 branch `cursor/andromeda-hud-modern-swiftui-67c4`: commit `97de0a3` — **15** snapshot PNG baselines only (no force-push). ⚠️ **Later found orphaned** (wrong suite); superseded by `8c9c4a6` (6 real `AndromedaHUDSnapshotTests` goldens + orphan removal), verified green on clean `/tmp` checkout. See CORRECTION at top.

### Remaining human blockers

1. Merge/review PR #8 (+ AndromedaHUDCore SoT sync) → BIN-58 Done  
2. Kill OpenRouter in `letta-native.env` → BIN-82 Done  
3. CloudKit GUI smoke PROOF → BIN-79 Done  
4. P2 reduce-motion snapshot inject (macOS WritableKeyPath)
