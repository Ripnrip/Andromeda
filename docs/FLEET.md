# Fleet — Multi-Brain Hosts

Who runs what. Studio facts are locally documented; Book was verified 2026-07-14 but
its live state is **unverified today**. Ops detail: [RUNBOOK.md](RUNBOOK.md).

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

## Full machine matrix

| Machine | Fleet role | Stores / flows | Current caveat |
|---------|------------|----------------|----------------|
| Studio | Phase-2 hub | canonical SecondBrain deposit, SwiftData hot store, `state.db`, Letta/Postgres, Ladybug, Qdrant, Multica | hub services are Python/native services, not a shipped all-Swift runtime |
| Book | Phase-1 satellite | local vault mirror, nightly + health + Telegram | live jobs/tunnels unverified today; report failures as degraded |
| Mac Mini | isolated lane | its own local state only | **not** a hive satellite unless explicitly promoted |
| habitat VM | Hermes source | `~/.hermes/state.db` via read-only SSH extractor | tunnel can degrade without stopping Studio-local sources |
| iPhone | MinIO/Obsidian sync client | curated file sync/consumption | not CloudKit-shipped proof or a hub |
| iMac | aspirational CloudKit satellite | none declared live | planned only |

## LaunchAgent install policy

| Plist | Studio | Book |
|-------|--------|------|
| `com.multibrain.nightly` | install (02:30) | install (remap HOME, **03:00**) |
| `com.multibrain.health` | install | install (remap HOME) |
| `com.multibrain.claude-mem-worker` | install | optional |
| `com.multibrain.letta*` | install | **do not** |
| `com.multibrain.index-server` | install | **do not** |
| `com.multibrain.retro` | install | **do not** |
| `com.multibrain.dreamcatcher` | install (`--no-llm`) | optional / **do not** by default |

Repo `ops/*.plist` bake Studio absolute paths (`/Users/admin/...`). Always rewrite `HOME` + script paths for other users.

## Config expectations

**Studio (hub)** sets: `vault_dir`, `staging_dir`, `state_db`, `claude_mem_db`, `synthesis_backend=zai` (or omit — defaults to z.ai → `--no-llm`), `graphify_nightly`, Telegram keys, optional `"role": "hub"`.

**No OpenRouter on Studio nightly (locked 2026-07-15).** Hub `run-nightly.sh` ignores `synthesis_backend=openrouter` if Ladybug + Letta runtime are present. Dreamcatcher LaunchAgent forces `--no-llm`. Letta's conversational path may still reference OpenRouter in runtime env — rotate keys as a **human Linear-only** task (never commit secrets).

**Book (satellite)** may set `synthesis_backend=openrouter` only as an explicit opt-in (historically hit HTTP 402). Prefer `zai` or `no-llm`. Add `vault_dir` pointing at Book’s `~/Developer/SecondBrain/07-Sessions` so consolidate and git steps agree. Auto-detect marks Book as `satellite` when no `.lbug` / Letta runtime is present.

## Known satellite issues (2026-07-14; re-verify live)

- Book nightly recently hit **OpenRouter HTTP 402** → fell back to `--no-llm` templates; health went RED and Telegram fired. Prefer killing OpenRouter on satellites too when possible.
- Book repo tip can lag Studio; pull before expecting new hub-only scripts.
- Book `ops/` templates still look like Studio — trust installed LaunchAgents under `~/Library/LaunchAgents/`, not the raw templates.

## Mini

Mac Mini stays in an **isolated lane**. Do not install the hive nightly, Letta,
Ladybug, or Qdrant there by default. Any future promotion requires an explicit
operator decision and a fresh inventory. Horizon-4 “Docker Hermes on mini” is
outdated; habitat SSH remains the documented Hermes feeder.