# Fleet — Multi-Brain Hosts

Who runs what. Verified 2026-07-14 (Studio local + `ssh book.local`). Ops detail: [RUNBOOK.md](RUNBOOK.md).

## Topology

```
┌──────────────────────────────┐     Tailscale / LAN      ┌──────────────────────────┐
│ Studio (admin) — HUB         │◄────────────────────────►│ Book (gurindersingh)     │
│ Phase-2 full stack           │                          │ Phase-1 satellite         │
│ nightly 02:30                │                          │ nightly 03:00             │
│ Letta :8283 / bridge :8284   │                          │ consolidate + health      │
│ Ladybug :8286 / Qdrant :6333 │                          │ Telegram alerts           │
│ SecondBrain vault (canonical)│                          │ local SecondBrain mirror  │
└──────────────┬───────────────┘                          └──────────────────────────┘
               │ ssh habitat
               ▼
     ┌─────────────────────┐
     │ habitat VM          │
     │ Hermes state.db     │  (extractor: extract_hermes_vm.py)
     └─────────────────────┘
```

## Role matrix

| Capability | Studio (hub) | Book (satellite) |
|------------|--------------|------------------|
| `run-nightly.sh` | ✅ 02:30 | ✅ 03:00 |
| `healthcheck` + Telegram | ✅ hourly | ✅ hourly |
| claude-mem capture | ✅ + worker LaunchAgent | ✅ (worker optional; CAPTURE_BROKEN flag seen historically) |
| Local Hermes extract | ✅ | ✅ if `~/.hermes` present |
| Multica extract | ✅ `:5442` | only if Multica local |
| habitat Hermes SSH | ✅ | optional |
| LadybugDB + index-server | ✅ | ❌ → health `n/a` |
| Letta + shim + bridge | ✅ | ❌ → health `n/a` |
| Qdrant knowledge-sync | ✅ `:6333` | usually ❌ |
| Weekly retro LaunchAgent | ✅ Mon 08:00 | ❌ |
| `brain` CLI | ✅ | after chezmoi alias sync + hub reachability |

## LaunchAgent install policy

| Plist | Studio | Book |
|-------|--------|------|
| `com.multibrain.nightly` | install (02:30) | install (remap HOME, **03:00**) |
| `com.multibrain.health` | install | install (remap HOME) |
| `com.multibrain.claude-mem-worker` | install | optional |
| `com.multibrain.letta*` | install | **do not** |
| `com.multibrain.index-server` | install | **do not** |
| `com.multibrain.retro` | install | **do not** |

Repo `ops/*.plist` bake Studio absolute paths (`/Users/admin/...`). Always rewrite `HOME` + script paths for other users.

## Config expectations

**Studio** typically sets: `vault_dir`, `staging_dir`, `state_db`, `claude_mem_db`, `synthesis_model` / z.ai path, `graphify_nightly`, Telegram keys, optional `"role": "hub"`.

**Book** may only set `synthesis_backend=openrouter` + Telegram. Add `vault_dir` pointing at Book’s `~/Developer/SecondBrain/07-Sessions` so consolidate and git steps agree. Auto-detect marks Book as `satellite` when no `.lbug` / Letta runtime is present.

## Known satellite issues (2026-07-14)

- Book nightly recently hit **OpenRouter HTTP 402** → fell back to `--no-llm` templates; health went RED and Telegram fired.
- Book repo tip can lag Studio; pull before expecting new hub-only scripts.
- Book `ops/` templates still look like Studio — trust installed LaunchAgents under `~/Library/LaunchAgents/`, not the raw templates.

## Mini

Mac Mini is expected to follow the **satellite** pattern (openrouter synthesis, nightly + health) unless promoted to a second hub. Horizon-4 “Docker Hermes on mini” is outdated — prefer native Hermes / habitat SSH feeders.
