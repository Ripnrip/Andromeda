# claude-mem Hook Fix — Swift Launcher + SwiftGate Provider

> 2026-09-28, HAB-731 lane (parent-executed). Fixes applied live on this machine.
> Forensic anatomy: [forensics/CLAUDE-MEM-ANATOMY.md](./forensics/CLAUDE-MEM-ANATOMY.md)

## Problem

Two chained failures in claude-mem 13.14.0 (fleet memory system — kept, fixed):

1. **Hook churn:** every hook event (7 kinds; `PostToolUse` = every tool call)
   ran a ~1.4KB inline bash prelude (`$SHELL -lc` login shell + glob/sort
   pipeline) that then invoked `claude-mem-hook-launcher.swift` **as an
   interpreted script** — `swift` recompiled it from source on every firing
   (visible as `swift-frontend` in Activity Monitor). 4 process generations
   per hook.
2. **Memory compression silently dead:** the `claude` provider spawns Claude
   SDK subprocesses that cannot auth in worker context — `SDK authentication
   failed; run /login` 200×/day in logs. With no SDK session, the summarize
   hook inserted rows with NULL `memory_session_id` →
   `NOT NULL constraint failed: session_summaries.memory_session_id` (72× on
   09-28 alone). Observations churned; summaries never landed.

## Fix (both verified live)

| Piece | What |
|---|---|
| Compiled launcher | `~/.local/bin/claude-mem-launcher`, ad-hoc signed `com.binarybros.claude-mem-launcher`, source kept at `~/.local/share/claude-mem-launcher-src/`. Added `--print-root` mode (root resolver without worker spawn). |
| Hooks rewritten | All 7 hook commands in the plugin's `hooks/hooks.json` now invoke the binary directly; bash preludes and `shell: bash` removed. Backup: `hooks.json.pre-swift-launcher.bak`. |
| Provider | `~/.claude-mem/settings.json`: `CLAUDE_MEM_PROVIDER=openrouter`, `CLAUDE_MEM_OPENROUTER_BASE_URL=http://127.0.0.1:20129/v1` (SwiftGate), `CLAUDE_MEM_OPENROUTER_MODEL=glm/glm-5.3` — per HAB-711 fleet model policy. The `openrouter` provider path takes any OpenAI-compatible base URL (`ote()` in worker-service.cjs honors `CLAUDE_MEM_OPENROUTER_BASE_URL`). |

## Proof (2026-09-28 00:28–00:31 EDT)

- A/B timing: old prelude 1.13s vs binary 0.47s per `PostToolUse` firing.
- After provider switch + worker restart, an observation hook produced:
  `Generator auto-starting (observation) using OpenRouter` →
  `MEMORY_ID_GENERATED provider=OpenRouter` →
  `OpenRouter API usage {model=glm-5.3, inputTokens=1387, outputTokens=313}` →
  `STORED … memorySessionId=openrouter-verify-swiftgate-001-… obsIds=[9758]`.
  The NOT NULL cascade is gone; no SDK auth errors since.

## Maintenance

Plugin updates reset `hooks/hooks.json` to upstream preludes (this fix was
applied once before and reverted by the Sep 20 update). Re-apply from
`~/.local/share/claude-mem-launcher-src/README.md` after every update.

## Open items

- Chroma backfill JSON parse errors (`Unexpected identifier "why"/"session"`)
  on old transcripts — pre-existing, separate from this fix.
- The 8×3.5GB node wave mechanism — see
  [MCP-MEMORY-WAVE-2026-09-28.md](./MCP-MEMORY-WAVE-2026-09-28.md).
