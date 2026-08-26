# Memory Bridge Plan — Andromeda ↔ Claude Knowledge Stack

**Status:** PHASE-1 PLANNED (2026-08-26) · **Owner:** Gurinder · **Tracking:** HAB-365 (Multica) · **Canonical copy:** `~/Developer/Andromeda/Plans/2026-08-26-memory-bridge-plan.md` (skill copy: `~/.claude/skills/andromeda-sync/BRIDGE-PLAN.md`)

## Goal

Connect the two memory worlds so a learning authored on the claude side is recallable from Andromeda (app + gateway), and a memory captured on-device flows back into the claude knowledge stack. When Phase 0 lands, `andromeda-sync` becomes **destination #6** in `/knowledge-sync`'s matrix — for real, not by alias.

## Design law: the agent IS the log — worldview via events

> This is the architectural nuance the bridge must never flatten.

Anima's memory is **event-sourced**. The `AnimaEpisodicRecord` rows and `OutboxRecord` retain/forget events **are** the memory; every projection downstream — Obsidian markdown, app views, recaps, the claude-side stores — is a **rebuildable derivation** of that log. The worldview ("what do we know, who knew it, when") is *assembled from events*, never stored as state.

Consequences, binding on every phase:

1. **Agent attribution is first-class.** Every event carries `agent` + `provenance`. A learning pushed by `pi` must remain distinguishable from the same fact pushed by `claude` — not for vanity, but because the worldview query is *"who knew what, when"* and dedup keys (`contentHash`) are computed per authored narrative, not per fact.
2. **Push events, not state.** The bridge ships `.retain` / `.forget` (tombstone) events — never "sync the current list." A forget on one side tombstones; it never deletes history. Replays are safe: projections rebuild idempotent from the same seeds.
3. **Delivery failure ≠ memory loss.** The outbox pattern (BIN-248) means enqueue is the commit point; delivery may lag (`pending → delivered → deadLetter`). The bridge reads delivery state honestly and reports gaps — a `deadLetter` row is surfaced, never silently retried into duplication.
4. **Recaps are derivatives.** Daily digests, terminal sweeps, recap reels are *views over the log*. They may be regenerated or thrown away; the events may not. (This is why herd-gather recaps cite evidence, and why `/checkpoint` remains the single authoring pass.)

A bridge that moves blobs without agent-attributed events would corrupt the paradigm: it would create state that looks authoritative but can't be replayed, attributed, or forgotten cleanly. Don't.

## Verified substrate (read from source 2026-08-26)

| What | Where | Status |
|---|---|---|
| Hot store | `AnimaEpisodicRecord` (SwiftData `@Model`): `id`, `contentHash` (unique), `project`, `agent`, `narrative`, `visibility`, `provenance`, `tags`, `materializedPath` | ✅ shipped |
| Event outbox | `Curtain/JSONOutboxAuthority` (BIN-248): atomic JSONL enqueue, `writeKind` retain/forget, `deliveryState`, tombstones | ✅ shipped |
| Gateway | `AndromedaGateway` (Hummingbird) on Studio — Autocache LLM routes only today | ✅ running, **no memory route yet** |
| Claude-side fan-out | `/knowledge-sync` → memory.md · claude-mem · graphify · multibrain · qdrant | ✅ live (5 destinations) |

## Canonical mapping (locked)

| claude-side (checkpoint/knowledge-sync) | Andromeda-side |
|---|---|
| `title` + `key insight` | `narrative` (joined, markdown) |
| `project` | `project` |
| `agent` (pi/claude/codex/kimi/…) | `agent` — **never defaulted, never stripped** |
| `tags` | `tags: [String]` |
| `type`/`source`/`confidence` | `provenance` (e.g. `knowledge-sync/pi/2026-08-26/high`) |
| `content_hash` (multibrain pattern) | `contentHash` — dedup free (unique constraint) |
| — | `visibility: "private"` (default; the bridge never widens) |
| deletion / supersession | `.forget` tombstone via `targetMemoryID` |

## Phases

### Phase 0 — gateway memory surface (the only real blocker) — HAB-365
- [ ] `MemoryRouter.swift` in `Sources/AndromedaHTTP`: `POST /v1/memory/retain`, `GET /v1/memory/export?since=`, `DELETE /v1/memory/:id` (→ `.forget`)
- [ ] Auth: bearer token via secrets broker (mirror Autocache pattern in `GatewayRouter`)
- [ ] Enqueue through `JSONOutboxAuthority` — no new durability code
- [ ] Contract tests: retain→dedup (same contentHash twice = 1 row), export pagination, tombstone, **agent attribution round-trip**
- [ ] Update `docs/DATA-CONTRACTS.md`; Studio localhost first (Funnel deferred to iOS wiring)

### Phase 1 — pull (Andromeda → claude stack) — read-only, ships first
- [ ] `andromeda-sync --from-andromeda`: GET export → qdrant doc + graphify entity per record (agent as node metadata)
- [ ] Runs as a pre-pass inside `/knowledge-sync` (pull before push, same-session merges)

### Phase 2 — push (claude → Andromeda)
- [ ] `--to-andromeda` after standard fan-out: POST retain (curated: checkpoints + explicit notes; never raw transcripts)
- [ ] Idempotency proof: re-sync same checkpoint → 0 new rows
- [ ] `/knowledge-sync` matrix row 6: ⬜ gated → ✅ live

### Phase 3 — live subscribe
- [ ] Outbox-driven incremental sync replaces nightly batch
- [ ] Conflict policy: same `contentHash` → skip; different hash same target → newest wins, loser tombstoned `.forget` (documented in DATA-CONTRACTS)

## Non-goals

Additive destination #6 — replaces nothing. No raw transcripts to the phone. No bidirectional realtime before Phase 3. No state-sync that bypasses the event log.

## Decision log

- **2026-08-26** Realm→SwiftData correction (draft doc bug). Outbox reuse over new ingest table.
- **2026-08-26** Pull-before-push phase order (read-only first).
- **2026-08-26** "Agent is the log" codified as binding design law (this doc, §Design law).
- **2026-08-26** Transport = gateway HTTP route, same-host first; Funnel deferred; XPC ruled out (iOS), file witness ruled out (no shared FS).
