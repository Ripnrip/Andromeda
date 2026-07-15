# Data Contracts — Multi-Brain Orchestration

Every schema, boundary, and shape the components agree on. If two pieces disagree, this doc wins. All shapes are **provisional against verified sources**; confirm live columns before coding (extractors carry `PRAGMA table_info` guards).

## 1. Source: claude-mem (`~/.claude-mem/claude-mem.db`, SQLite)

Verified columns (2026-07-01). Attribution rides on `sdk_sessions`, **not** `observations.agent_type` (which is NULL).

```
observations(
  type,            -- bugfix|feature|refactor|discovery|decision|change
  title, subtitle, narrative,
  concepts,        -- e.g. how-it-works|gotcha|pattern|trade-off (delimited)
  files_modified,
  project,
  content_hash,    -- dedup key
  memory_session_id,
  created_at_epoch,
  agent_type,      -- NULL (do not use)
  agent_id         -- NULL (do not use)
)
session_summaries(
  request, investigated, learned, completed, next_steps,
  project, memory_session_id, created_at_epoch
)
sdk_sessions(
  memory_session_id, project,
  platform_source,  -- 'claude' | 'codex'  ← attribution source
  started_at_epoch
)
```

**Day window query (canonical):**
```sql
SELECT o.type, o.title, o.subtitle, o.narrative, o.concepts,
       o.files_modified, o.project, o.content_hash, o.memory_session_id,
       COALESCE(s.platform_source,'claude') AS agent
FROM observations o
LEFT JOIN sdk_sessions s USING (memory_session_id)
-- NOTE (Wave-1 fix): created_at_epoch is in MILLISECONDS → multiply boundaries by 1000; keep UTC (no localtime).
WHERE o.created_at_epoch >= strftime('%s','now','start of day','-1 day') * 1000
  AND o.created_at_epoch <  strftime('%s','now','start of day')          * 1000
ORDER BY o.project, agent, o.created_at_epoch;
```

## 2. Source: local Hermes (`~/.hermes/state.db`, SQLite FTS5)

- `messages_fts` / `messages_fts_trigram` — full-text over messages; query the day's rows.
- `~/.hermes/skills/.usage.json` — per-skill `use_count`/`view_count`/`patch_count` + timestamps → maps to `insight/pattern` notes (skill attribution).
- `~/.hermes/memories/MEMORY.md` — freeform note store (secondary).

## 3. Source: Multica (native Postgres, `127.0.0.1:5442`)

Creds from Multica `.env` (`POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB=multica`). **As-built:** native stack on Studio (not Docker `:5432`). Extractor: `bin/extract_multica.py` (agent task queue / learnings). Tag `agent: multica`.

## 4. Source: habitat-VM Hermes (SSH)

`ssh habitat "sqlite3 ~/.hermes/state.db '<query>'"` — read-only over Tailscale. Tag `agent: hermes-vm`. **Must degrade gracefully** if the VM is unreachable at run time.

## 5. Digest (extractor output → Letta `read_sources` / `consolidate.py` input)

```json
{
  "date": "2026-07-01",
  "generated_at": "2026-07-02T02:30:11Z",
  "groups": [
    {
      "project": "Portfolio",
      "agent": "claude-code",
      "platform_source": "claude",
      "sessions": ["<memory_session_id>", "..."],
      "observations": [
        {"type": "discovery", "title": "...", "narrative": "...",
         "concepts": ["gotcha"], "files": ["path"], "content_hash": "sha256:..."}
      ],
      "summaries": [
        {"request": "...", "learned": "...", "next_steps": "...", "session": "<id>"}
      ]
    }
  ],
  "sources_status": {"claude-mem": "ok", "hermes": "ok", "multica": "ok", "hermes-vm": "unreachable"}
}
```
`sources_status` is mandatory — the health check and Daily Brief read it.

## 6. Deposit: session-learning note (`07-Sessions/YYYY-MM-DD--<project>--<agent>.md`)

```yaml
---
type: session-learning
created: 2026-07-01
date: 2026-07-01
agent: claude-code            # claude-code | codex | hermes | hermes-vm | multica
agent_session: <memory_session_id>
platform_source: claude
project: <name>
observation_types: [discovery, feature, bugfix]
concepts: [gotcha, pattern]
source: claude-mem
community: null                # graphify fills on --update
tags: [session/claude-code, project/<name>, insight/discovery, community/<label>]
confidence: synthesized        # synthesized | verbatim
---
```
Body sections (fixed order): `## Key Insights` (each `[[wikilink]]`), `## What Changed`, `## Problem → Solution`, `## Files Touched`, `## Connections`, then an attribution footer.

**Tags use bare frontmatter form** (no `#`) to match Obsidian-native behavior and the newest real note; axes: `session/<agent>`, `project/<name>`, `insight/<obs-type>`, `concept/<concept>`, `community/<label>`.

## 7. Deposit: daily digest block (appended to `02-Daily/YYYY-MM-DD.md`)

```markdown
## Agent Learnings
- **Portfolio** (claude-code): [[2026-07-01--Portfolio--claude]] — 3 insights
- **multibrain** (codex): [[2026-07-01--multibrain--codex]] — 5 insights
```
Append-only; never rewrites the human-authored parts of the daily note.

## 8. Digest outputs

- **Daily Brief** `06-Journal/YYYY-MM-DD Brief.md` (`type: daily-brief`): `## Yesterday`, `## Insights Ahead`, `## Health`.
- **Weekly Retro** `06-Journal/YYYY-Www Retro.md` (`type: weekly-retro`): `## Themes`, `## Key Learnings`, `## Surprising Connections`, `## Contradictions`, `## Progress`.

## 9. `~/.multibrain/health.json` (health monitor output; UI + alert input)

`ok` may be `true` | `false` | `null`. When `status: "n/a"`, the check is intentionally skipped (Phase-1 satellite or feature gated) and does **not** contribute red.

```json
{
  "status": "green",
  "checked_at": "2026-07-14T06:00:00Z",
  "last_success": "2026-07-14T02:34:10Z",
  "checks": {
    "capture_fresh":   {"ok": true,  "detail": "412 obs in last 24h"},
    "sources":         {"ok": true,  "detail": "claude-mem reachable"},
    "notes_written":   {"ok": true,  "detail": "6 notes stamped 2026-07-14"},
    "graph_colored":   {"ok": true,  "detail": "20 colorGroups in graph.json"},
    "ladybug_query":   {"ok": true,  "detail": "HTTP 200 from http://127.0.0.1:8286/health"},
    "letta_api":       {"ok": true,  "detail": "HTTP 200 from http://127.0.0.1:8283/v1/health"},
    "git_committed":   {"ok": true,  "detail": "vault clean & committed"},
    "anomaly":         {"ok": true,  "detail": "counts within 7d baseline"},
    "dead_man":        {"ok": true,  "detail": "last success 3h ago"}
  },
  "baselines": {"notes_7d_avg": 5.4, "obs_7d_avg": 380}
}
```

Satellite example (Book): `ladybug_query` / `letta_api` → `{"ok": null, "status": "n/a", "detail": "n/a (satellite — no … hub)"}`.

## 10. Letta tool signatures (custom tools)

```
read_sources(date: str) -> Digest            # §5
write_vault_note(note: SessionNote) -> path   # §6/§7, via claude-obsidian transport
graphify_update() -> {colorGroups: int, communities: int}
index_ladybug() -> {nodes: int, vectors: int}
query_graph(q: str) -> [GraphHit]             # graphify MCP
vector_search(q: str, k: int) -> [Hit]        # LadybugDB HNSW
generate_daily_brief(date: str) -> path       # §8
generate_weekly_retro(week: str) -> path      # §8
```

## 11. Dedup ledger (`~/.multibrain/state.db`)

```
consolidated(content_hash TEXT PRIMARY KEY, date TEXT, note_path TEXT, first_seen_epoch INT)
baselines(metric TEXT, value REAL, updated_epoch INT)
alerts(fingerprint TEXT, state TEXT, first_epoch INT, last_epoch INT)   -- alert dedup
```

## 12. Anima Hot Capture Store (SwiftData / Realm)

The local hot storage of record for episodic capture before it is consolidated or projected downstream. Fully ACID-compliant, transactional, designed for sub-ms execution directly on threads.

### SwiftData Schema

```swift
@Model
final class AnimaEpisodicRecord: Sendable {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var contentHash: String // Primary join key derived from narrative
    var createdAt: Date
    var project: String
    var agent: String
    var narrative: String
    var visibility: String // public | friends | private | internal
    var provenance: String // source metadata
    var tags: [String]
    var materializedPath: String? // Nullable, populated on projection to Obsidian

    init(id: UUID = UUID(), contentHash: String, createdAt: Date = Date(), project: String, agent: String, narrative: String, visibility: String = "private", provenance: String, tags: [String] = [], materializedPath: String? = nil) {
        self.id = id
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.project = project
        self.agent = agent
        self.narrative = narrative
        self.visibility = visibility
        self.provenance = provenance
        self.tags = tags
        self.materializedPath = materializedPath
    }
}
```

- **Execution Constraint:** `store_memory` MUST execute its transaction and seal (Merkle proof) against this hot store and return immediately. It MUST NOT block on materialization (Obsidian write) or vector index updates (Qdrant/Ladybug).

## 13. Index Upsert Contract (Qdrant & LadybugDB)

Qdrant and LadybugDB are derived, rebuildable caches, NOT databases of record. All upserts are best-effort, async-at-materialization, and idempotent.

### Idempotency Key
To avoid duplicate vectors, the vector point ID MUST be a deterministic UUID derived from the record's `content_hash` (e.g. truncated SHA-256 mapped to UUID format, or UUIDv5 using a custom namespace).

### Thin Payload Schema
Do not store heavy raw text bodies inside vector indexes. Store only the metadata required for filtering and the join pointer back to the source of truth.

```json
{
  "point_id": "deterministic-uuid-from-content-hash",
  "vector": [0.15, -0.22, 0.94, "... 384 dimensions"],
  "payload": {
    "content_hash": "sha256:...",
    "visibility": "public | friends | private | internal",
    "project": "multibrain",
    "date": "2026-07-14",
    "tags": ["insight/discovery", "gotcha"],
    "source_path": "07-Sessions/2026-07-14--multibrain--codex.md"
  }
}
```

### Constraints
1. **Async-at-Materialization:** Index upsert is triggered by the Dream/consolidation loop, never by the hot capture `store_memory` callsite.
2. **Fail-Open:** Index down/timed out MUST NOT throw or halt. The failure is logged, and the index is flagged as "stale" or "dirty" for a background repair/rebuild later.
3. **Visibility Gate:** If `visibility` is `private` or `internal`, the point payload MUST carry `visibility` accordingly, and any export/sharing script must explicitly filter these points out.

