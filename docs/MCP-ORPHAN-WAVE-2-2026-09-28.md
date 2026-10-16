# MCP Orphan Wave 2 — 2026-09-28 (HAB-731)

> Evidence record for HAB-731. Operator-only. No secrets.
> Prior wave: [MCP-ORPHAN-EPIDEMIC-2026-09-27.md](./MCP-ORPHAN-EPIDEMIC-2026-09-27.md) (HAB-727) ·
> Runbook: [MCP-SPRAWL-OPS.md](./MCP-SPRAWL-OPS.md)

## What happened

At 00:10 EDT, Activity Monitor (user screenshot) showed **8 identical `node`
processes at 3.4–3.6 GB each (~28 GB total)** — 12 threads and 31–32 open ports
per process. Observed PIDs (7 of the 8 recorded; one PID was not captured in
the screenshot — count is from the AM total):

`24459 · 24465 · 24508 · 24526 · 24538 · 24988 · 25004` (+1 unrecorded)

Alongside them: `lldb-rpc-server` at 3.79 GB (PID 59562), WindowServer 2.73 GB,
Obsidian Helper (GPU) 2.03 GB, one Chrome renderer at 1.78 GB.

**By 00:12 all 8 node PIDs and lldb-rpc-server were dead** (`ps -p` returned
nothing on every PID; `memory_pressure` reported 73% free). The wave lasted
minutes and **self-resolved — no reaping was performed**. This record documents
the wave; it was gone before any intervention was possible.

## Spawner context (alive at 00:12)

| PID | What | State |
|---|---|---|
| 23356 | `claude.exe -p --output-format stream-json --input-format stream-json --verbose --permission-mode bypassPermission` (headless, up 12 min, parent 41402) | live — the likely spawner |
| 23410 | claude-mem 13.14.0 `mcp-server.cjs` (child of the above) | live |
| 29037 / 29076 | claude-mem observation hooks, firing ~every 15 s | live |

The 8 bloated node processes died while this broker survived, so they were not
the broker itself — most plausibly burst-spawned children (MCP/worker
restarts) of the headless claude-mem session. **No post-mortem of the dead
PIDs was possible** — they left nothing to inspect. That is the honest limit of
this record.

## How this differs from Wave 1 (Sep 27)

| | Wave 1 (HAB-727) | Wave 2 (this, HAB-731) |
|---|---|---|
| Processes | 13 `python3.13` MCP servers (chroma/qdrant) | 8 identical `node` processes |
| Memory each | ~300 MB AM / 4–17 MB RSS | **3.4–3.6 GB each** |
| Lifetime | 7–11 days | minutes |
| End | Manual SIGTERM/SIGKILL + reaper | **Self-resolved, untouched** |
| Root | claude-mem stdio children not reaped on session exit | unconfirmed — died before inspection |

Wave 1 was accumulation (slow leak, long-lived). Wave 2 was a burst (huge,
brief). Different failure shape — do not assume the Sep 27 root cause covers it.

## Reaper verification on the live tree (post-wave)

`andromeda mcp-hub reap` (dry-run, built from this branch `feat/mcp-orphan-reaper`,
2026-09-28 ~04:24 EDT):

```
scanned MCP-looking processes: 9
  🧺 orphaned pid 8119 (90.1 MB) — chain reparented to launchd (ppid 1) — broker is gone
  🔒 owned pid 8155, 8156 — claude-mem chroma pair under 8119
  🔒 owned pid 67494/67581, 67766, 67833, 67897, 68327 — chain reaches live broker 67426
orphans: 1 | reaped: 0 | failed: 0
```

Dry-run only — **no `--apply` was run** for this record. The one orphan found
(PID 8119, claude-mem `worker-service.cjs --daemon` under bun, reparented to
launchd) is a fresh leftover from a later claude-mem session, not a survivor of
the 00:10 wave. Classifier behaves per contract (owned chains walked to broker
67426; `unknown` never signaled).

## Contrast: intentional PPID-1 daemons are not orphans

Three `node …/mcporter daemon start --foreground` processes (PIDs 29300/29313/
29314, PPID 1, up **15 days**) are *intentional* daemons — they were designed to
be reparented to launchd. Orphan classification must stay command-shape-based
(MCP-looking + dead broker chain), never "ppid 1 ⇒ kill". These are FINE; do
not reap.

## Open questions (HAB-731 follow-up)

1. What were the 8 node processes? No capture exists of their argv. Next wave:
   screenshot first, then immediately `ps -o pid,ppid,rss,command -p …` before
   they die.
2. Why did each hold 31–32 ports? Suggests identical listeners — possibly 8
   restarts of the same server, not 8 different servers.
3. Does claude-mem 13.14.0 burst-spawn workers under headless
   `claude -p --permission-mode bypassPermissions`? Needs a reproduction with
   the hub (ADR-0019) in observe mode.

## Stopgap (unchanged from Wave 1)

Until claude-mem runs through the shared MCP hub, orphan accumulation
continues. Run `andromeda mcp-hub reap` (dry-run) to inspect,
`--apply` to reap — per [MCP-SPRAWL-OPS.md](./MCP-SPRAWL-OPS.md) §3.
