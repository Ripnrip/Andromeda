# Process Guardian — daemon-sprawl kill chain

**Date:** 2026-08-26 · **Author:** Berserker (Letta) · **Status:** ACTIVE
**Tickets:** HAB-369/370/371/372 (Multica) · Linear unavailable (no BIN team in CLI; noted)
**Repo lane:** `feat/process-guardian` → PR

## 1. The crime scene

Activity Monitor (2026-08-25 ~23:45–00:15, peak state):

- **~16 `com.apple.dt.Xcode.sourcecontrol.Git` daemons** at 1.7–2.6 GB RSS each (~30 GB) across admin AND root, while Xcode itself hung (Not Responding).
- **~45 cloned `node` processes** at ~118 MB each — the stdio-MCP-per-session pattern (root-caused 2026-08-24 for qdrant specifically; this is the fleet-wide edition).
- **61.86 GB swap** on a 32 GB machine; CapCut / Xcode / Firefox / ChatGPT all Not Responding (victims, not causes).

Live state tonight (2026-08-26 01:19): horde gone (0 Git daemons), 55 node procs but only ~0.3 GB, swap 14.2 GB, memory 58% free. **The peak is a recurrence, not an accident.**

## 2. The causal chain (2 + 2)

```
agent sessions (Claude Code / Codex / Cursor / Trae)
  → stdio MCP children per session (xcodebuildmcp ×6, memory ×4,
    sequential-thinking ×4, filesystem/playwright/cerebras ×3+)
  → xcodebuildmcp invokes xcodebuild
  → Xcode SourceControl XPC spawns com.apple.dt.Xcode.sourcecontrol.Git
  → daemons leak (age without bound; two Xcode installs amplify:
    Xcode.app = 26.0 (Sep 2025, stale) + Xcode-26.6.0.app = 26.6)
  → 30 GB daemon RSS + 62 GB swap → everything Not Responding
```

Two sprawl families, one chain. The guardian breaks it at both ends:
reap the daemon accumulation, reap the orphaned MCP children.

## 3. Design — `ProcessGuardian` (Fleet pillar: typed Swift, never bash)

**Home:** `Sources/AndromedaHostOps/ProcessGuardian.swift` (root package,
sibling to PowerLeaseCoordinator / TestFlightUploader) + `andromeda guardian`
CLI subcommand (pattern: PR #45's testflight subcommand).

**Policy engine (pure, unit-testable):** `ProcessSample[] → KillDecision[]`.
Given a process census (pid, ppid, user, age, rss, executable path, args),
emit reap decisions per rules:

- **R1 — Source-control daemons.** If no live Xcode/xcodebuild process exists,
  reap ALL `com.apple.dt.Xcode.sourcecontrol.Git`. If Xcode IS alive, keep the
  newest N=2 per user, reap the rest. Reap any daemon older than 6h regardless
  (leak signature; Xcode respawns on demand — kill is recoverable, no data
  loss: these are read-only SCM helpers).
- **R2 — Orphaned MCP children.** Reap `node` processes whose args match the
  known MCP-server set (filesystem, memory, sequential-thinking, playwright,
  xcodebuildmcp, qdrant, cerebras, chrome-devtools, claude-mem launcher) when
  (a) PPID == 1 (orphaned), or (b) parent process no longer exists, or (c)
  age > 4h with zero connections to a live session. Never reap a node whose
  parent chain reaches a live agent host (Claude.app, codex, Cursor, Trae,
  claude.exe).
- **R3 — Pressure escalation.** If `vm.swapusage` used > 24 GB or memory
  pressure ≥ warn: tighten R1 to keep N=1, tighten R2 age to 1h, log ESCALATED.
- **R4 — Never touch.** User apps (CapCut, Firefox, ChatGPT, Finder) even when
  Not Responding (destructive = human's call, AGENTS.md triple-confirmation
  law). Simulator. Anything in the guardian's own parent chain. launchd-owned
  system daemons outside the named set.

**Execution:** SIGTERM first, SIGKILL after 10s grace if still alive.
Idempotent: same census → same decisions. Bounded: one sweep per invocation.

**Observability (AGENTS.md law — visible status, telemetry, ownership,
controls):**
- JSON-lines telemetry log: `~/.andromeda/logs/guardian.jsonl` (sweep id,
  census size, decisions, kills, pressure state).
- `andromeda guardian status` — last sweep, live census summary, config.
- `andromeda guardian sweep --dry-run` — prints the kill set, kills nothing.
- `andromeda guardian sweep` — manual sweep (used by the LaunchAgent too).
- LaunchAgent `com.andromeda.process-guardian.plist` — every 10 min,
  RunAtLoad, logs visible. Install path: typed Swift `guardian install`
  (BIN-101 law — no launchctl-by-hand).

**Tests (canon):** policy engine fixtures (census JSON → expected kill sets):
daemon cap math, orphan detection, parent-chain protection, pressure
escalation, never-touch list, TERM→KILL escalation, idempotency. No real
process kills in tests — the executor is protocol-injected
(`ProcessKiller` protocol; tests use a recording mock).

## 4. Immediate relief (pre-PR, tonight)

Live horde is already gone (peak decayed on its own). Remaining relief:
audit + reap ONLY verified orphans from the current 55 node procs (dry-run
first, show the set, kill orphans only). Xcode 26.0 stale install: flag to
BofA (do not delete apps without his word).

## 5. Tickets

- **HAB-369** — ProcessGuardian policy engine + executor (Sources/AndromedaHostOps, canon Swift 6)
- **HAB-370** — `andromeda guardian` CLI (sweep/status/install) + LaunchAgent + telemetry log
- **HAB-371** — Verify the xcodebuildmcp→SourceControl daemon coupling (instrument: next peak, capture parent chains of Git daemons; plan assumes but does not yet prove MCPs trigger the horde)
- **HAB-372** — Fleet hygiene decision: Xcode 26.0 (Sep 2025) stale install — keep/remove + `com.manus.hab344.*` orphan plists cleanup
- (cross-link: swift-canon Exhibit 7 + testing.md determinism overhaul ride this branch)

## 6. Rollback

Guardian uninstalls via `guardian uninstall` (bootout + plist removal). All
kills are of recoverable, on-demand-respawn helpers — no user data, no
databases, no remote state. Single-revert PR.

## 7. Out of scope (honest boundaries)

- Killing hung USER apps (destructive — human decision per AGENTS.md).
- Consolidating MCPs to shared network services (the qdrant precedent) —
  bigger design, separate workstream (MCP-SPRAWL docs in multibrain own that).
- vm.swap tuning / macOS memory management itself.
