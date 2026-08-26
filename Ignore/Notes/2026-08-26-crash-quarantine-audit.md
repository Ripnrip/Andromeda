# Crash-Quarantine 2026-08-04 — Audit & Findings

**Date:** 2026-08-26 (found while wiring the nightly sweep) · **Tracking:** HAB-377 · **Location:** `~/Library/LaunchAgents/disabled/crash-quarantine-2026-08-04/`

## What happened

On 2026-08-04 a bulk quarantine moved **37 LaunchAgent plists** into `disabled/crash-quarantine-2026-08-04/` (crash-storm era — same window as the zsh-5.9/Manus buffer-overflow crashes, HAB-360). Since then services have drifted into three states, and **nothing tracked which** — including the health watchdog itself being quarantined, so silence looked like health.

## State of the 37 (cross-referenced 2026-08-26 02:30)

### ✅ Live again (restored / reincarnated — 12)
| Quarantined plist | Live mechanism |
|---|---|
| com.multibrain.nightly | restored by hand 2026-08-26 (this session) — verified firing |
| com.multibrain.anima-vault-sync | restored 2026-08-15 (documented fix) |
| com.multibrain.index-server | live plist (Ladybug warm index) |
| com.multica.stack / daemon | stack live (daemon runs via Multica app path) |
| com.qdrant.server | reincarnated as **com.qdrant.secondbrain** (port 6333 healthy) |
| com.scrolltracker.intake | live |
| com.careerops.email-watcher | live |
| homebrew.mxcl.mysql / postgresql@17 | live (brew re-registered) |
| dev.agent-habitat.boot | live |
| com.multibrain.andromeda-home / fleet-observe-bar | run as **GUI applications** (launchd app domain, different mechanism) |
| com.multibrain.claude-mem-worker | worker healthy on :37777 via watchdog/`claude-mem-ensure-worker.sh` — **plist still quarantined** (fragile: relies on someone reviving it) |
| homebrew.mxcl.tailscale | running via Tailscale.app |

### ⚠️ Loaded-but-suspicious (1)
- com.careerops.scan — appears in `launchctl list` though its plist sits in the quarantine dir (loaded from unknown path / stale registration). Verify + re-home.

### 🔴 True orphans — quarantined, no live counterpart, silently dead (rest, needs triage)
com.andromeda.hud · com.multibrain.dreamcatcher · com.multibrain.retro · com.multibrain.health (hourly health!) · com.multibrain.letta + letta-bridge + letta-shim · com.multibrain.multibrain-bar · com.multibrain.runtime-failover · ai.router-watchdog · com.binarybros.vault-backup · com.binarybros.clawket-bridge (superseded by ai.hermes.bridge.clawket?) · com.gurinder.warroom · com.local.mac-mini-vnc-tunnel · com.local.mini-health-monitor · homebrew.mxcl.ollama · homebrew.mxcl.postgresql@14 · homebrew.mxcl.lume · com.swiftbar.spotlight-toggle · actions.runner.* · com.careerops.scan (see ⚠️)

**Each needs an explicit restore-or-retire decision.** Some are surely obsolete (postgres@14 next to live @17); others are load-bearing-but-dead (multibrain.health means no hourly dead-man; runtime-failover means Multica failover is down).

## Systemic findings (this session, all fixed or ticketed)

1. **Phantom `last_success` defeats catch-up guard.** The restored nightly fired at 02:30:02, ran <1s, exit 0, *no log lines*: the catch-up guard saw `last_success = 2026-08-26T05:10:07Z` — stamped **while the job was quarantined** (writer: some non-launchd `healthcheck.py --mark-success` pass; crontab empty). The guard assumes one writer; quarantine broke that. **Rule: after restoring a quarantined periodic job, `--force` once or clear the marker** (done: forced run verified 02:38 with sweep artifacts).
2. **Quarantine has no exit protocol.** Three weeks of drift, zero paper trail. Fix: audit tool (below) + a rule that any restore event updates this note.
3. **macOS 26 beta signing monitor SIGKILLs freshly-copied SwiftPM binaries** (`Code Signature Invalid / Invalid Page`, even for `help`). Fix: fresh `cp` + `codesign -f -s -` on binary AND every `@rpath` dylib. Now in swift-canon `cli-and-process.md`.
4. **Stray `~/.git`** (accidental Andromeda clone tracking `$HOME`, plaintext PAT in remote URL) hung every git-touching tool run from home. Archived to `~/.git-stray-archive-20260826`; **PAT rotation still owed**.
5. **OpenLoopTracker was dead-on-arrival** (installer rpath bug) — fixed + multi-agent (HAB-373).

## Recommended follow-ups

- [ ] One-shot **quarantine-audit tool** (Swift, fleet-cousin of herd-gather): quarantine dir × `launchctl list` × process/port liveness → table + per-orphan ticket. 
- [ ] Restore-or-retire each 🔴 orphan (start: multibrain.health, runtime-failover, letta trio, andromeda.hud).
- [ ] Rotate the leaked PAT; then delete the archive dir.
- [ ] Add "restore = force-run once + note here" to the ops runbook.
