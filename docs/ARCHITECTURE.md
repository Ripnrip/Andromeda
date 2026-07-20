# Architecture — Multi-Brain Orchestration

Companion to [PLAN.md](PLAN.md) and [FLEET.md](FLEET.md). Explains *why* each component exists and how responsibility is divided — **as built 2026-07-14**.

## The core idea

Many agents produce work all day. Their memory is either ephemeral or siloed. Multi-Brain Orchestration is the **connective tissue**: a nightly deterministic loop that turns every agent's day into curated vault notes + indexes, plus an interactive Librarian (Letta) on the Studio hub.

## Layered model (avoid the "everything is memory" trap)

| Layer | Responsibility | Component(s) |
|-------|----------------|--------------|
| **Capture** | Passively record what each agent did | `claude-mem`, Hermes FTS5, Multica PG, habitat Hermes SSH, Kimi bridge |
| **Extract** | Deterministically read each store's day | `bin/extract_*.py` → `aggregate_digest.py` |
| **Conduct (batch)** | Nightly synthesis + deposit | **`consolidate.py`** via `run-nightly.sh` |
| **Conduct (interactive)** | Conversational recall + bridge tools | **Letta** + `letta_setup.py` bridge (`brain` CLI) |
| **Substrate** | Human-facing curated knowledge | SecondBrain Obsidian vault |
| **Graph** | Connections, communities, colors | `graphify` + `graphify_merge.py` |
| **Index (hub)** | Unified graph+vector for multibrain | **LadybugDB** + index-server `:8286` |
| **Knowledge-sync vectors** | Session-learning semantic recall | **Qdrant** `secondbrain_learnings` (see [KNOWLEDGE-STACK.md](KNOWLEDGE-STACK.md)) |
| **Report** | Push knowledge back to the human | Daily Brief, Weekly Retro |
| **Guard** | Prove it's healthy, shout when not | `healthcheck.py` + `alert.py` (Telegram) |
| **Surface** | Visible & interactive UI | CommandCenter module + Pet (**Phase 4**) |

**FAISS** is an explicit non-goal (redundant with LadybugDB / pgvector / Chroma / Qdrant).

### Qdrant vs LadybugDB (do not conflate)

| Store | Role |
|-------|------|
| **LadybugDB** | Multibrain unified index for vault graph + vectors; rebuilt nightly on Studio; queried by Letta bridge / index-server |
| **Qdrant** | `/knowledge-sync` destination for individual learnings (`bin/qdrant-upsert.py`); separate collection; not part of nightly consolidate |

## Division of labor: deterministic vs agentic

- **Deterministic (Python):** extractors, digest shaping, dedup ledger, graphify merge, Ladybug rebuild, git commit, health. Testable; no hallucination in the plumbing.
- **Agentic (synthesis LLM + Letta):** prose synthesis in `consolidate.py` (z.ai / OpenRouter / `--no-llm` templates); Letta for interactive Q&A and optional tool orchestration via the bridge.

The original design imagined Letta *owning* the nightly loop. **As-built:** launchd runs `consolidate.py` directly; Letta is the conversational face and tool host.

## Data flow (nightly, as-built)

```
02:30 (Studio) / 03:00 (Book) launchd → run-nightly.sh
   │
   ├─ ingest_staged.py          # /checkpoint notes → vault
   ├─ extract_claudemem.py      # prove source readable
   ├─ consolidate.py            # aggregate_digest (claude-mem+hermes+multica+hermes-vm)
   │     └─ synthesis → 07-Sessions/*.md
   ├─ index_ladybug.py          # Studio hub; satellites may no-op / soft-fail
   ├─ graphify_merge.py         # if graphify_nightly
   ├─ git commit vault
   ├─ daily_brief.py
   └─ healthcheck (--mark-success) → alert.py on RED
```

Interactive (Studio only):

```
brain "…"  →  Letta :8283  ↔  bridge :8284  ↔  extractors / Ladybug / vault tools
```

## Why these technology choices

- **Letta:** stateful conversational Librarian (REST + tools). Native on Studio (`:8283`), Postgres on `:5442` — **not** Docker + `multica_default` (that was Wave-1 recon; superseded).
- **LadybugDB:** single-file graph + vector + HNSW; rebuildable from vault/graph — index, not SoT.
- **graphify:** community clustering + Obsidian colors via **merge shim** (never clobber physics).
- **claude-mem:** capture layer already running; we consume SQLite/Chroma.
- **Qdrant:** cheap local semantic recall for knowledge-sync facts — peer to memory.md / graphify MCP, not a second Ladybug.

## Boundaries

- **Code vs runtime:** repo = code + docs; `~/.multibrain/` = data (never committed).
- **Read vs write on sources:** extractors are **read-only** against capture stores.
- **Attribution:** prefer `sdk_sessions.platform_source` over NULL `agent_type`.
- **Fleet:** hub services (Letta, Ladybug, index-server) are Studio-only; satellites run capture + consolidate + health. See [FLEET.md](FLEET.md).

## Failure philosophy

Degrade gracefully and *loudly*. Unreachable VM Hermes skips that source. Missed nightly → dead-man's-switch. Invariant breaks → Telegram. Silence is never success.

## Graphify deep pass notes (2026-07-14)

Ran AST + deep semantic extract over `bin/` + docs (`graphify-out/`, ~550 nodes / ~930 edges). Highest-degree concepts matched the as-built story:

- **LadybugDB**, **Studio hub**, **Book satellite**, **consolidate.py**, **run-nightly.sh**, **Letta**, **healthcheck**, **SecondBrain** are the structural god-nodes.
- Docs and code agree: nightly batch ≠ Letta; Qdrant sits on the knowledge-sync side, not the nightly index path.
- Test modules (`test_consolidate`, `test_healthcheck`) cluster tightly with pipeline scripts — useful for future TEST-MATRIX fill-in.

See `graphify-out/GRAPH_REPORT.md` for the god-node list and sample INFERRED edges.
