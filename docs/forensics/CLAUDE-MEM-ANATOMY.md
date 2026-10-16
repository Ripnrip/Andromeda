# claude-mem Anatomy — Forensics (2026-09-28)

> Parent-executed lane (subagent S1 was terminated by provider failover before
> writing this doc; the parent held the live evidence directly).
> Companion fix record: [CLAUDE-MEM-HOOK-FIX-2026-09-28.md](../CLAUDE-MEM-HOOK-FIX-2026-09-28.md) · HAB-731/HAB-736

## 1. Spawn-tree architecture (observed live, 2026-09-27/28)

```
launchd (1)
├── claude.exe -p --stream-json … (headless session, e.g. PID 23356)
│   ├── node -e "…claude-mem bootstrap wrapper…"        (PID 23385)
│   │   └── node mcp-server.cjs (claude-mem MCP, 13.14.0)  (PID 23410)
│   ├── [/bin/sh -c <1.4KB prelude>] → launcher → node worker   (hook events; FIXED — see below)
│   └── (per-session stdio MCP: chroma-mcp uvx pairs, qdrant — the HAB-727 orphans)
│
├── bun worker-service.cjs --daemon (PID 58319)   ← claude-mem persistent worker, port 37777
│   └── uv tool uvx … chroma-mcp (persistent chroma client)
│
├── node mcporter daemon start --foreground ×3 (PIDs 29300/29313/29314, 15 days)  ← INTENTIONAL
└── node dist/openauthServer.js, runtime-standalone.js (19 days, ~3 MB RSS each)
```

Key sources: `ps -axo pid,ppid,etime,rss,command` snapshots (session
transcript 2026-09-27 21:xx and 2026-09-28 00:10–00:31 EDT); plugin tree at
`~/.claude/plugins/cache/thedotmack/claude-mem/13.14.0/`.

## 2. Hook wiring (as shipped 13.14.0, pre-fix)

`hooks/hooks.json` registers 7 events, each a ~1.4KB inline bash prelude
(`$SHELL -lc` PATH recovery + cache-glob SemVer sort) ending in the Swift
launcher **interpreted from source**:

| Event | Matcher | Async | Worker verb |
|---|---|---|---|
| Setup | `*` | no | `version-check.js` via node |
| SessionStart | `startup\|clear\|compact` | no | `start`, then `hook claude-code context` |
| UserPromptSubmit | — | no | `hook claude-code session-init` |
| PreToolUse | `Read` | yes | `hook claude-code file-context` |
| PostToolUse | `*` | yes | `hook claude-code observation` |
| Stop | — | yes | `hook claude-code summarize` |

The observed ~15s cadence under headless `-p --stream-json` was simply
PostToolUse firing per tool call of the running agent session — no timer
inside claude-mem. Each firing: login shell → glob/sort → swift-frontend
recompile → node spawn (4 process generations, ~1.13s wall). **Fixed
2026-09-28**: compiled `claude-mem-launcher` binary, preludes amputated
(0.47s/firing) — see the hook-fix doc.

## 3. Ripgrep attribution

- `rg`/`ripgrep` grep of the plugin scripts (`mcp-server.cjs`,
  `worker-service.cjs`, `bun-runner.js`, `claude-mem-hook-launcher.swift`,
  `scripts/*`): **no ripgrep spawn site found** in the launcher/hook path.
- The runaway-`rg` sightings on this machine are therefore most plausibly
  Claude Code's own bundled ripgrep (the Grep tool binary ships inside the
  claude-code node package) or agent-issued searches under headless sessions —
  **not claude-mem**. Attribution remains circumstantial: no argv capture of a
  runaway instance exists. A watch-cycle that logs full argv of any `rg`
  crossing a CPU threshold would settle it.

## 4. Chroma footprint

`~/.claude-mem/chroma` — measured in the hook-fix session via `du`: the
persistent chroma store backing claude-mem memory; sizes on the order of a few
hundred MB with the sqlite + HNSW segment files dominating. The store is
single-writer: **two live chroma-mcp clients on the same data-dir is the hard
blocker for hub consolidation** (see the recipe doc).

## 5. Memory-wave mechanism (8×3.5 GB node, 00:10–00:12)

Best-supported explanation: **transient worker/dev-server cluster spawned by
the headless claude.exe -p session** — sequential PIDs (24459–25004),
identical shape (12 threads, 31–32 ports each), all dead within ~2 minutes,
spawner alive throughout, memory returned to 73% free. Confidence: medium —
no argv was captured before exit. What would confirm: a watch run catching the
next wave's full argv + parent chain (`andromeda mcp-hub watch`, shipped in
this branch). NOT a leak: contrast [MCP-ORPHAN-EPIDEMIC-2026-09-27.md]
(../MCP-ORPHAN-EPIDEMIC-2026-09-27.md) (slow accumulation, days-old, manually
reaped) vs [MCP-ORPHAN-WAVE-2-2026-09-28.md](../MCP-ORPHAN-WAVE-2-2026-09-28.md)
(burst, minutes-lived, self-resolved).

## 6. Hardening, ranked

1. ✅ **Done (HAB-736):** compiled launcher binary + SwiftGate provider —
   kills the 4-generation churn and the silent summarizer death.
2. **Re-apply discipline:** plugin updates reset `hooks.json`; re-apply from
   `~/.local/share/claude-mem-launcher-src/README.md`.
3. **Chroma through the hub** (recipe staged): eliminates per-session
   chroma/qdrant stdio spawns — the HAB-727 orphan class.
4. **Watch cadence:** run `andromeda mcp-hub watch --cycles N` after big
   agent sessions; waves and orphan births print with argv.
5. **Chroma backfill parse errors** (`Unexpected identifier "why"/"session"`)
   on legacy transcripts — separate bug, low priority.
