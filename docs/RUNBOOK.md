# Runbook — Multi-Brain Orchestration

Operational reference for the **live** system (verified 2026-07-14). Companion: [FLEET.md](FLEET.md), [ARCHITECTURE.md](ARCHITECTURE.md).

> `ops/*.plist` are **Studio path templates** (`HOME=/Users/admin`, nightly **02:30**). On Book, install only `nightly` + `health`, remap `$HOME`, set nightly **03:00**, and use `synthesis_backend=openrouter`.

## Layout at a glance

| Path | Role |
|------|------|
| `~/Developer/multibrain/` | **code + docs** — all pipeline scripts live in `bin/` |
| `~/Developer/multibrain/bin/` | extractors, `consolidate.py`, `run-nightly.sh`, health, alert, Letta bridge helpers, ingest/kimi/qdrant helpers |
| `~/.multibrain/` | **runtime data** (never committed): `config.json`, `state.db`, `health.json`, `last_success`, `logs/`, `multibrain.lbug`, `letta/` |
| `~/Developer/SecondBrain/` | Obsidian vault (deposit target) |
| `~/Library/LaunchAgents/com.multibrain.*.plist` | scheduled jobs |

Prefer **repo `bin/`**. Nightly falls back to `~/.multibrain/bin/ingest_staged.py` only if the repo copy is missing.

## `config.json` keys

| Key | Purpose | Hub default notes |
|-----|---------|-------------------|
| `vault_dir` | Deposit path (often `…/SecondBrain/07-Sessions`) | required for correct git/graph roots |
| `staging_dir` | Checkpoint staging (`…/multibrain/07-Sessions`) | |
| `state_db` | Dedup + baselines + alerts | `~/.multibrain/state.db` |
| `claude_mem_db` | Capture DB | `~/.claude-mem/claude-mem.db` |
| `synthesis_backend` / `synthesis_model` | `zai` / `openrouter` / etc. | Studio: z.ai; Book: openrouter |
| `telegram_bot_token` / `telegram_chat_id` | Alert channel | never commit; prefer env |
| `graphify_nightly` | bool — run graphify merge step | Studio often `true` |
| `role` | `hub` \| `satellite` | auto-detected from `.lbug` / Letta dirs if unset |

Book may ship a thinner config (`synthesis_backend` + Telegram only) — valid for Phase-1 satellites.

## Scheduled jobs

| Job | When | Host | Does |
|-----|------|------|------|
| `com.multibrain.nightly` | Studio **02:30** / Book **03:00** | both | ingest → extract → consolidate → ladybug → graphify → git → brief → health |
| `com.multibrain.health` | hourly | both | `healthcheck.py --quiet`; `alert.py` if exit ≥ 2 |
| `com.multibrain.claude-mem-worker` | every 60s + KeepAlive | **Studio** | `bin/claude-mem-ensure-worker.sh` |
| `com.multibrain.letta` | RunAtLoad + KeepAlive | **Studio** | native Letta `:8283` |
| `com.multibrain.letta-bridge` | RunAtLoad + KeepAlive | **Studio** | tool bridge `:8284` |
| `com.multibrain.letta-shim` | RunAtLoad + KeepAlive | **Studio** | z.ai Anthropic shim |
| `com.multibrain.index-server` | RunAtLoad + KeepAlive | **Studio** | Ladybug serve `:8286` |
| `com.multibrain.retro` | Mon **08:00** | **Studio** | `weekly_retro.py` |

Catch-up: `run-nightly.sh` skips if `last_success` is &lt;20h old unless `--force` (survives asleep Mac at 02:30).

### Nightly sequence (as-built)

```
0.   ingest_staged.py
1.   extract_claudemem.py          # also covered inside consolidate
2.   consolidate.py                # aggregate_digest multi-source + synthesis
2.5  index_ladybug.py              # rebuild .lbug; bounce index-server (hub)
3.   graphify_merge.py             # gated by graphify_nightly
4.   git commit vault
4.5  daily_brief.py
5.   healthcheck.py --mark-success then healthcheck
     fail() → alert.py
```

**Ordering note (Book health-fix):** stamp `--mark-success` only after a clean pipeline; hourly health alone must not mark success. Nightly already does this correctly — do not invert.

### Health plist bash note

Use `/bin/bash -c '…; rc=$?; if [ "$rc" -ge 2 ]; then … alert.py; fi'`. Avoid bare `sh` quirks; keep absolute paths to `python3` + scripts.

## Telegram alerts

- Implemented in `bin/alert.py` (Telegram primary).
- Creds: env → `~/.multibrain/config.json` → Hermes `.env` fallbacks.
- Dedup via `state.db` table `alerts`.
- Triggers: nightly `fail()`, hourly health RED, `--selftest`, `--message`.
- Email SMTP / Hermes APNs: documented aspirations — **not** in `alert.py` today.

```bash
python3 ~/Developer/multibrain/bin/alert.py --selftest
```

## Common operations

```bash
# Manual full run
~/Developer/multibrain/bin/run-nightly.sh --force
tail -f ~/.multibrain/logs/nightly.log

# Re-consolidate a day
python3 ~/Developer/multibrain/bin/consolidate.py --date 2026-07-01

# Health now
python3 ~/Developer/multibrain/bin/healthcheck.py
jq .status ~/.multibrain/health.json

# Librarian (Studio)
brain "what did we learn this week?"
brain brief
brain retro

# Rebuild index (safe; vault + graph.json are source of truth)
python3 ~/Developer/multibrain/bin/index_ladybug.py
launchctl kickstart -k gui/$(id -u)/com.multibrain.index-server

# Install / reload a job (Studio example)
cp ~/Developer/multibrain/ops/com.multibrain.retro.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.multibrain.retro.plist
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Red: `capture_fresh` | claude-mem worker stalled | `curl :37777/health`; `launchctl kickstart …claude-mem-worker`; `bin/claude-mem-ensure-worker.sh` |
| Red: Book nightly OpenRouter 402 | synthesis credits | top up OpenRouter or set `--no-llm` / another backend |
| Yellow: `ladybug_query` on Studio | index-server down | kickstart `com.multibrain.index-server`; rebuild `.lbug` |
| Yellow: `letta_api` on Studio | Letta native down | kickstart `com.multibrain.letta` (+ shim/bridge) |
| `n/a` ladybug/letta on Book | expected satellite | set `"role": "satellite"` or leave auto-detect |
| Graph uncolored | `graphify_nightly` false or merge skipped | enable flag; re-run `graphify_merge.py` |
| Notes in staging not vault | missing `vault_dir` / ingest failed | set `vault_dir`; run `ingest_staged.py` |
| Alert storm | fingerprint dedup broken | inspect `state.db.alerts` |
| Letta unreachable | hub service down | interactive `brain` fails; **nightly still runs** via `consolidate.py` |

## Recovery

- **Vault:** git revert in `~/Developer/SecondBrain`.
- **Bad `.lbug`:** delete and rebuild from vault / graphify outputs — index is cache.
- **Letta drift:** reseed agent / `rolling_state` in native Postgres (`:5442` Letta DB).

## Prereqs / known fixes

- graphify interpreter: `cat …/graphify-out/.graphify_python` — not system python.
- Multica / Letta Postgres: native **`:5442`** (not Docker `:5432`).
- claude-mem epochs are **milliseconds**.
- Never point graphify `--obsidian-dir` at the live vault — use scratch + `graphify_merge.py`.
- FAISS is intentionally unused.
