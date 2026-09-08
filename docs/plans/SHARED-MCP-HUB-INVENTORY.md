# Shared MCP Hub — Phase 0 Inventory (2026-09-08)

> Live re-scan (the plan doc's §1 inventory was 2026-09-05; drift confirmed).
> Numbers below are from this host today, gathered by direct config reads.

## Live config inventory (2026-09-08)

| Host | File | Keys | Delta vs 09-05 |
|---|---|---|---|
| Claude Code | `~/.claude.json` | **13** (browsermcp, filesystem, memory, openaiDeveloperDocs, sequentialthinking, pageindex-local, qdrant, multica, linear, career-ops, swift-lsp, playwright, python-lsp) | +3 (swift-lsp, playwright, python-lsp new) |
| Claude Code | `~/.claude/.mcp.json` | (cerebras-mcp per 09-05; not re-read this pass) | — |
| Codex | `~/.codex/config.toml` | **20** stanzas (chrome-devtools, openaiDeveloperDocs, firecrawl, playwright, node_repl, browsermcp, filesystem, memory, pageindex-local, sequentialthinking, stitch, cerebras-mcp, qdrant, computer-use, multica, linear, cua_repl, …) | ~same |
| Claude Desktop | `claude_desktop_config.json` | 3 (quake-coding-arena, XcodeBuildMCP, obsidian-mcp-tools) | same |
| Cursor | `~/.cursor/mcp.json` | **1** (claude-mem) | drift confirmed (16 → 1 since July) |
| Hermes local | `~/.hermes/config.yaml` | url-form: higgsfield, agent-zero, gbrain (+obsidian per 09-05); command-form: mempalace | same shape |

Live sprawl signal: ~100 process lines matching `npm exec|npx -y|mcp` on
this host today (includes the survey's own grep; the plan's measured
baseline was 37-60 npm-exec parents — same order).

## Resolved entrypoints (config/mcp-hub/servers.example.json)

| Server | Resolved real entrypoint |
|---|---|
| filesystem | `/Users/admin/.npm/_npx/a3241bba59c344f5/.../server-filesystem/dist/index.js` (behind the named launcher) |
| memory | `/Users/admin/.npm/_npx/15b07286cbcc3329/.../server-memory/dist/index.js` (behind the named launcher) |

`npx -y` cache paths are content-addressed but not guaranteed stable
across cache clears — the launcher's `require` path is verified by
`andromeda mcp-hub validate` before any cutover.

## Spike results

- **S1 naming (remainder):** byte-copied shim binaries sharing one ad-hoc
  cdhash — **deferred to install-time verification** (needs the built
  binaries; the shim's `--server` flag covers dev mode without copies).
  node `process.title` ✓ (proven 09-05, launchers shipped here use it).
- **S2 framing:** the relay's line-delimited pass-through with id
  namespacing is unit-proven (18/18 tests: collisions, notifications,
  cancelled rewriting, unknown-field preservation, id-shape restoration).
  Live-client verification (Claude Code ↔ hub ↔ filesystem) is the
  Phase-1 acceptance step on this branch.
- **S3 classification:** filesystem = `shared` (stateless per-request);
  memory = `shared` **with a semantic decision**: one shared
  `MEMORY_FILE_PATH` makes memory *actually shared across agents* —
  matches the Anima direction, but the multibrain visibility/cloak tag
  rules must be reviewed before cutover (flagged; default path in the
  example config points at a NEW dedicated file, not any existing
  per-agent memory, so nothing silently merges).
  browsermcp/playwright/chrome-devtools = `passthrough` candidates
  (per-session state) — not in wave 1.
- **S4 TCC:** not re-run this pass (requires Full Disk Access context);
  the 09-05 survey stands (andromeda-mcp adhoc ✓, mempalace/qdrant-mcp
  unsigned ✗ migration candidates).

## Wave-1 roster (MVP)

filesystem + memory only — both `shared`, secret-free (SecretsBroker
stub gates the env-bearing ones), stateless-or-tagged.
