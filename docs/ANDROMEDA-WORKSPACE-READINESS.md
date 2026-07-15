# Andromeda Workspace Promotion Readiness

**Status:** GATED — do **not** force-move the Cursor workspace into Andromeda yet.  
**Date:** 2026-07-15  
**Locked decision:** dual-home until MemoryKit is battle-tested against live multibrain stores.  
**Linear / Multica:** comment on BIN-39 / HAB-56 — workspace flip still gated.

## What “memory battle-tested live” means

All of the following must be green before promoting Andromeda as the default app workspace:

| # | Criterion | Evidence / how to prove | Status (2026-07-15) |
|---|-----------|-------------------------|---------------------|
| 1 | **E2E bar smoke green** | `MemoryBridgeE2ESmokeTests` 3/3; proof `PROOFS/32-bar-e2e-smoke.md` | ✅ PASS |
| 2 | **store → Merkle seal → recall** on Studio hot path | CaptureService default `AnimaLedger` + bar MemoryBridge | ✅ PASS (temp stores; same APIs) |
| 3 | **journal / session_dump path** | Bar journal verb → hot store → recall | ✅ PASS |
| 4 | **Materializer fail-open** | Obsidian materializer errors must not block hot `store_memory` return | ✅ by design (hot path isolated); live Dream pass still fleet ops |
| 5 | **Indexes fail-open** | Qdrant / Ladybug down ⇒ recall still serves hot (vault degraded OK) | ✅ by design; optional Studio chaos check residual |
| 6 | **Canonical Studio store smoke** | Optional: one store/recall against `~/.multibrain/anima-hot.store` (not only temp) | ⬜ optional human confirmation |
| 7 | **`project.state` live Multica** | `MULTICA_LIVE=1` list/create; proof `PROOFS/33-…` | ✅ PASS |
| 8 | **`project.state` live Linear** | Requires `LINEAR_API_KEY` fan-out | ⬜ blocked on key |
| 9 | **Dual-home MemoryKit sync** | Andromeda `Packages/MemoryKit` matches multibrain tip used by bar | ⬜ after #5 merge |
| 10 | **No paid spend on nightly** | OpenRouter/Haiku killed on Studio nightly + dreamcatcher | ✅ BIN-36 / HAB-50 |

**Promotion rule:** Items 1–5 and 7 + 9 must be ✅. Item 8 is strongly preferred but Multica-only is acceptable if Linear remains operator-MCP-only. Item 6 is a final human gut-check.

## Dual-home package sync

| Home | Role until promotion |
|------|----------------------|
| `~/Developer/multibrain` | Fleet SoT, health, nightly, MemoryKit proofs (`PROOFS/`, `Packages/MemoryKit`) |
| `~/Developer/Andromeda` | Product / control-plane (Swift UI, capability surface, eventual primary MemoryKit consumer) |
| `~/Developer/multibrain-bar` | Floating macOS client; path-depends on multibrain MemoryKit |

**Sync procedure (when promoting or after MemoryKit PRs):**

```bash
# From multibrain tip (after merge) → Andromeda dual-home copy
rsync -a --delete --exclude '.build' --exclude '.swiftpm' \
  ~/Developer/multibrain/Packages/MemoryKit/ \
  ~/Developer/Andromeda/Packages/MemoryKit/
# Then PR in Andromeda with proof note + SHA pin
```

Do **not** flip the Cursor workspace root to Andromeda until the checklist above is signed off in Linear/Multica.

## Explicit non-goals

- Forcing Cursor / agent default cwd into Andromeda
- Exposing Linear / Multica / n8n brands in client menus
- Declaring battle-tested because unit tests alone are green

## Next human actions (workspace flip)

1. Confirm optional canonical-store smoke (`~/.multibrain/anima-hot.store`) if desired.
2. Provide / set `LINEAR_API_KEY` for full `project.state` fan-out.
3. After MemoryKit live-bridge merges: rsync dual-home + Andromeda PR.
4. Say the word to flip workspace defaults — agents will not do it unilaterally.
