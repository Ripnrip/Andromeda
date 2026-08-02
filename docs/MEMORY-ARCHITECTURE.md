# Memory Architecture — the vision reference

> **Audience:** agents building the Andromeda website, docs, or product copy; any agent
> touching Anima. This is the **memory-domain** deep dive — it complements, and does not
> replace, [ANDROMEDA-CONTROL-PLANE.md](./ANDROMEDA-CONTROL-PLANE.md) (six pillars + curtain)
> and [MEMORY-ONEPAGER.md](./MEMORY-ONEPAGER.md) (Andromeda × Anima × Multibrain relationships).
> **Honesty legend:** ✅ shipped · 🚧 partial · 📐 specified / not built. No greenwashing.

---

## 1. The thesis (one paragraph for the homepage)

Every AI agent you run generates a river of work each day — fixes, decisions, root causes,
configs, conversations. Without a memory system it all **evaporates**: you re-solve the same
problem, forget why a thing is the way it is, lose hard-won decisions. We call that the
**evaporation tax**. Andromeda's memory subsystem (**Anima**) exists to stop the evaporation:
*every agent's day, distilled into one curated, connected, queryable brain — and a companion
that hands the relevant part back to you, exactly when you need it.* The hard part isn't
capturing — it's capturing **once**, connecting everything, recalling by **meaning**, and
hiding all the machinery behind one calm surface. That surface is the **capability curtain**.

---

## 2. The memory paradigm — author once, distribute many

Memory is built in **three separate passes**, never conflated:

| Pass | Skill | Job | Output |
|------|-------|-----|--------|
| **Author** | `/checkpoint` | Write ONE structured, dated record of a learning/decision/incident | a markdown note (doubles as a session-learning deposit) |
| **Distribute** | `/knowledge-sync` | Fan that ONE record to every live destination in a consistent shape | memory.md · graphify · qdrant · multibrain/Obsidian staging · (claude-mem auto) |
| **Orchestrate** | `/close` | Run author → distribute, then offer the bows (changelog, recap reel, graphify) | a clean session close |

**Why separate passes:** authoring and review are different cognitive modes; merging them
produces worse notes and worse distribution. **Idempotent by design** — re-running on the same
learning merges, never duplicates. The callsite (the agent at sync time) never decides *which*
brand of store to write; it hands the record to the distribute pass and the substrate carries it.

---

## 3. The eight layers of memory (Anima)

Human memory isn't one thing; neither is Anima. Eight layers, one job each:

| # | Layer | Intent | Today's machinery | Anima target |
|---|-------|--------|-------------------|--------------|
| 01 | **Episodic** | "We talked Tuesday" — timed, emotional, compactable | claude-mem observations + transcripts | SwiftData hot capture + integrity seal |
| 02 | **Semantic** | "Chapter 3 has the state machine" — structure-first recall | Obsidian SecondBrain + graphify + LadybugDB + Qdrant | Knowledge adapters with provenance |
| 03 | **Photographic** | "I've seen that diagram" — vision/CLIP | 📐 gap (screenshots not first-class today) | Local MLX/CLIP, greenfield |
| 04 | **Integrity** | "Can I trust this memory?" — Merkle | health.json + git vault + content-hash dedup | Merkle proofs over memory trees |
| 05 | **Meditation** | Morning reflection from the dream journal | Daily Brief + weekly retro scripts | Intention-setting actor |
| 06 | **Soul** | Presence, mood, relationship depth | Letta persona (thin today) | Relationship context only — not chatbot paste |
| 07 | **Awareness** | Speak only when it matters (`HEARTBEAT_OK` = silence) | hourly health → Telegram on RED | Presence-aware pulse; silence is a feature |
| 08 | **Dream** | Night: Review → Shadow → Insight → Integration | nightly `run-nightly.sh` + graphify | Swift dream cycle (coexists with nightly until it absorbs it) |

**Website framing:** present the 8 layers as the "kinds of remembering." Most products ship
only #1 (a chat log) and maybe #2 (RAG). The differentiator is the *full* spectrum —
especially **Integrity** (can you trust it?), **Awareness** (it knows when *not* to interrupt),
and **Dream** (it reflects overnight so the morning is smarter).

---

## 4. The services today — what each store does and why

Seven live surfaces today (the multibrain fleet). Each is the right tool for one recall
question. **One job per store** — never merge them.

| Service | Style | Role today | Recall question it answers |
|---------|-------|-----------|----------------------------|
| **memory.md** | document / key-value | Fast-recall layer: one fact per markdown file, indexed by a single `MEMORY.md` pointer loaded into every session | "What do I already know about X, right now, in plain text?" |
| **claude-mem** (Chroma + SQLite) | auto-ingested vector + relational | The capture river; an observer ingests the live session automatically — no manual write API | "What actually happened, in order, across sessions?" |
| **graphify** (MCP `memory` server) | graph | Entities + relations between concepts | "What is *connected to* what?" |
| **qdrant** (`:6333`, `secondbrain_learnings`) | vector (384-dim, local embeddings) | Semantic fact vectors written by `/knowledge-sync` | "Find the note about X *by meaning*, not keywords" |
| **Obsidian SecondBrain** | document vault (PARA/Zettelkasten) | The human-readable substrate; ~132 curated notes; the nightly deposits here | "Let me read and browse my knowledge like a notebook" |
| **LadybugDB** (`:8286` + `multibrain.lbug`) | graph + vector over the vault | Multibrain's hub query index; rebuildable cache (point ID = content-hash) | "Query the whole vault analytically, fast" |
| **Letta** (`:8283` + bridge `:8284`) | conversational (MemGPT-style) | Interactive Librarian — chat that remembers across sessions (`brain "…"`); **not** the nightly conductor | "Conversational recall — ask, refine, follow up" |

### Why a graph (graphify) AND a vector store (qdrant)?
They answer **different questions**. A vector store finds *similar* things by meaning. A graph
finds *related* things by connection. "The cloak router **tunnels-to** the home router, which
**egresses** New York, which **gates** the kill-switch" is a chain of **relations** — no
embedding similarity will surface that structure. Conversely, "find the note about recovering
a lost key" is a **meaning** query that a graph can't do well. You need both. This is the
single most under-explained nuance on most "AI memory" sites — **lead with it**.

### Why so many stores? (the spectrum)
Animate an axis from **exact/human-readable** → **meaning/relationship**:

```
document ────── relational ────── vector ────── graph ────── hot/cold tier
(memory.md,    (claude-mem       (qdrant,       (graphify,    (SwiftData hot →
 Obsidian)      SQLite)           Ladybug,       Ladybug        CloudKit cold →
                                 Chroma)        relations)     Obsidian)
exact & durable  structured       by meaning     by connection  latency vs durability
```

Each style is the right answer to a different recall question. **No single store does all
well — that's why there are many.** The stack exists because memory isn't one problem, it's
five. Andromeda's job is to make those five look like one to the client.

---

## 5. The capability curtain — how complexity is concealed

This is Andromeda's central design move, and the thing the website must communicate most clearly.

**Mechanic:** clients (apps, agents, CLIs, the HUD) call **stable capability IDs only**.
Andromeda resolves providers, secrets, stores, and routing **server-side**. Brand names,
store paths, ports, and raw keys **never cross into the client process**.

```
        CLIENT SEES                     ANDROMEDA HIDES
   ┌──────────────────┐         ╔═════════════════════════════════╗
   │  memory.recall   │ ──────▶ ║ SwiftData · vault · Qdrant ·     ║
   │  memory.store    │         ║ Ladybug · claude-mem             ║
   │  infer.write     │ ──────▶ ║ Anthropic · Cerebras · keys      ║
   │  project.state.* │ ──────▶ ║ Linear ∪ Multica ∪ Slack         ║
   │  slack_proxy     │ ──────▶ ║ Keychain tokens · env            ║
   └──────────────────┘         ╚═════════════════════════════════╝
                  stable ID in ───────▶ resolution out
```

### Curtain mapping (the table the site should render)

| Capability ID | What the client does | What Andromeda resolves behind the curtain | What the client must NEVER see |
|---------------|----------------------|---------------------------------------------|--------------------------------|
| `memory.recall` | "remember this topic" | SwiftData hot + vault fallback (+ Qdrant/Ladybug at the semantic tier) | store paths, index brand names |
| `memory.store` | "save this episode" | transactional SwiftData write → async materialize/index | write order, index brands |
| `infer.write` | "generate text" | model registry + health + fallbacks + cache ROI | Anthropic/Cerebras/OpenRouter, raw keys |
| `project.state.*` | "what's the status of X" | Linear ∪ Multica ∪ Slack fanout | tracker brand names in menus |
| `slack_proxy` / `github_proxy` | "post this" | broker calls API with a Keychain token | `SLACK_BOT_TOKEN`, `GITHUB_TOKEN`, env dumps |

**Hard rule:** UI LaunchAgents and satellite agents run with **env scrub** (`HOME` + `PATH`
only). The broker injects secrets **server-side at call time**. Raw key values never enter a
client or agent process environment. 📐 *Broker runtime is specified, not yet shipped.*

**Website framing:** the curtain is the product. Show the before/after — "today your agent
script hard-codes provider names, store paths, and API keys; tomorrow it says
`memory.recall` and Andromeda does the rest." One sentence: **"Stable ID in. Resolution out."**

---

## 6. Privacy and visibility — what may leave the device

Visibility is a first-class field, not an afterthought. Missing values default to **private**;
cloak/secret/credential markers force **internal**.

| Visibility | Meaning | Local (SwiftData/Ladybug/Obsidian) | CloudKit / vector egress |
|------------|---------|-------------------------------------|--------------------------|
| `public` | explicitly shareable | allowed | allowed |
| `friends` | trusted-sharing scope | allowed | allowed |
| `private` | **default** | allowed | **blocked** |
| `internal` | forced by secret/cloak markers | allowed | **blocked** |

**Local-first, not local-only:** the device stays useful when providers, hosted graph stores,
MCP servers, or telemetry exporters fail. Cloud egress is opt-in per-record, never blanket.
🚧 *Egress enforcement on Python note frontmatter is an open schema gap, not yet proven safe.*

---

## 7. The daily loop — aligned clocks

Memory isn't a database you query; it's a cycle that maintains itself.

| Clock | Phase | Today (multibrain) | Anima target |
|-------|-------|--------------------|--------------|
| ~02:30 / 03:00 | **Dream** (Review → Shadow → Insight → Integration) | `com.multibrain.nightly` → `consolidate.py` conductor + graphify | Swift dream cycle (coexists, then absorbs nightly) |
| ~07:00 | **Meditation** (read dream journal, set intention) | Daily Brief on disk | intention-setting actor |
| Hourly | **Awareness** pulse | `com.multibrain.health` → Telegram only on RED | presence-aware; `HEARTBEAT_OK` = silence |
| Mon 08:00 | **Integration** / retro | `weekly_retro` (Studio) | weekly integration |
| On demand | **Conversation** | `brain` → Letta | Swift conversational recall |

**Website framing:** most "memory" products are passive storage. Anima is a **rhythm** — it
dreams at night, meditates in the morning, and speaks only when it matters. That cadence is
the product, not a feature.

---

## 8. Migration vision — consume and subsume, never replace

Anima does **not** greenfield a ninth memory silo. It builds **adapters** over the existing
fleet and migrates inward, one store at a time, never stranding working capture.

- **Phase 0 (today):** multibrain Python fleet is the production brain; Anima reads, does not own.
- **Phase 1:** adapters over claude-mem, Obsidian, Qdrant/Ladybug, health — same data, Swift surface.
- **Phase 2:** SwiftData hot capture becomes the episodic source-of-truth; nightly coexists.
- **Phase 3:** Swift dream cycle absorbs nightly curation; Letta's role moves to a Swift runtime.

**Non-negotiables during migration:** durable record **before** processing; replay/rollback
always possible; no silent loss; one job per store; never delete a source-of-truth record
because a derived index accepted it. The Studio is the Phase-2 hub; Book is a Phase-1
satellite (nightly + health only — never assume Letta/Ladybug on every Mac).

---

## 9. Proof it works — grounded in a real session (2026-07-19)

This isn't spec. A live `/knowledge-sync` of one milestone ("cloak router restored after a
factory reset") landed across the stack, verified:

| Destination | Evidence |
|-------------|----------|
| memory.md | new fact file + `MEMORY.md` pointer; old design marked SUPERSEDED, incident marked RESOLVED |
| graphify | **4 entities + 5 relations** (router `tunnels-to` home server; milestone `recovered-key-via` server-side storage) |
| qdrant | vector point `43d3c386…`; **recall verified #1 @ 0.626** for "how do I get my WireGuard key back after resetting the travel router" — semantic match on a query whose exact words aren't in the note |
| multibrain → Obsidian | checkpoint staged in `07-Sessions/`; nightly carries it into the SecondBrain vault + indexes LadybugDB |
| claude-mem | worker healthy, auto-ingesting the session |

**Website framing:** the `#1 @ 0.626` recall is the money proof — show it. It demonstrates
*meaning-based retrieval* succeeding where keyword search would fail.

---

## 10. What is and isn't shipped (honesty, 2026-07-19)

**✅ Shipped:** `memory.recall`/`memory.store` (SwiftData hot + vault fallback) · `memory.journal`/
`session_dump` (Home/Bar; HUD on promotion branch) · `project.state.*` CRUD · `/checkpoint` →
`/knowledge-sync` → `/close` ritual · the multibrain nightly conductor · Autocache Anthropic
LLM-proxy surface · curtain + MemoryKit.

**🚧 Partial:** MCP sprawl bent 55→37 but shared dedupe host not shipped · HUD journal/visibility
on a promotion branch (merge/CI gates shipped status) · Letta/Ladybug/Qdrant live on Studio hub only.

**📐 Specified, not built:** Secrets broker (`slack_proxy`/`github_proxy`/`write.too` runtime) ·
MCP consolidate (one shared host) · `SkillRegistry` product surface · full multi-provider LLM
router beyond Autocache/Anthropic · fleet plist single-source-of-truth + typed mutate ·
CloudKit end-to-end replication · Photographic (CLIP) layer · Swift Letta/dream runtime.

**`infer.write` caveat:** today it's an **episodic-store alias tagged `infer-write`**, NOT LLM
inference. It becomes a real inference capability only through an explicit versioned migration;
until then existing callers are memory writers. Do not advertise it as inference.

**Workspace flip:** still **NO-GO** (PROOF 44 blockers, PR #10 CI, BIN-101 Swift installer,
human word required). See [ANDROMEDA-WORKSPACE-READINESS.md](./ANDROMEDA-WORKSPACE-READINESS.md).

---

## 11. Principles the website must not contradict

From the [Charter](../ANDROMEDA-CHARTER.md):

1. **No silent loss. No invisible automation. No provider lock-in as config. No knowledge without provenance. No automation without visibility. No migration without rollback.**
2. Capability names beat provider names — clients ask for capabilities; Andromeda resolves.
3. Append before processing — observations are durably journaled before enrichment/embedding/routing.
4. Local-first, not local-only — useful offline; cloud is opt-in per record.
5. Everything important is observable — logs, metrics, trace, status, owner, privacy classification.
6. Human authority remains explicit — observe vs suggest vs reversible vs destructive vs privileged.
7. Evidence drives evolution — prompt/skill/model/policy changes need hypothesis, baseline, eval, rollback.

---

## 12. Website section map (for the builder agent)

| Site section | Source in this doc | Key asset |
|--------------|--------------------|-----------|
| Hero / thesis | §1 | the evaporation-tax line + "one brain" |
| "How it remembers" | §3 (8 layers) | layer grid; call out Integrity/Awareness/Dream as differentiators |
| The stores / services | §4 | the 7-service table + the doc→graph spectrum |
| "Why graph + vector" | §4 (graph nuance) | the relation-chain example — lead this |
| The capability curtain | §5 | before/after diagram + mapping table; "stable ID in, resolution out" |
| Privacy / local-first | §6 + §11 | visibility tier table; "useful offline" |
| The daily rhythm | §7 | clock table; "memory as a cycle, not a database" |
| Proof | §9 | the `#1 @ 0.626` recall card |
| Honest status | §10 | shipped/partial/specified — do not overclaim (esp. `infer.write`) |

---

## 13. Related docs

| Doc | Role |
|-----|------|
| [ANDROMEDA-CONTROL-PLANE.md](./ANDROMEDA-CONTROL-PLANE.md) | Six pillars + curtain (canonical, dual-homed) |
| [MEMORY-ONEPAGER.md](./MEMORY-ONEPAGER.md) | Andromeda × Anima × Multibrain relationships + Anima agent brief |
| [../ANDROMEDA-CHARTER.md](../ANDROMEDA-CHARTER.md) | Founding charter, non-negotiables, module map |
| [KNOWLEDGE-STACK.md](./KNOWLEDGE-STACK.md) | `/checkpoint` → `/knowledge-sync` → `/close` detail |
| [ANDROMEDA-WORKSPACE-READINESS.md](./ANDROMEDA-WORKSPACE-READINESS.md) | The flip gate |
| [ANIMA-PROJECT-LINKS.md](./ANIMA-PROJECT-LINKS.md) | Operator Linear∪Multica∪Slack tracking |

---

*Eight layers. Seven services. One curtain. No silent sprawl.*
