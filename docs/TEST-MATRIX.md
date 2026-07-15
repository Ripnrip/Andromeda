# Test Matrix & Health Monitoring — Multi-Brain Orchestration

Testing and self-monitoring are **first-class from Phase 1**, not bolted on. This doc is the checklist the suite must satisfy. Framework: `pytest`, no network (fixtures/mocks only). See [../tests/README.md](../tests/README.md) for layout.

## Unit tests (per component)

| Component | Asserts |
|-----------|---------|
| `extract_claudemem` | Correct day-window rows; `platform_source` join; NULL `agent_type` ignored; concepts/files parsed |
| `extract_hermes` | FTS5 day query; `.usage.json` → skill-attribution notes |
| `extract_multica` | pgvector rows mapped to digest (against fixture schema) |
| `extract_hermes_vm` | SSH command shape; unreachable → empty + `sources_status=unreachable` |
| `dedup_ledger` | Known hash skipped; new hash recorded; ledger idempotent |
| `note_schema` | Frontmatter valid; required fields; bare-tag form; section order |
| `graph_merge` | colorGroups written; **non-color settings preserved** (centerStrength/repel/etc.) |
| `ladybug_index` | Nodes+vectors loaded; a query returns expected neighbor |
| `letta_tools` | Each tool's I/O contract (mock Letta runtime) |
| `alert` | Correct Telegram/email payload on a failure object; dedup by fingerprint |

## Permutation tests (explicit — the tricky logic)

| Permutation | Expected behavior |
|-------------|-------------------|
| Empty day (no observations) | No notes written; run succeeds; brief says "quiet day" |
| Single source only | Only that agent's notes; others absent, not errored |
| Multi-source, same project | Separate `--<agent>.md` notes; daily digest lists all |
| Duplicate content (same hash) | Skipped by ledger; no duplicate note |
| Re-run same day | Idempotent — append-merge, zero new dupes |
| Existing target note | Append-merge new bullets, preserve old |
| Malformed / NULL rows | Row skipped with a warning; run continues |
| Schema drift (renamed column) | `PRAGMA` guard degrades gracefully, alerts, does not crash |
| Source unreachable (VM/Tailscale) | Skipped; `sources_status` flags it; no crash |
| Multica container down | Skipped; health = yellow; alert |
| Letta down (Phase 2+) | Fall back to deterministic `consolidate.py`; alert |
| Obsidian file locked | Retry via wiki-lock; then defer |
| Half-written note + git auto-commit race | flock prevents mid-write commit |

## Integration tests (full pipeline)

Over a throwaway vault copy + fixture stores, assert:
1. Correct `07-Sessions/*--claude.md` + `*--codex.md` written.
2. `02-Daily/<today>.md` has an `## Agent Learnings` block; backlinks resolve.
3. `.obsidian/graph.json` parses; `colorGroups` non-empty; non-color settings intact.
4. `multibrain.lbug` answers a vector+graph query.
5. `git log` shows exactly one nightly commit.
6. Re-run is idempotent (no new files, no dupes).

## Health monitor (`healthcheck.py`) — invariants

Runs after every nightly job **and hourly**. Writes `health.json` (see DATA-CONTRACTS §9) + a `## Health` line into the Daily Brief.

- **Freshness:** claude-mem has obs in last 24h; each source reachable.
- **Output:** notes written for active projects; graph colored; `multibrain.lbug` queryable; Letta API responsive; git clean & committed; embeddings advanced.
- **Anomaly (vs 7-day baseline in `state.db`):** note count didn't collapse to 0; obs count not anomalously low; dedup ratio sane; log error-rate not climbing.
- **Dead-man's-switch:** if `last-success` is older than the schedule window, the run silently failed → alert.

## Alerting (`alert.py`) — loud on ANY failure

- **Channels:** Telegram (`~/hermes-telegram-bot`, primary), email (SMTP — confirm creds), optional Hermes APNs (`~/hermes-apns-relay`).
- **Content:** which check failed, its detail, `last-good` timestamp, and the run log tail.
- **Dedup:** alert on **state change** (green→red) + a daily reminder while unresolved; never hourly spam of the same failure. State tracked in `state.db.alerts` by fingerprint.
- **Self-test:** `alert.py --selftest` sends a test message so the channel itself is verified; the alerting path must not be able to fail silently.

## CI

Local git pre-commit hook runs `pytest -q`. Green required to commit. No network in tests.
