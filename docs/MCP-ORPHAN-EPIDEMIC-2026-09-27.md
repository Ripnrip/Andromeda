# MCP Orphan Epidemic — 2026-09-27

> Evidence record for HAB-727. Operator-only. No secrets.
> Companion runbook: [MCP-SPRAWL-OPS.md](./MCP-SPRAWL-OPS.md) ·
> Problem inventory: [MCP-SPRAWL-PROBLEM.md](./MCP-SPRAWL-PROBLEM.md) ·
> Follow-up wave: [MCP-ORPHAN-WAVE-2-2026-09-28.md](./MCP-ORPHAN-WAVE-2-2026-09-28.md) (HAB-731)

## What happened

Activity Monitor showed 13 `python3.13` processes at ~300 MB each (AM accounting;
actual RSS 4–17 MB each — AM counts mapped/compressed pages). All were MCP
servers spawned by the **claude-mem plugin** of Claude Code sessions:

- 6× `chroma-mcp` pairs (`uv tool uvx` wrapper + python child), all pointing at
  `~/.claude-mem/chroma`, versions `chroma-mcp==0.2.6`
- 3× `qdrant-mcp-server` (uv tools install)

Ages at discovery: **11 days** (since Sep 16), **7+ days** (since Sep 20), and
one fresh (minutes). Every Claude Code session with claude-mem spawns a new
set; when the session exits, the stdio children are **not reaped** and get
reparented to launchd (ppid 1). An 11-day-old `claude.exe --resume` (PID 75289)
still holds a qdrant server as of this writing — owned, not touched.

## Why infra.mcp.scan missed it

`MCPServerRegistry.looksLikeMCP` had no `chroma-mcp` needle — the single
largest offender was invisible to the scanner. Fixed in this change set.

## Response (manual pass, per MCP-SPRAWL-OPS.md §3)

| Time (EDT) | Action | Result |
|---|---|---|
| 21:15 | SIGTERM 8 dead-broker processes | python children died; 4 uvx wrappers survived |
| 21:18 | SIGKILL escalation on wrappers | wrappers already exiting; 13 → 5 |
| 21:36 | `andromeda mcp-hub reap --apply` (new) | reaped 1 fresh orphan (70317) born mid-build |

Steady state: 2 MCP servers, both owned by live Claude brokers (67426, 75289).

Note from the field: **uvx wrappers ignore SIGTERM** when their child holds the
pipe — the reaper escalates to SIGKILL after 300 ms by design.

## Shipped (this branch: `feat/mcp-orphan-reaper`)

| Piece | Path |
|---|---|
| Classifier + reaper actor (OSLog `infra.mcp.reap`) | `Packages/MemoryKit/Sources/MemoryKit/Registry/MCPOrphanReaper*.swift` |
| `andromeda mcp-hub reap [--apply]` (dry-run default) | `Sources/AndromedaCLI/MCPHubCommands.swift` |
| `chroma-mcp` scanner needle | `Packages/MemoryKit/Sources/MemoryKit/Registry/MCPServerRegistry.swift` |
| Tests (chain walks, ownership, dry-run) | `Packages/MemoryKit/Tests/MemoryKitTests/MCPOrphanReaperTests.swift` |

Classification contract:

- `orphaned` — ancestor chain hits ppid 1 or a PID absent from the live table
- `owned` — chain reaches a live broker (claude/cursor/codex/hermes/cmux/electron)
- `unknown` — anything else; **never signaled**

The observe-only `MCPServerRegistry` remains observe-only. The reaper is a
separate, explicit, opt-in lifecycle surface (`--apply`), per the AGENTS.md
rule that mutations be visible and controlled.

## Root-cause fix (not in this branch)

The durable fix is the shared MCP hub (ADR-0019): clients connect to hub
sockets instead of spawning per-session stdio servers. Until claude-mem runs
through the hub, orphan accumulation continues — run
`andromeda mcp-hub reap` (or `--apply`) as the stopgap.
