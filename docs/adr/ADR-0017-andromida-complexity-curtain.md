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
