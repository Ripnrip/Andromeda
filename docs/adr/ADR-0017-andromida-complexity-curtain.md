# ADR-0017 — Andromida complexity curtain (JSON outbox authority)

> **Status:** Accepted (2026-08-08) · BIN-246–252  
> **Honesty:** 🚧 partial ship — core curtain in MemoryKit; Apple RealmSwift adapter still 📐 behind `OutboxLiveProjection`.

## Context

The Andromida complexity curtain standard locks a small agent verb surface and
separates durable intake from live operator projections. Prior docs treated
SwiftData as the hot SoT and `memory.store` / `memory.recall` as the client
verbs ([MEMORY-CURTAIN-CONSOLIDATION.md](../MEMORY-CURTAIN-CONSOLIDATION.md)).
The new standard (shared as `andromida-complexity-curtain.md`) elevates a
**JSON outbox** as write authority and a **fail-open live projection**
(Realm-shaped) for queue awareness.

## Decision

1. **Canonical verbs:** `memory_recall`, `memory_retain`, `memory_forget`,
   `memory_health`. Dotted `memory.*` / `infer.write` / journal / session-dump
   remain compatibility shims. Session dump / journal stay off the agent hot path.
2. **Write authority:** `JSONOutboxAuthority` (JSONL seeds). Retain succeeds when
   the seed is durable — before backend delivery.
3. **Live projection:** `OutboxLiveProjection` protocol. Shipped implementation is
   `RealmOutboxLiveProjection` (in-process, rebuildable). It must never block
   retain success (fail-open). RealmSwift Apple adapter remains a future adapter
   behind the same protocol — clients never see the brand.
4. **Recall:** `RecallPlanner` classifies intent (exact / temporal / long-document /
   code-graph / synthesis) and `RankFusion` merges backend lists with tombstone
   suppression. Agents never choose stores.
5. **Operator flows:** `memory_health`, projection rebuild, pending replay, and
   drift detection (authority vs projection ID sets / counts).
6. **Companion:** `AndromidaCompanionView` exposes retain / recall / health / queue
   insights without backend brands.

## Consequences

- SwiftData remains a valuable hot working adapter, not the retain acceptance SoT
  for the new curtain path.
- HUD / Home accept both canonical underscore verbs and legacy shims.
- Graph / long-doc / synthesis adapters are stubbed fail-open until wired.
- Docs must mark RealmSwift and full Companion dogfood as 🚧/📐 honestly.

## Alternatives considered

| Option | Why rejected |
|--------|----------------|
| Twin SoT (SwiftData + Realm) | Dual-write hell; already rejected |
| Rename only (`memory.write`) without outbox | Does not give durable intake independent of backends |
| Make Realm the authority | Conflates operator UX with system truth; LAN spec + Linear review lock JSON authority |

---

## Footnote — vector recall is weaker than it markets (2026-09-11)

Decision 4 has `RecallPlanner` classifying intent across exact / temporal /
long-document / **code-graph** / synthesis, with `RankFusion` merging backend
lists. Before wiring a semantic/vector backend behind that planner, note what
a controlled benchmark of one actually showed.

`zg` (zvec-grep, Alibaba/Qwen, Apache 2.0) unifies ripgrep + BM25 + local
vector embeddings. Tested with six **blind intent-only queries** — behaviour
described in a sentence, all identifiers withheld — scoring whether the known
target symbol appeared in the top 5:

| Corpus | `zg` hybrid | `rg`, one keyword guess |
|---|---|---|
| 1,893-file TS/Vue/Python monorepo | **1/6** | **5/6** |
| 56-file Swift app | **3/3** | 3/3, but ranked 4th-6th |

Three findings that bear directly on `RecallPlanner` and `RankFusion`:

1. **Vector recall never returns empty.** Asked for exponential-backoff code
   in a repo containing none, `zg` confidently returned unrelated
   error-recovery classes. `rg` correctly returned nothing. A fusion ranker
   that treats "backend returned rows" as evidence of relevance will promote
   confident noise. **Absence must be representable** — a vector adapter
   needs a score floor below which it reports nothing, or `RankFusion` needs
   to discount it against a lexical backend that *can* return empty.
2. **Precision degrades with corpus size**, sharply. Strong at 56 files, weak
   at 1,893. Whatever scope the planner hands a semantic adapter should be
   narrowed first, not handed the whole store.
3. **Its win is ranking, not recall.** Where it beat `rg` it did so by
   returning the correct *line range* at rank 1 where `rg -l` buried the file
   at rank 4-6. That is a real contribution to fusion — as a re-ranker over a
   lexical candidate set, not as a primary retriever.

For the **code-graph** intent specifically, neither tool is the answer:
`ripwire` (deterministic tree-sitter call graph, no embeddings) resolved
callers correctly on every case where an LSP-backed symbol server returned
nothing — including every Swift lookup without a compiled index store.

Full method, per-query results and caveats:
`ai-ide-setup/docs/search-tooling/{zg,ripwire}-guide.md`.

**Bearing on this ADR:** no change to the accepted decision. This is a
constraint on future adapter work behind Decision 4 — "stubbed fail-open
until wired" should stay stubbed until the empty-result and scoping
questions above are answered.
