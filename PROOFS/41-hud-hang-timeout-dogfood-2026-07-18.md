# PROOF 41 — AndromedaHUD Working-hang timeout dogfood

**Date:** 2026-07-18 ~12:18–12:40 EDT  
**Surface:** `AndromedaHUD` @ `~/Applications/AndromedaHUD.app`  
**Parent:** [BIN-55](https://linear.app/binary-bros/issue/BIN-55/epic-andromeda-hud-modern-macos-floating-control-surface)  
**Related:** [BIN-69](https://linear.app/binary-bros/issue/BIN-69/andromeda-hud-dogfood-proof-dogfood-pass) (full dogfood still open) · [BIN-59](https://linear.app/binary-bros/issue/BIN-59/andromeda-hud-aggressive-performance-latency-benchmarks) (latency)  
**Client capability IDs only:** `memory.recall` (bare `"test"` → recall)

**Verdict (hang path):** **PASS (live)** — `"test"` left Working and reached a terminal empty-recall outcome.  
**Env:** **PASS (clean)** — no paid vendor API keys in process env.  
**LaunchAgent direct-exec:** **PASS** — root cause of prior key inheritance fixed.

---

## Live process

| Fact | Value |
|------|--------|
| **PID** | **`12088`** (single `pgrep -x AndromedaHUD`) |
| Parent | `launchd` (PPID 1) — **not** a shell/`open -a` child |
| Binary | `/Users/admin/Applications/AndromedaHUD.app/Contents/MacOS/AndromedaHUD` |
| Binary mtime | **2026-07-18 12:17:19** (`size=10355584`) |
| LaunchAgent | `gui/501/com.andromeda.hud` — `RunAtLoad`, **no KeepAlive** |
| **ProgramArguments** | **direct exec** of binary (see below) |

```text
pgrep -x AndromedaHUD
# → 12088

ps -p 12088 -o pid,ppid,etime,command
# → 12088  1  …  /Users/admin/Applications/AndromedaHUD.app/Contents/MacOS/AndromedaHUD
```

### LaunchAgent direct-exec fix (key inheritance root cause)

**Prior (PROOF 39 remediation):** plist used `/usr/bin/open -a …/AndromedaHUD.app`, which can inherit Aqua/agent-shell env → paid keys (`OPENROUTER_*`, `CEREBRAS_*`, `GROQ_*`, `FIRECRAWL_*`) leaked into an earlier same-session PID.

**Now (live):**

```text
plutil -extract ProgramArguments json -o - ~/Library/LaunchAgents/com.andromeda.hud.plist
# → ["/Users/admin/Applications/AndromedaHUD.app/Contents/MacOS/AndromedaHUD"]
```

Repo SoT matches: `ops/com.andromeda.hud.plist` documents **do not use `open -a`**; `EnvironmentVariables` = `HOME` + `PATH` only. Install path kickstarts `com.andromeda.hud` (no shell `open`).

### Env check (clean = Y)

```text
ps eww -p 12088 | tr ' ' '\n' | rg -i '^(OPENROUTER|ANTHROPIC|OPENAI|CEREBRAS|GROQ|FIRECRAWL)_API_KEY='
# → (no matches)

launchctl print gui/$(id -u)/com.andromeda.hud   # environment block
# → HOME, PATH, XPC_SERVICE_NAME, OSLogRateLimit only
```

**Env clean: Y**

### Binary contains timeout strings

```text
strings …/AndromedaHUD | rg 'submitTimeout|Timed out|HUD submit timed out|Working on your query'
# includes: _submitTimeoutNanoseconds, "Timed out ", "HUD submit timed out after %lluns", "Working on your query"
```

Source: `HUDModel.submitTimeoutNanoseconds = 2_500_000_000` (2.5s); watchdog races `executeCommand` and clears `.syncing` → `.failed("Timed out — try a more specific query")`.

---

## Live dogfood — query `"test"`

**Method:** status-item click (cliclick @ menu-bar “Andromeda HUD”) + AX / keystroke submit. **Not** `open -a`.

**AX evidence (terminal outcome, Working cleared):**

```text
=== WINDOW 1 … size=392x197
4 AXTextField … val=test
6 AXStaticText … val=No memories matched “test”
```

| Check | Result |
|-------|--------|
| Query | `"test"` → bare text → `memory.recall` |
| Working stuck forever? | **No** |
| Terminal UI | `No memories matched “test”` (empty recall — OK) |
| Timeout message required? | **No** — recall finished before 2.5s wall |
| Stopwatch on later AX polls | Flaky (ProgressView / collapsed pill / About dialog); **first dump is SoT** |
| Outcome class | **PASS** — Working cleared; hang fixed for this path |

### Manual dogfood step (operator)

1. Confirm single HUD from LaunchAgent: `pgrep -lf AndromedaHUD` → `~/Applications/...` only.  
2. Show HUD via **status item** (left click) or ⌘⇧Space — never `open -a` from a keyed shell.  
3. Type `test` → Enter.  
4. Expect within **≲3s**: either hits, `No memories matched “test”`, or `Timed out — try a more specific query` — **never** indefinite Working.

### Unit / harness coverage (timeout path)

`Tests/AndromedaHUDTests/MemorySearchViewModelTests.swift` → `submitTimeoutClearsSyncing`:

- Slow `ProjectStateSurface` sleeps 5s  
- `submitTimeoutNanoseconds = 200_000_000`  
- Expects `.failed` message containing `Timed out`

**Green run (2026-07-18 ~13:01 EDT):**

```text
swift test --filter 'submitTimeoutClearsSyncing'
# Test "Submit timeout leaves failed not syncing" passed after 0.224 seconds
# Test run with 1 test in 1 suite passed after 0.226 seconds
```

This proves the watchdog leaves `.failed` / not `.syncing`. Live `"test"` exercised the fast-success path (empty recall) on the installed binary.

---

## Scorecard note (audit owner)

- **BIN-66 Recent queries: PASS** — persisted UserDefaults last-8; empty+expanded only. Linear already **Done**; no remediations.

---

## Tracking

| ID | Action |
|----|--------|
| BIN-55 | Comment: hang timeout live dogfood PASS + direct-exec env fix |
| BIN-69 | Comment: hang/env slice green; full capability dogfood still incomplete → stay **In Progress** |
| Multica HAB | **SKIP** (no Multica MCP in this harness) |

---

## Out of scope / not claimed

- Full BIN-69 capability matrix (`memory.store`, `infer.write`, `project.state` list) — still open  
- Snapshot re-record (BIN-83)  
- Invented sub-second stopwatch when AX poll missed Working frame  
