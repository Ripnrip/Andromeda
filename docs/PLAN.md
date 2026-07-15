# Plan: Multi-Brain Orchestration

> **As-built banner (2026-07-14):** Phase 1–2 are **implemented** in this repo (`bin/`, `ops/`). Nightly conductor is **`consolidate.py`**, not a Letta API “consolidate yesterday” call. Letta runs **native** on Studio `:8283` (Postgres `:5442`), not Docker. Multica is native Postgres `:5442`. Book is a Phase-1 satellite. See [ARCHITECTURE.md](ARCHITECTURE.md), [FLEET.md](FLEET.md), [RUNBOOK.md](RUNBOOK.md). The body below is the original Jul-1 execution plan retained for history — treat “documentation-only / Codex owns impl” as **historical**.

## Context

The user wants every agent to deposit end-of-day learnings/insights into the `~/Developer/SecondBrain` Obsidian vault — hyper-optimized for colors/tags/connections/graph, backed by a vector store, Hermes-friendly for skill attribution — and orchestrated by a persistent **Librarian/Conductor agent** you can converse with. Exploration showed the *capture + knowledge* half is ~70% already built and unintegrated: `claude-mem 12.4.7` actively captures every Claude Code + Codex session (68 MB SQLite + Chroma, 670 obs/24h), `graphify` builds community-clustered graphs and writes Obsidian graph colors directly, `claude-obsidian 1.9.2` sits on a near-empty PARA/Zettelkasten vault (Dataview, Templater, Obsidian Git, smart-connections embeddings), and Hermes/Multica/pgvector run already.

**What's missing:** (1) a consolidation pipeline that funnels each agent's day into curated, graph-optimized vault notes; (2) **LadybugDB** as a unified graph+vector index; (3) **Letta** as the stateful conductor agent that reasons over it all, remembers, and answers. This is the piece nothing else fills — claude-mem/graphify/cron are all passive/batch; Letta is the persistent brain you talk to.

### Execution split (HISTORICAL — Jul 2026 docs phase)
**Codex was taking the initial implementation.** Claude’s early work was **documentation-only**. That split is complete: code now lives in-repo. Do not treat this paragraph as a current build freeze.

### Decisions locked (via user)
- **Name:** Multi-Brain Orchestration. Scaffold under `~/.multibrain/`.
- **Sources:** Claude Code + Codex (both in `claude-mem.db`), local Hermes (`~/.hermes/state.db`), Multica (pgvector `127.0.0.1:8090`/`5432`), habitat-VM Hermes (`ssh habitat`).
- **Vector/graph store:** **LadybugDB** as the unified multibrain archival/query surface. **Qdrant** is a separate `/knowledge-sync` destination (do not conflate).
- **Letta:** **Librarian** — interactive Q&A + bridge tools. **As-built:** nightly batch is `consolidate.py`, not Letta API.
- **Deposit:** new `07-Sessions/` atomic notes + a `## Agent Learnings` backlink digest in `02-Daily/YYYY-MM-DD.md`.
- **Schedule:** launchd `StartCalendarInterval` 02:30 + RunAtLoad catch-up guard (run if last success > 20h).
- **Out:** FAISS (redundant with pgvector/Chroma).

## Architecture

```
CAPTURE (already running)          CONDUCTOR (new: Letta agent)              SUBSTRATE
──────────────────────            ───────────────────────────               ─────────
claude-mem.db (claude,codex)─┐    ┌───────────────────────────┐
~/.hermes/state.db (FTS5)    ─┤    │  LETTA "Librarian"        │             ~/Developer/SecondBrain
Multica pgvector :5432       ─┼─▶  │  core memory = state      │──deposit──▶  07-Sessions/DATE--proj--agent.md
ssh habitat ~/.hermes/db     ─┘    │  archival  = LadybugDB    │             02-Daily/DATE.md ## Agent Learnings
        ▲ deterministic            │  tools:                   │             05-MOC/Sessions MOC.md (Dataview)
        │ extractors               │   • read_sources(digest)  │
        └──── feed digest ────────▶│   • write_vault_note()    │──graphify─▶  .obsidian/graph.json colorGroups
                                   │   • graphify_update()     │
   nightly 02:30 (launchd) ───────▶│   • index_ladybug()       │──index───▶   ~/.multibrain/multibrain.lbug
   or you: "what did we learn?" ──▶│   • query_graph()         │             (HNSW+graph, MCP query surface)
                                   └───────────────────────────┘──commit──▶   git (flock-guarded)
```

**Division of labor:** deterministic Python extractors do the fragile part (read each source's DB reliably) and hand Letta a structured **digest**; Letta does the agentic part (synthesize learnings, file notes, update its own memory, trigger graphify + LadybugDB index, answer queries). Extractors and graphify/LadybugDB are exposed to Letta **as tools**, so the same machinery serves both the nightly loop and interactive questions.

All new machinery under `~/.multibrain/` (`bin/`, `prompts/`, `staging/`, `logs/`, `state.db` dedup ledger, `multibrain.lbug`). Nothing pollutes `~/.claude-mem` or the vault.

## Letta — the Librarian/Conductor

- **Self-host (as-built):** native Letta (`run-letta-native.sh`), API `:8283`, bridge `:8284`, Postgres `:5442`. Docker + `multica_default` was Wave-1 only.
- **Nightly (as-built):** `run-nightly.sh` → `consolidate.py` (Letta does not own the batch loop).
- **Agent config:** persona = "Librarian of the Multi-Brain"; core-memory blocks = `persona`, `rolling_state` (current projects / open threads / recent themes), `humans`. Archival memory = the fabric (session notes + graph nodes embedded into LadybugDB/pgvector).
- **Tools (custom, registered on the Letta agent):**
  - `read_sources(date)` → calls the deterministic extractors, returns a per-project×agent digest JSON.
  - `write_vault_note(note)` → writes `07-Sessions/*.md` + daily digest via claude-obsidian transport (REST `127.0.0.1:27124` → filesystem floor).
  - `graphify_update()` → runs graphify `--update --obsidian-dir` over the vault.
  - `index_ladybug()` → loads `graph.json` + note embeddings into `multibrain.lbug`.
  - `query_graph(q)` / `vector_search(q)` → graphify MCP + LadybugDB HNSW for retrieval.
  - `generate_daily_brief(date)` / `generate_weekly_retro(week)` → the outbound digests (below).
- **Interfaces:** Letta REST API + a `brain` shell alias for chat ("what did we learn this week?"); register Letta (and the graphify/LadybugDB MCP servers) as **MCP servers** so Claude Code / other agents can call the conductor.
- **Nightly loop:** launchd triggers `run-nightly.sh` → one Letta API call ("consolidate <yesterday>") → Letta orchestrates read_sources → synthesize → write_vault_note → graphify_update → index_ladybug → updates its own `rolling_state` memory.

## Recurring Digests (outputs to the user)

The fabric reports back, not just ingests. Letta generates:
- **Daily Brief** — produced in the nightly loop (ready when you wake): "**Yesterday**" recap across all agents/projects + "**Insights Ahead**" (open `next_steps` from `session_summaries`, unresolved threads, suggested focus). Written to `06-Journal/YYYY-MM-DD Brief.md` (`type: daily-brief`).
- **Weekly Retrospective** — separate Monday job: themes of the week, key learnings, cross-project connections + **surprising_connections/god_nodes/cohesion from graphify**, contradictions flagged, progress vs open threads. Written to `06-Journal/YYYY-Www Retro.md` (`type: weekly-retro`).

**Delivery (decision):** default = vault note + a terminal readout via the `brain` alias (e.g. `brain brief` / `brain retro`). Opt-in extra channels available given existing infra — **Hermes APNs push** (`~/hermes-apns-relay`) or the **Telegram bot** — surface the brief each morning. Confirm channel at build time.

## Vault Schema (session-learning notes)

New folder **`07-Sessions/`**; filename `YYYY-MM-DD--<project>--<agent>.md`. Frontmatter:

```yaml
---
type: session-learning
created: 2026-07-01
date: 2026-07-01
agent: claude-code          # claude-code | codex | hermes | hermes-vm | multica
agent_session: <id>         # audit trail back to source
platform_source: claude
project: <name>
observation_types: [discovery, feature, bugfix]
concepts: [gotcha, pattern]
source: claude-mem
community: null             # graphify fills on --update
tags: [session/claude-code, project/<name>, insight/discovery, community/<label>]
confidence: synthesized
---
```

Body: `## Key Insights` (each a `[[wikilink]]`), `## What Changed`, `## Problem → Solution`, `## Files Touched`, `## Connections`, attribution footer. Daily note gets a lightweight backlinked `## Agent Learnings` block (keeps the human daily note clean).

**Tags** (nested `#cat/sub`, honoring vault `CLAUDE.md`; reconcile the existing `#`-prefix-vs-bare drift to **bare** frontmatter tags): `session/<agent>`, `project/<name>`, `insight/<obs-type>`, `concept/<concept>`, `community/<graphify-label>`. **Index:** one Dataview MOC `05-Maps of Content/Sessions MOC.md`.

## Deterministic Extractors (Letta's `read_sources` backend)

`~/.multibrain/bin/extract_*.py` (stdlib `sqlite3` + `psycopg` + `subprocess`):
- **claude-mem (claude+codex):** `observations` LEFT JOIN `sdk_sessions USING(memory_session_id)` for `platform_source` (attribution — `agent_type` is NULL, don't use) + `session_summaries`. `PRAGMA table_info` guard for upgrade resilience.
- **Local Hermes:** `~/.hermes/state.db` FTS5 `messages_fts` for the day + `~/.hermes/skills/.usage.json` skill attribution (`insight/pattern`).
- **Multica:** pgvector `127.0.0.1:5432` (creds from `~/Developer/multica/.env`); day's completed tasks / agent-runtime activity. *Schema inspection is a Phase-2 prereq.*
- **VM Hermes:** `ssh habitat "sqlite3 ~/.hermes/state.db ..."` read-only; degrade gracefully if unreachable.

**Dedup (3 layers):** `content_hash` ledger in `~/.multibrain/state.db`; note-level append-merge; optional semantic (later).

## graphify + LadybugDB

- **graphify:** resolve interpreter via `PY=$(cat ~/Developer/SecondBrain/graphify-out/.graphify_python)` (not importable from system python). Run `--update --obsidian --obsidian-dir ~/Developer/SecondBrain` over `07-Sessions/` + `01-Permanent/`. graphify's `to_obsidian()` **sets `.obsidian/graph.json colorGroups` itself**, writes `_COMMUNITY_<label>.md` MOCs + `graph.canvas`. Post-step copies each node's community into note `community:` frontmatter + tag.
- **LadybugDB:** nightly load `graph.json` nodes/edges + note embeddings into `~/.multibrain/multibrain.lbug` (HNSW + graph, one file) = Letta's archival + agent query surface via MCP. **Verify install method in Phase 0** — LadybugDB is the Kùzu successor; PyPI `ladybug` is unrelated (building-energy), so confirm the correct package/repo.

## Testing & Health Monitoring (first-class)

Given the many moving pieces, testing and self-monitoring are built in from Phase 1, not bolted on.

**Test suite (pytest, in the repo `tests/`):** TDD — write the failing test before each component.
- **Unit** — each extractor against fixture DBs (`tests/fixtures/*.db`): claude-mem reader, Hermes FTS5 reader, Multica pgvector reader, VM Hermes reader; the dedup ledger; the synthesis output-schema validator; the graphify colorGroups merge shim; the LadybugDB load/query; each Letta tool.
- **Permutations (explicit):** empty day (no observations), single source only, multi-source overlap, duplicate content (dedup must skip), append-merge into an existing note, malformed/NULL rows, schema-drift (renamed column → graceful degrade), source unreachable (VM/Tailscale down, Multica container down, Letta down), Obsidian-locked file, half-written note + commit race.
- **Integration** — full nightly pipeline over a throwaway vault copy + fixture stores → assert: correct `07-Sessions/*.md` written, daily digest block present + backlinks resolve, `graph.json` valid & `colorGroups` non-empty & non-color settings preserved, `multibrain.lbug` answers a query, git commit made, re-run is idempotent (no dupes).
- CI: run `pytest` on commit (local git hook) — no network deps in tests (all fixtures/mocks).

**Health monitor (`~/.multibrain/bin/healthcheck.py`, runs after every nightly job + hourly):** asserts invariants and compares to rolling baselines in `~/.multibrain/state.db`:
- Capture fresh (claude-mem obs in last 24h; each source reachable); notes written for active projects; `graph.json` parses & `colorGroups` non-empty; LadybugDB queryable; Letta API responsive; git clean & committed; embeddings advanced; **anomaly checks** (note count didn't collapse to 0, obs count not anomalously low vs 7-day baseline, dedup ratio sane, no growing error rate in logs).
- Writes `~/.multibrain/health.json` (status + per-check detail + last-good timestamps) and a `## Health` line into the Daily Brief.

**Loud alerting (`~/.multibrain/bin/alert.py`) — on ANY health failure or nightly-job crash:**
- **Telegram** (existing bot `~/hermes-telegram-bot`) — loud, with the failing check + last-good time.
- **Email** — via a simple SMTP sender (channel/creds to confirm at build).
- **Optional Hermes APNs push** (`~/hermes-apns-relay`).
- Deduplicate alerts (don't spam the same failure hourly — alert on state-change + a daily reminder while unresolved).

## UI Surface — Menu-bar / Pet (SwiftUI, macOS)

A visually prominent, always-there companion over the fabric — the whole point being you *don't* have to go hunting through graphs/DBs. It's a **thin client over artifacts the pipeline already produces**, so it adds no new backend: reads `~/.multibrain/health.json` (file-watch), today's Daily Brief note, `graphify-out/graph.html`, and talks to the **Letta API** for chat + the **graphify/LadybugDB MCP** for queries.

- **States (dynamic/responsive):** idle (green), working/consolidating (animated "thinking"), degraded (red + alert reason), new-brief-available (badge). Driven by `health.json` + Letta status + a `last-success` marker.
- **Popover / window contents:** health summary; today's brief ("Yesterday" + "Insights Ahead"); quick actions (open graph.html, open Obsidian vault, **chat with the Librarian/Letta**, "consolidate now", "run healthcheck"); recent-learnings feed; links to each source dashboard (Hermes, Multica, AZ).
- **Form factor (LOCKED = both):** a **CommandCenter module** (deep utility panel, reuses the existing menu-bar app + InfraModule pattern) **+** a **standalone floating Pet** (`MenuBarExtra` + always-on-top animated companion, ambient status/delight). Both are thin clients over one shared `MultiBrainClient` (reads `health.json`, Daily Brief, Letta API, MCP). Swift 6 / SwiftUI, macOS. Sequence: CC module first (utility), Pet second (delight).

## launchd

Three launchd jobs (the machine's first `StartCalendarInterval` jobs; all others RunAtLoad; model on `~/Library/LaunchAgents/com.multica.local.plist`; explicit `PATH`+`HOME`; logs → `~/.multibrain/logs/`):
- `com.multibrain.nightly.plist` — **02:30**: consolidate yesterday + generate the Daily Brief (ready by morning).
- `com.multibrain.retro.plist` — **Monday 08:00** (`Weekday 1`): weekly retrospective.
- `com.multibrain.health.plist` — **hourly** (`StartInterval 3600`): `healthcheck.py` → alert on degradation.
- (optional) a morning delivery hook (~07:30) that pushes the already-written brief via the chosen channel.

**Catch-up:** `run-nightly.sh` checks a `last-success` marker and runs if > 20h stale (survives sleep, no forced wake). Job = flock → call Letta consolidate+brief → wait → verify → done.

## Prerequisite Fixes (Phase 0)

1. **[HIGH] Verify graphify colorGroups merge** — on a vault *copy*, confirm `to_obsidian` merges into (not clobbers) `.obsidian/graph.json`; add a merge shim if needed. Highest-risk integration point.
2. **Verify LadybugDB install method** before wiring `index_ladybug`.
3. **Letta self-host smoke test** — Docker up, pointed at pgvector `letta` DB, agent + custom tool round-trip works.
4. **claude-mem stale alias** — fix `/Users/gurindersingh` → `/Users/admin` in `~/.zshrc.d`. Non-blocking.
5. **Hermes Curator pydantic** — pin `2.41.5` in Hermes's own venv (Phase 2, when local Hermes is a source).
6. **`disableAllHooks: true`** — leave; claude-mem still captures via its plugin. Revisit only if brain-sync markdown is wanted.

## Phased Rollout

- **Phase 0.0 — Repository bootstrap (do FIRST):** create a new project repo at `~/Developer/multibrain`; `git init`; save THIS plan as `docs/PLAN.md` (+ `README.md` overview); create `Changelog.md` (reverse-chronological journal), `TODO.md`, `Features.md`, `Roadmap.md`, `.gitignore` (ignore `*.lbug`, `staging/`, `logs/`, `.env`, secrets); initial commit. The `~/.multibrain/` runtime dir (data/logs/db) stays separate from this code repo. Decide GitHub remote (private) — offer, don't push until told.
- **Phase 0 (½ day):** the 6 prereq verifications above; inspect Multica Postgres schema.
- **Phase 1 — Deterministic MVP (Claude Code + Codex), no Letta yet — TDD:** `~/.multibrain/` scaffold, `extract_claudemem.py`, a plain `consolidate.py` that synthesizes via `claude -p` headless → `07-Sessions/` + daily digest + `Sessions MOC.md`, launchd @ 02:30, graphify `--update` → colored graph. **Ship with `pytest` unit+integration tests + `healthcheck.py` + `alert.py` (Telegram) from day one.** Proves the deposit+graph+test+alert loop end-to-end. Both agents free (already captured).
- **Phase 2 — Anima Swift MemoryKit, SwiftData, iCloud, Letta Conductor & Caches:**
  Create `MemoryKit` (local Swift Package in `~/Developer/multibrain-bar/Packages/MemoryKit` so the floating command bar can depend on it directly). Build using modern Swift (Swift 6.2+ strict concurrency, structured concurrency, `@Observable`). Set up **SwiftData / Realm** as the local hot episodic capture store (durable write-ahead journal). Add automatic one-way **iCloud / CloudKit** cold replication for multi-device sync and disaster recovery. Materialize recordings into the Obsidian vault asynchronously via a background dream/consolidation loop. Expose the capture surface via `store_memory` (returns immediately after write + seal) and retrieval via `recall_memory` (search hot store -> search Obsidian via ripgrep). Integrate rebuildable index caches (Qdrant & LadybugDB) async-at-materialization, with deterministic `content_hash` point IDs, thin metadata payloads, and fail-open resilience. Stand up Letta native as the conversational Librarian agent.
- **Phase 3 — retro + delivery + polish:** **Weekly Retrospective** job (graphify god-nodes/surprising-connections/cohesion); wire the chosen delivery channel (terminal `brain` / Hermes push / Telegram); semantic dedup; claude-obsidian REST transport for live-vault dedup; tune colorGroups/tags; Letta proactive surfacing (contradictions, frontier topics).
- **Phase 4 — Anima Command Bar & Floating Pet UI:**
  Integrate `MemoryKit` into `multibrain-bar` (the existing floating macOS command surface). Develop CommandCenter menu-bar utility module (Phase 4a) and a standalone animated, state-reactive floating Pet (Phase 4b). Deliver state visualization (health, synchronizing indicators, current visibility filter badge, active dream cycles). Isolate all view-facing models on `@MainActor` with `@Observable`. Ensure UI complies with Dynamic Type, Dark/Light modes, VoiceOver, and Apple HIG guidelines.


## Verification

- **Every phase:** `pytest` green (unit+integration+permutations); a *synthetic* health failure (e.g. stub an unreachable source) fires a real Telegram alert; recovery clears it.
- **Phase 0:** graphify on vault-copy preserves non-color graph settings; LadybugDB imports; Letta agent tool round-trips.
- **Phase 1 (next morning):** `07-Sessions/` has `*--claude.md` + `*--codex.md`; `02-Daily/<today>.md` has a working `## Agent Learnings` block; Obsidian graph is community-colored (`colorGroups` non-empty); nightly `git` commit present. Manual dry-run: `~/.multibrain/bin/run-nightly.sh`, inspect `logs/nightly.log`.
- **Phase 2:** ask Letta "what did we learn this week?" and get a grounded answer citing session notes; notes tagged `session/hermes|multica|hermes-vm` appear; `multibrain.lbug` answers a vector+graph query via MCP; re-runs don't duplicate.

## Critical Files (new unless noted)
- `~/.multibrain/bin/extract_*.py` — per-source deterministic readers (Letta's `read_sources`)
- `~/.multibrain/bin/consolidate.py` — Phase-1 synthesizer (later becomes a Letta tool)
- `~/.multibrain/bin/run-nightly.sh` — flock orchestrator + catch-up guard (calls Letta in Phase 2)
- `~/.multibrain/bin/healthcheck.py` + `alert.py` — self-monitoring + loud Telegram/email/APNs alerts
- `~/Developer/multibrain/tests/` — pytest unit + integration + permutation suite (fixtures, no network)
- `~/.multibrain/letta/` — Letta agent config, custom tool defs, docker-compose (pgvector-backed)
- `~/Library/LaunchAgents/com.multibrain.{nightly,retro,health}.plist` — scheduled jobs (model on `com.multica.local.plist`)
- `~/Developer/SecondBrain/05-Maps of Content/Sessions MOC.md` — Dataview index
- `~/Developer/SecondBrain/.obsidian/graph.json` (existing) — graphify colorGroups target
- `~/Developer/SecondBrain/CLAUDE.md` (existing) — tag/wikilink conventions to honor
- `~/.claude/skills/graphify/SKILL.md` (existing) — graphify invocation via `graphify-out/.graphify_python`
- UI: `~/Documents/Developer/CommandCenter/` (existing menu-bar app, extend with a MultiBrain module) **or** a new `~/Developer/multibrain-pet/` SwiftUI app — reads `~/.multibrain/health.json` + Daily Brief + Letta API

## Open Risks
- **[HIGH]** graphify may clobber `graph.json` — verify Phase 0 (merge shim mitigates).
- **[MED]** Letta adds a persistent server + Postgres dependency; if it's down at 02:30 the nightly loop can't run — health-check + fall back to the Phase-1 deterministic `consolidate.py` path.
- **[MED]** Mac asleep at 02:30 — catch-up guard handles; no forced wake.
- **[MED]** Obsidian Git 10-min auto-commit can catch a half-written note — flock + explicit end-of-job commit.
- **[MED]** Multica "learnings" extraction depends on its Postgres schema — unknown until inspected.
- **[MED]** Attribution coarse (`platform_source` = claude/codex only).
- **[LOW]** VM Hermes / Tailscale reachability at 02:30 — degrade gracefully.
- **[LOW]** LadybugDB is newer tech; keep graphify `graph.json` as the portable source of truth so the `.lbug` is a rebuildable index, not a single point of failure.
- **[DECISION] Email alert channel** — Telegram (bot exists) + APNs (relay exists) are ready; email needs an SMTP sender/creds (e.g. a Gmail app-password or a relay). Confirm the email path at build, or ship Telegram-first.
- **[MED] Alerting must not itself fail silently** — the health monitor needs a dead-man's-switch: if the nightly job never runs, a separate lightweight check (or the hourly health job) must notice the stale `last-success` and alert; alerting code has its own minimal self-test.
