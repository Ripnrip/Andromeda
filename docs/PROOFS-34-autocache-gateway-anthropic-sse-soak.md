# PROOF 34 — Autocache Gateway Anthropic SSE Live Soak

**Date:** 2026-07-16 (re-soak) · prior: 2026-07-15  
**Repo:** `~/Developer/Andromeda` **@** `main` (Autocache landed via PR #1 `091aaec`)  
**Linear:** [BIN-42](https://linear.app/binary-bros/issue/BIN-42/live-anthropic-sse-soak-on-autocache-gateway)  
**Multica:** HAB-65  
**Operator:** Cursor agent · keys never printed or committed

## BEFORE (prior PROOFS-34)

| Layer | Result |
| --- | --- |
| Build + unit tests | PASS (14/14 on gateway branch) |
| Gateway boot + `/health` | PASS |
| Autocache ROI headers on upstream error | PASS |
| **Live Anthropic SSE (`text/event-stream`)** | **FAIL** — `401 authentication_error: invalid x-api-key` |

Citation: prior soak on `cursor/hummingbird-autocache-gateway-3c88` @ `19bf070` (worktree `/tmp/andromeda-gateway-soak`) documented that the Autocache gateway spine works but **SSE end-to-end was not proven** — no valid direct Anthropic Messages API key on Studio. Keys were already flagged for human rotation (BIN-43 lane); agents must not invent keys.

## AFTER (2026-07-16 re-soak on `main`)

| Layer | Result | Notes |
| --- | --- | --- |
| Autocache on `main` | **PASS** | Merged PR #1 |
| `swift build` | **PASS** | Clean (~15s incremental) |
| Gateway boot + `/health` | **PASS** | `127.0.0.1:18080` · `status=healthy` · `surface=autocache` · `strategy=moderate` · `version=0.1.0-autocache` |
| Autocache headers on upstream 401 | **PASS** | Full `X-Autocache-*` set returned |
| **Live Anthropic SSE stream** | **FAIL** | Key blocker — see below |

**Overall live soak:** **FAIL** (honest key blocker; gateway plumbing OK; no SSE events observed)

### Key probe (no secret values)

| Source | Present? | Usable as Anthropic Messages `x-api-key`? |
| --- | --- | --- |
| Shell `ANTHROPIC_API_KEY` | absent | — |
| `~/Developer/Andromeda/.env` | missing | — |
| `~/Developer/multibrain/.env` | no key line | — |
| `~/.multibrain/letta/.env` | line present (len=49, not `sk-ant-*`) | **invalid** → 401 |
| `~/.multibrain/letta/letta-native.env` | commented out | — |
| `~/.claude/settings-openrouter.json` `ANTHROPIC_API_KEY` | empty | — |
| same file `ANTHROPIC_AUTH_TOKEN` | present (`sk-or-*`, OpenRouter) | **not** direct Anthropic; base URL is `openrouter.ai` — out of scope for this soak |
| `~/.claude/.credentials.json` OAuth | present | **not** Messages API key (prior 401) |
| macOS Keychain `anthropic` / `op` CLI | absent | — |

**Conclusion:** Only stale/wrong-shape credentials exist. Operator keys remain **PINNED for rotation** — soak cannot PASS until a current Console `sk-ant-…` is provisioned into the serve environment (env-only, never commit).

### Soak procedure executed

```bash
cd ~/Developer/Andromeda   # main @ post-PR#1
swift build
# ANTHROPIC_API_KEY loaded silently from ~/.multibrain/letta/.env (value never logged)
HOST=127.0.0.1 PORT=18080 CACHE_STRATEGY=moderate \
  swift run andromeda serve --port 18080

curl -sf http://127.0.0.1:18080/health
# → healthy / autocache / moderate

curl -sS -N -X POST http://127.0.0.1:18080/v1/messages \
  -H 'Content-Type: application/json' \
  -H 'anthropic-version: 2023-06-01' \
  -d '{"model":"claude-3-5-haiku-20241022","max_tokens":16,"stream":true,
       "messages":[{"role":"user","content":"Say hi in one word."}]}'
```

### Observed evidence (redacted)

- HTTP `401 Unauthorized`
- `Content-Type: application/json` (not `text/event-stream`)
- Body: `{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"},"request_id":"req_011Cd6xc4fqedkDoTYmojF3m"}`
- Autocache headers present (`X-Autocache-Injected: false`, strategy/model/ROI fields populated)
- **No** `event:` / `message_start` / `content_block_delta` SSE lines
- Gateway process stopped after soak; port `18080` cleared

### Latency / error budget (attempted)

| Metric | Value |
| --- | --- |
| Health ready | ~14s after `swift run` |
| Messages round-trip | curl exit 0; upstream auth reject before stream open |
| SSE event budget | **0 events** (blocked) |
| Error class | Anthropic `authentication_error` — expected until valid key |

## Unblock checklist (human)

1. Rotate / provision a **current** Anthropic Console API key (`sk-ant-api03-…`) into serve env only.
2. Re-run the curl above against a local `andromeda serve`.
3. Expect: HTTP `200`, `Content-Type: text/event-stream`, lines with `event:` + `data:` containing `message_start` / `content_block_delta`.
4. Flip this proof **PASS**, comment BIN-42 / HAB-65, close trackers.

## Security note

No API keys, tokens, or `.env` contents were written to this proof, git, chat, Linear, or Multica.
