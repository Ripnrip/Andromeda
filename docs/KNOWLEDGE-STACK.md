# Knowledge Stack — Checkpoint, Sync, Close, Agents

How session learnings move from a chat into durable memory. This is the **human/agent ritual** layer; the nightly pipeline ([ARCHITECTURE.md](ARCHITECTURE.md)) is the batch curator that consumes staged notes + capture DBs.

Canonical note format: [DATA-CONTRACTS.md](DATA-CONTRACTS.md) §6. Skills live under `~/.claude/skills/` (and Cursor mirrors).

## Ritual flow

```
/checkpoint <topic>     →  author one 07-Sessions note (stage)
        ↓
/knowledge-sync [path]  →  distribute to live destinations
        ↓
/close <topic>          →  checkpoint + sync (+ optional twinkie / recap / graphify)
```

| Skill | Job |
|-------|-----|
| `/checkpoint` | **Author** the record (one structured, dated note) |
| `/knowledge-sync` | **Distribute** that record to every live destination |
| `/close` | Orchestrate checkpoint → sync, then optional bows |
| `/knowledge-agent` | **Query** a filtered claude-mem corpus (not a write path) |
| Vercel `knowledge-update` | Platform fact overrides for Vercel docs — **not** part of this fabric |

## Destinations (`/knowledge-sync`)

| Destination | Path / surface | Status | Action |
|-------------|----------------|--------|--------|
| **memory.md** | `~/.claude/projects/-Users-admin/memory/` | live | write fact file + `MEMORY.md` pointer |
| **claude-mem** | `~/.claude-mem/` | live | verify observer capture; Kimi via `bin/kimi-to-claudemem.py` |
| **graphify / MCP memory** | MCP `user-memory` | live | `create_entities` / `create_relations` (merge, don’t duplicate) |
| **multibrain stage** | `~/Developer/multibrain/07-Sessions/` | live stage | checkpoint already here; nightly `ingest_staged.py` → SecondBrain |
| **qdrant** | `127.0.0.1:6333` collection `secondbrain_learnings` | live | `bin/qdrant-upsert.py` / MCP record — **384-dim local embeddings** |

**LadybugDB is not a knowledge-sync destination.** It is rebuilt from the vault/graph by the nightly hub pipeline.

## `/knowledge-agent` (claude-mem corpora)

Build a filtered observation corpus → prime an AI session → ask questions:

1. `build_corpus` (project / types / concepts / dates / limit)
2. `prime_corpus`
3. `query_corpus`
4. `rebuild_corpus` / `reprime_corpus` when observations drift

Use for “everything about hooks”, “decisions last month”, etc. Does **not** replace `/checkpoint`.

## `/close` optional bows

After sync (unless `--fast`):

- **twinkie** — hipster `Changelog.md` entry (explicit yes / keyword required)
- **remotion-recap** — narrated reel
- **graphify** — only when a real path is supplied
- **delegate** — Manus / Claude Desktop demo hand-off prompt

Never auto-commits. Changelog default is **no**.

## Rules of the road

1. One learning per file; specific (commands, `file:line`).
2. Idempotent — `rg` before writing; merge, don’t duplicate.
3. Honest about gaps — if claude-mem didn’t capture, say so.
4. Never rewrite a prior checkpoint’s body — add a follow-up and link it.
5. Qdrant ≠ LadybugDB; memory.md ≠ vault notes.

## Related ops scripts (repo `bin/`)

- `ingest_staged.py` — stage → SecondBrain
- `kimi-to-claudemem.py` — Kimi SessionEnd bridge
- `qdrant-upsert.py` — knowledge-sync vector write
- `write_vault_note.py` — vault helper used by bridge / consolidate paths
