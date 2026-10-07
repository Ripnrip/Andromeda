# Shared-memory cloak review (S3) — Multica umbrella

> **Status:** 🚧 Formalized 2026-10-07 · **Pillar:** 1 Memory  
> **Tickets:** Multica HAB-602 cloak lane · umbrella `3b17466e`  
> **Related:** `VisibilityFilter`, `LETTA-MEMORY-INGRESS.md`, ADR-0020

Operator gate before any shared-memory cutover. Clients never see cloak brands —
Andromeda enforces visibility behind the curtain.

## Rules (locked)

| Surface | Inbound | Outbound / egress |
|---------|---------|-------------------|
| **Letta memfs** | Writes allowlisted to `system/knowledge/**` only; never `persona`/`human`. Tag mandatory. Attributable author (`andromeda-memory-ingress`). Idempotency ledger. Ours-appends merge. | Memfs stays out of shared `MEMORY_FILE_PATH` by default; only explicit `public` knowledge may fan out; `persona`/`human` default `private`. |
| **Curtain retain** | `VisibilityFilter.determineVisibility` — cloak/secrets tags + credential patterns force `internal`. | CloudKit / vector / share: `public`+`friends` only (`publicShare` = public only). Ladybug / local materialization: all classes on-device. |
| **Letta ingress writer** | `LettaMemoryFact.cloaked` before seal (Phase 2 partial). | Same VisibilityFilter classes rendered into body metadata. |

## Proof checklist

1. [x] VisibilityFilter unit proofs (`PROOFS/09-visibility-filter.md`)
2. [x] Letta ingress cloak force-internal (MemoryKit tests, 2026-10-07)
3. [ ] Shared `MEMORY_FILE_PATH` fan-out review on Studio (operator)
4. [ ] agent-to-agent proof recorded (`MemoryChainProofRunner`, HAB-600)
5. [ ] Ladybug-index leg beyond health (upsert/query)

Until 3–5 pass, do **not** claim shared-memory ship.
