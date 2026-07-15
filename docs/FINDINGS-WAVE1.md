# Wave 1 — Recon & Prereq Findings (2026-07-05)

> **Historical.** Still useful for graphify clobber rules, LadybugDB package notes, and claude-mem epoch-ms. **Superseded for deploy topology** by native Letta (`:8283`), Multica/Postgres `:5442`, and [FLEET.md](FLEET.md) / [ARCHITECTURE.md](ARCHITECTURE.md). Docker + `multica_default` Letta path is retired.

Five parallel agents verified the risky assumptions before the build. Wave 2 must build on these.

## SA1 — graphify CLOBBERS `.obsidian/graph.json` ⚠️
Verified in source (`graphify/export.py:675-687`) + live test on a vault copy: `to_obsidian()` writes `{"colorGroups": [...]}` and **overwrites the whole file** — wiping physics keys (your real vault has `centerStrength=0.5187`, `repelStrength=10`, `linkDistance=250`).
**BUILD RULE:** never point graphify's `--obsidian-dir` at the live `~/Developer/SecondBrain`. Point it at a **scratch vault**, then merge ONLY the `colorGroups` array into the real `graph.json`:
```python
original = json.loads(gj.read_text()) if gj.exists() else {}
# run graphify against a scratch dir → scratch_graph.json
original["colorGroups"] = json.loads(scratch_gj.read_text()).get("colorGroups", [])
gj.write_text(json.dumps(original, indent=2))
```

## SA2 — LadybugDB = `pip install ladybug==0.18.0` ✅
The graph DB **took over** the `ladybug` PyPI name (energy tool moved to `ladybug-tools`). Verified install + smoke test.
- **Python 3.12** (3.14 fails — no wheel). Ships prebuilt arm64 `.so`, no compiler.
- Import name `ladybug`; API = Kùzu surface (`Database`, `Connection`).
- `INSTALL vector; LOAD vector;` downloads the vector ext at runtime → **first vector call needs network**.
- HNSW: `CALL CREATE_VECTOR_INDEX('T','idx','col', metric:='cosine')`; query `CALL QUERY_VECTOR_INDEX('T','idx',$q,k) RETURN node.*, distance`. Params via dict as 2nd arg to `execute`.

## SA3 — Letta self-host on the existing pgvector ✅ (with a networking catch)
- Docker 27.5.1 up; `multica-postgres-1` healthy (pgvector/pg17, PG 17.10).
- **pgvector reuse works:** set `LETTA_PG_URI=postgresql://multica:<pw>@multica-postgres-1:5432/letta`; one-time `CREATE DATABASE letta; CREATE EXTENSION vector;`. No second Postgres.
- ⚠️ **`multica-postgres-1` has NO host port binding** — only on docker network `multica_default`. Letta's container must `networks: [multica_default (external)]` and dial `multica-postgres-1:5432` (NOT localhost).
- Port **8283** (REST + ADE); `SECURE=true` + `LETTA_SERVER_PASSWORD`.
- Custom tools = Python funcs w/ Google docstrings → `client.tools.create_from_function`; core-memory blocks persona/rolling_state/humans.
- Letta is an MCP **client** (bridges to graphify MCP via `PUT /v1/tools/mcp/servers`), not a server.
- Drafted `~/.multibrain/letta/{docker-compose.yml,.env.example,README.md}`.
- **Open:** needs an embedding provider key (OpenAI or equiv) for vector memory; Letta data lands in Multica's pgdata volume (backup implication); consider a dedicated `letta` role vs reusing `multica` superuser.

## SA4 — Multica learnings live in `agent_task_queue` ✅
Connect via `docker exec multica-postgres-1 psql -U multica -d multica` (no host port). Key tables:
- **`agent_task_queue`** (primary): `agent_id, runtime_id, issue_id, status(completed|failed|…), started_at, completed_at, result(jsonb), error, trigger_summary, handoff_note`.
- **`issue`** (`status='done'`, `updated_at`, `title`), **`agent`/`agent_runtime`** (names), **`comment`** (agent narrative notes), `activity_log`, `autopilot_run`, `project`/`workspace`.
- DB is a near-empty dev instance now — query is correct but returns few rows until real activity accrues.
- Day-window query drafted (agent_task_queue completed/failed last 24h + comment union). Tag `agent='multica'`.

## SA5 — capture is gated by `disableAllHooks`; timestamp bug found 🔴
- claude-mem worker is ALIVE (bun PID on :37777, `/health` ok, writing now). But observations **paused Jul 3–5** and resumed Jul 6.
- **Root cause:** `"disableAllHooks": true` in `~/.claude/settings.json:133` suppresses the plugin's capture hooks → worker alive but no `observation` events. **DECISION for the user** (toggling also affects OMC/GSD/herdr hooks — not changed unilaterally).
- `_capture-health.md` "dormant" is a STALE snapshot (brain-health.py last ran Jul 1).
- 🔴 **`created_at_epoch` is in MILLISECONDS** — the DATA-CONTRACTS §1 query (comparing to `strftime('%s')` seconds) was BROKEN (0 rows). **Fixed:** multiply boundaries by 1000, keep UTC (no `localtime`). Validated 75 rows for the Jul 1 window. `session_summaries.created_at_epoch` is also ms.
- All DATA-CONTRACTS §1 columns confirmed to exist; `platform_source` on `sdk_sessions` = claude|codex; join coverage partial → `COALESCE(...,'claude')` correct.
- ✅ **Fixed** the stale `claude-mem` alias in `~/.zshrc:24` (`/Users/gurindersingh` → `/Users/admin`).

## Net corrections applied to the spec
1. DATA-CONTRACTS §1 day-window query → `* 1000` on the epoch boundaries, UTC.
2. graphify → scratch-vault + colorGroups-merge (never write live `.obsidian`).
3. LadybugDB → `ladybug==0.18.0`, Python 3.12.
4. Multica/Letta → `docker exec` / docker-network `multica_default`, not host `:5432`.
5. Open decision: `disableAllHooks` (capture foundation).
