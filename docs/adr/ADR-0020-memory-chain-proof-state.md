# ADR-0020: Memory-chain proof state document

- **Status:** Accepted (2026-09-20)
- **Tickets:** Multica HAB-599 / HAB-602 · Linear BIN-287 / BIN-197
- **Related:** ADR-0019 (mcp-hub config schema) · `docs/plans/LETTA-MEMORY-INGRESS.md`

## Context

The canonical-verbs lane (HAB-602 / BIN-197: "memory verbs everywhere — prove
the full chain") needs a machine-readable record of *whether the full memory
chain is proven*, and the HUD `memory_health` capability (HAB-599 / BIN-287)
needs to *read* that record at runtime. Before this ADR there was no format:
proofs lived in `PROOFS/*.md`, which humans can read but the HUD cannot census.

## Decision

A single versioned JSON document at `~/.andromeda/proofs/memory-chain.json`:

```json
{
  "version": 1,
  "lastRun": "2026-09-20T05:16:43Z",
  "legs": [
    {
      "id": "agent-to-agent",
      "status": "pass",
      "at": "2026-09-20T05:16:43Z",
      "detail": "memory.store from Claude Code recalled via memory.recall from Codex"
    },
    {
      "id": "letta-ingress",
      "status": "pending",
      "at": null,
      "detail": "ingress commit counted in-context (blocked on Studio-Agent endpoint)"
    }
  ]
}
```

Rules:

1. **Versioning.** `version` is `1`. Any field rename/addition bumps it. The
   reader (`MemoryChainProofStore`) throws on a newer version instead of
   guessing — the HUD then shows an honest failure, not a misread document.
2. **Legs are stable ids** (`agent-to-agent`, `letta-ingress`, …). A leg with
   no result yet is `pending` with `at: null` — absent legs mean the lane has
   not even attempted that leg.
3. **Statuses** are exactly `pass` / `fail` / `pending`. No partial credit:
   a leg passes when its acceptance criterion (HAB-602 § Proof) fully holds.
4. **Write ownership:** the proof lane (canonical-verbs work) writes the
   document after each proof run. The HUD (`memory_health`) and any operator
   tooling only ever *read* it. The HUD never mutates proof state.
5. **Absence is not failure.** No document on disk means "proof not recorded
   yet" — the HUD census renders it as honest yellow (🚧), never fake green
   and never a hard error.
6. **Operator-internal path.** The document lives under `~/.andromeda/` and is
   never surfaced through client capability responses; only its *summary*
   (pass counts, leg names) appears on the operator HUD.

## Consequences

- The HUD `memory_health` chain report derives its proof line from this
  document (`MemoryChainProofSummary`); the umbrella gate "shared-memory
  visibility/cloak review" can audit exactly what the HUD shows.
- The proof lane has a write contract to land against; once the Letta ingress
  leg passes, the HUD flips from 🚧 to proof-passed with zero UI changes.
- `PROOFS/*.md` remains the human narrative; this JSON is the machine census.
