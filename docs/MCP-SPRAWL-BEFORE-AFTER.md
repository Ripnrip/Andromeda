# MCP Sprawl — Before / After (BIN-41)

> **Host:** Studio Mac  
> **Issue:** Linear [BIN-41](https://linear.app/binary-bros/issue/BIN-41/mcp-dedupe-registry-cleanup-post-visible-alpha-wave) · Multica HAB-64  
> **No secrets** in this file (no API keys, tokens, or env values).

Companion: [MCP-SPRAWL-PROBLEM.md](./MCP-SPRAWL-PROBLEM.md) · ops runbook [MCP-SPRAWL-OPS.md](./MCP-SPRAWL-OPS.md)

---

## Commands used (exact)

```bash
# Parent count + package breakdown
pgrep -lf 'npm exec'

# Per-PID broker / TTY / RSS (batch)
ps -o pid=,ppid=,tty=,stat=,rss=,command= -p "$(pgrep -f 'npm exec' | paste -sd, -)"

# Orphan definition (used in proof scripts)
# orphan = ppid == 1 OR ppid not in live `ps -axo pid=` set
```

Machine snapshots (local only, not committed): `/tmp/mcp-sprawl-BEFORE.json`, `/tmp/mcp-sprawl-AFTER.json`.

---

## BEFORE — 2026-07-17T03:59:45Z

| Metric | Value |
|--------|------:|
| **`npm exec` parents** | **55** |
| Orphans (dead broker) | 0 |
| Historical reference (2026-07-15 doc) | 60 |

### Top offenders (package)

| Count | Package |
|------:|---------|
| 14 | `@modelcontextprotocol/server-filesystem` |
| 14 | `@modelcontextprotocol/server-memory` |
| 14 | `@modelcontextprotocol/server-sequential-thinking` |
| 2 | `firecrawl-mcp` |
| 2 | `@magicuidesign/mcp` |
| 2 | `@remotion/mcp` |
| 2 | `@anaisbetts/mcp-installer` |
| 1 each | `ios-simulator-mcp`, `openai-websearch-mcp`, `@supabase/mcp-server-supabase`, `@modelcontextprotocol/server-pdf`, `@browsermcp/mcp` |

### Session / TTY split

| TTY | `npm exec` count | Notes |
|-----|-----------------:|-------|
| `??` | 25 | Detached / GUI brokers (Cursor Helper, Grok, Claude.app, etc.) |
| `ttys003`…`ttys027` | 3 each × 10 | Classic Claude CLI “trio” per TTY (filesystem + memory + sequential) |

### Top live brokers (children count)

| Children | Broker (redacted) |
|--------:|-------------------|
| 11 | `grok` session |
| 7 | Cursor Helper: `mcp-process` |
| 3 × many | Claude Code CLI sessions (cmux / zsh) |
| 1 | Claude.app PDF MCP wrapper |

---

## Actions taken (safe)

### Config (affects **new** sessions only)

| Host file | Change |
|-----------|--------|
| `~/.codex/config.toml` | Removed duplicate `cerebras-fixed` (identical to `cerebras-mcp`); added `-y` to `playwright` args |
| `~/.claude/.mcp.json` | Removed `browsermcp` (already configured in `~/.claude.json` top-level) |
| `~/.cursor/mcp.json` | No change — all `npx` entries already had `-y`; no same-file duplicate keys |
| Firecrawl | **No flip** — Cursor keeps `npx` + `FIRECRAWL_API_KEY` env; Codex already HTTP. Avoids copying URL-embedded credentials across hosts |

### Live process trim (evidence-gated)

- **Did not** `pkill` all Claude TTYs.
- **Did** SIGTERM `npm exec` (+ node MCP children) whose broker was:
  - Claude CLI (not Cursor, not Claude.app, not Grok)
  - `pcpu == 0.0`
  - etime ≥ 24h
- **6** idle brokers → **18** `npm exec` parents terminated (plus matching node children).
- Orphan kill: **N/A** (0 orphans with dead brokers).

Idle broker PIDs trimmed (brokers themselves left alive): `9683`, `3879`, `1745`, `4920`, `13221`, `68448`.

---

## AFTER — 2026-07-17T04:01:13Z

| Metric | Value |
|--------|------:|
| **`npm exec` parents** | **37** |
| Orphans | 0 |
| **Delta** | **55 → 37 (−18)** |

### Top offenders after

| Count | Package |
|------:|---------|
| 8 | `@modelcontextprotocol/server-filesystem` |
| 8 | `@modelcontextprotocol/server-memory` |
| 8 | `@modelcontextprotocol/server-sequential-thinking` |
| 2 | `firecrawl-mcp` / `@magicuidesign/mcp` / `@remotion/mcp` / `@anaisbetts/mcp-installer` |
| 1 each | remaining one-offs |

### TTY split after

| TTY | Count |
|-----|------:|
| `??` | 25 |
| `ttys004`, `007`, `010`, `014` | 3 each (active Claude sessions kept) |

---

## Honesty / residual

| Claim | Reality |
|-------|---------|
| Config dedupe alone dropped live count | **No** — live drop is from idle trim (−18). Config prevents *future* duplicate cerebras / browsermcp / missing `-y` prompt stalls |
| Count will fall further without restarts | **Unlikely** — remaining 37 are attached to live Cursor / Grok / active Claude brokers |
| Path to ~15–20 parents | Restart idle Claude/cmux panes; optionally disable the filesystem/memory/sequential trio on hosts that already get them from Cursor; long-term: Andromeda `MCPServerRegistry` shared lifecycle |
| Vs 2026-07-15 baseline (60) | **60 → 37** (−23) across days + this pass |

---

## Big scoreboard

| Snapshot | `npm exec` parents | filesystem | memory | sequential-thinking |
|----------|-------------------:|----------:|-------:|--------------------:|
| 2026-07-15 inventory | 60 | 15 | 15 | 15 |
| **BEFORE** this pass | **55** | **14** | **14** | **14** |
| **AFTER** this pass | **37** | **8** | **8** | **8** |
| Delta (this pass) | **−18** | −6 | −6 | −6 |
