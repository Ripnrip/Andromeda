# 🧠 Multi-Brain Orchestration — The Vision

> **Status banner (2026-07-14):** This document is the original *why* narrative. The system described here is largely **built** on Studio (Phase 1–2); see [README.md](../README.md) and [ARCHITECTURE.md](ARCHITECTURE.md) for as-built truth. Keep this file as vision/presentation source — not the ops bible.

*A bespoke presentation. Read this first. It's the "why" that makes the "how" obvious.*

---

## The problem, in one image

You run a small army of AI agents. Claude Code ships features. Codex refactors. Hermes runs errands on two machines. Multica's autopilots grind through tasks. Every single day they **learn things** — a gotcha here, a pattern there, a decision, a dead end avoided.

And every single day, that knowledge **evaporates.** The session ends. The context window closes. The insight is gone, or buried in a 68 MB SQLite file no human will ever open. Tomorrow, a different agent rediscovers the same gotcha from scratch.

You have a dozen brains. None of them talk to each other. **None of them talk to you.**

---

## The idea

> **One curated brain that every agent feeds, that connects everything, that you can see and talk to — and that hands you back what matters each morning.**

Not another memory store. Not another dashboard you'll forget to open. A living **fabric** that:

1. **Captures** every agent's day (already happening — we just consume it).
2. **Distills** it — a stateful *Librarian* agent reads the raw river and writes clean, atomic, cross-linked notes.
3. **Connects** it — community-clustered graph, color-coded, densely wikilinked, semantically indexed.
4. **Reports** it — a Daily Brief when you wake, a Weekly Retrospective on Mondays.
5. **Shows** it — a menu-bar panel and a little Pet that reacts to your brain's pulse.
6. **Guards** it — tests everything, watches its own health, and shouts the instant it degrades.

---

## Why now: you've already built 70% of it

This isn't a greenfield moonshot. The hard parts are **already running on your Mac:**

| Already there | Doing what |
|---------------|-----------|
| `claude-mem` (68 MB, ~670 obs/day) | Capturing every Claude Code + Codex session |
| `graphify` | Clustering knowledge into colored community graphs |
| `claude-obsidian` + SecondBrain vault | A real PARA/Zettelkasten home, ready and near-empty |
| Hermes ×2, Multica, pgvector | Running, full of signal |

The missing 30% is **connective tissue**: a nightly consolidation loop, a conductor agent, a unified index, the briefs, the tests, the face. That's this project. We're not building a brain from neurons — we're wiring up brains that already fire.

---

## The cast

- **The Librarian (Letta).** The star. A persistent, conversational agent whose *core memory* is the evolving state of your work and whose *archival memory* is the whole fabric. It runs the nightly distillation as its own reasoning, remembers across days, and answers when you ask *"what did we learn this week?"* It's the brain you talk to.
- **The Scouts (extractors).** Deterministic, boring, reliable. They read each agent's store and hand the Librarian a clean digest. No hallucination in the plumbing.
- **The Cartographer (graphify).** Turns notes into a map — communities, hubs ("god nodes"), surprising cross-links — and paints Obsidian's graph in living color.
- **The Vault (LadybugDB).** One file. Graph + vector + HNSW. The single surface any agent can query: *"what do we know about X, and what's it connected to?"*
- **The Pet.** The face. It naps on quiet days, perks up when insights pour in, and gets visibly alarmed when something breaks. Delight as a status indicator.
- **The Sentinel (health + alerts).** Trusts nothing. Tests every permutation, checks every invariant hourly, and if the brain ever starts to rot — a **loud** Telegram/email/APNs message, immediately.

---

## A day in the life

> **02:30** — The Mac is quiet. The nightly job wakes the Librarian: *"Consolidate yesterday."* The Scouts fan out — claude-mem, Hermes, Multica, the VM. A digest forms. The Librarian reads it and writes: six crisp session notes, each attributed, tagged, and wikilinked. The Cartographer redraws the graph; new communities bloom in fresh colors. Everything folds into the `.lbug`. A Daily Brief is written.
>
> **07:30** — You sit down. The Pet has a gentle ✨ badge. You click it: *"Yesterday: 6 sessions across Portfolio, multibrain, and the router fix. Insights ahead: 4 open threads — the pgvector migration is still unresolved."* One glance, and you know where you stand.
>
> **Later** — *"brain, what did we figure out about the port collision?"* The Librarian answers, citing the exact session note and the three graph-neighbors around it.
>
> **Monday** — A retrospective lands: the week's themes, the surprising connection between two projects you hadn't linked, one contradiction flagged for you to resolve.
>
> **If anything breaks** — before you even notice, your phone buzzes: *"🔴 Multi-Brain: capture stale, no observations in 26h. Last good 02:34 yesterday."*

---

## Principles

- **Local-first.** Everything on `127.0.0.1` / Tailscale. Your brain is yours.
- **Consume, don't duplicate.** We wire up existing capture; we don't add another silo.
- **Deterministic where it can be, agentic where it must be.** Scripts read DBs; the Librarian exercises judgment.
- **Loud failure.** Silence is never success. If it degrades, you *will* know.
- **Rebuildable.** The `.lbug` and graph are indexes; `graph.json` and the vault are truth. Nothing is a single point of failure.

---

## Where we are

📐 **Fully specified, ready to build.** Codex takes the first implementation. The plan is phased so value lands early: a working two-agent brain (Phase 1) before the Librarian (Phase 2) before the face (Phase 4). Every phase ships with tests and health checks.

**Start here → [PLAN.md](PLAN.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [DATA-CONTRACTS.md](DATA-CONTRACTS.md)**

*The river doesn't have to evaporate. Let's give it somewhere to go.*
