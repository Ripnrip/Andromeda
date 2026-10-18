---
description: Model fallback cascade + gateway pillar design. Primary → fallback → prune dead.
---

# Model cascade + gateway pillar (Andromeda / fleet lane)

## Problem
Agent retrieve hits a dead model (unknown, 429, 403) and surfaces the error instead of falling through. And at startup, dead providers aren't pruned — they stay in the agent's `model` / `model_settings`. The Slack bridge then sends empty/error messages. The user wants redundancy.

## Design (small, not framework)

Per-agent `model_tiers`: array of handles, verified at agent start / install.
- Tier 1 — native best (e.g., `xai/grok-4.6`) when provider auth is live.
- Tier 2 — openai-compatible fallback (e.g., `openai-compatible/glm/glm-5.3`) — always tested at load.
- Tier 3 — secondary openai-compatible (e.g., `openai-compatible/inkling/kimi-2.6`) if configured.

Startup verification (in `FleetCommand` / health probe):
1. For each tier, call `letta model list` / provider health endpoint (minimal `GET` to `/v1/models` or equivalent for the provider).
2. If tier responds with 200 + model present in catalog → keep active.
3. If tier fails (429, 403, unknown-model, timeout > 5s), mark `inactive`; log; don't try again in this session.
4. Agent's `retrieveAgent` tries tiers in order; on first failure, tries next; never exposes failure to Slack unless all tiers dead (then reply "model unavailable — retry").

## Provider pruning
From the Nous Portal screenshot (model marketplace with active discounts): many listed providers don't respond. Instead of pulling from every listed card, only pull from providers that pass the startup probe. Dead entries (like any "Osaurus" or non-responding openai-compatible slot) should be removed from active agent configs. The gateway pillar (`Hermes` / `claude-mem-all` concept) is the centralized aggregation layer that does this probing across all agents.

## Hermes gateway pillar
The `extract_hermes_vm.py` and `claude-mem-for-all.swift` already reference `~/.hermes/state.db`. Make it an Andromeda pillar:
- Source: `~/.hermes/state.db`, `multibrain/` worktrees, agent memfs repos.
- Structured output: model-availability table (provider / handle / status / last-check / cost/hour).
- Consumption: `andromeda fleet status` reads from gateway, not just local probe.
- Telemetry: provider quotas (like the openrouter/free quota that hit 429 today) feed into this.

## Implementation path (this worktree)
1. `FleetCommands.swift`: add `model_tiers` to `Install` spec (optional `--tiers` option or config file). Default: `xai/grok-4.6`, `openai-compatible/glm/glm-5.3` for this account.
2. `FleetStatus` / health probe: try the model handle via a minimal provider check (use existing `letta` CLI's model list or direct `curl` to provider endpoint) and surface tier status.
3. If all tiers dead → exit non-zero (alarm condition).
4. Prune dead tiers from agent records via a `fleet prune` subcommand (future).

## Notes
- The `openrouter/free` hit today (429 at 5h window) confirms quota limits need to be tracked — gateway pillar.
- `model_settings` should carry `context_window_limit`, `max_tokens`, `parallel_tool_calls`; don't drop them when switching tiers.
