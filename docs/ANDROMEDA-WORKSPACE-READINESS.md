# Andromeda Workspace Promotion Readiness

**Status:** GATED — do **not** force-move the Cursor workspace into Andromeda yet.  
**Date:** 2026-07-15 (evening residual — proof 34 + Linear live)  
**Locked decision:** dual-home until MemoryKit is battle-tested against live multibrain stores.  
**Linear / Multica:** BIN-39 / HAB-56 — workspace flip **still gated** until dual-home MemoryKit is fully synced (#9).

## Visible Alpha closeout (2026-07-15 evening)

Tonight closed the **Visible Alpha** capability curtain as a visible chapter — not a workspace promotion:

- E2E bar smoke **PASS** (proof 32): `MemoryBridgeE2ESmokeTests` 3/3; bar remembers via MemoryKit.
- Live `project.state` → Multica **PASS** (proof 33); Multica live green.
- Live `project.state` → Linear **PASS** via dotenv + `LINEAR_LIVE=1` (`LiveLinearProjectStateTests`); smoke probes BIN-44…49 / HAB-67…69 cancelled after proof.
- Canonical Studio hot store **PASS** (proof 34): `~/.multibrain/anima-hot.store` store→seal→recall.
- Dotenv loader landed on fleet tip (multibrain **#15**); Andromeda dual-home may still trail on create-suite / `LINEAR_LIVE` gate parity — reconcile before calling #9 ✅.
- Autocache gateway + MemoryKit UI wave already on Andromeda main.

**Flip remains gated.** Checklist progress ≠ default Cursor workspace promotion.

## What “memory battle-tested live” means

All of the following must be green before promoting Andromeda as the default app workspace:

| # | Criterion | Evidence / how to prove | Status (2026-07-15 eve) |
|---|-----------|-------------------------|-------------------------|
| 1 | **E2E bar smoke green** | `MemoryBridgeE2ESmokeTests` 3/3; proof `Packages/MemoryKit/PROOFS/32-bar-e2e-smoke.md` | ✅ PASS |
| 2 | **store → Merkle seal → recall** on Studio hot path | CaptureService default `AnimaLedger` + bar MemoryBridge | ✅ PASS (temp stores; same APIs) |
| 3 | **journal / session_dump path** | Bar journal verb → hot store → recall | ✅ PASS |
| 4 | **Materializer fail-open** | Obsidian materializer errors must not block hot `store_memory` return | ✅ by design (hot path isolated); live Dream pass still fleet ops |
| 5 | **Indexes fail-open** | Qdrant / Ladybug down ⇒ recall still serves hot (vault degraded OK) | ✅ by design; optional Studio chaos check residual |
| 6 | **Canonical Studio store smoke** | One store/recall against `~/.multibrain/anima-hot.store` (not only temp) | ✅ PASS — store exists; proof `Packages/MemoryKit/PROOFS/34-canonical-hot-store-smoke.md` (bar mirror `multibrain-bar/PROOFS/34-…`) |
| 7 | **`project.state` live Multica** | `MULTICA_LIVE=1` list/create; proof `Packages/MemoryKit/PROOFS/33-project-state-live-bridge.md` | ✅ PASS |
| 8 | **`project.state` live Linear** | Dotenv + `LINEAR_LIVE=1` suite | ✅ PASS — `LINEAR_LIVE=1 swift test --filter LiveLinearProjectStateTests` green via `~/Developer/multibrain/.env` (key never logged); proof 33 Linear section |
| 9 | **Dual-home MemoryKit sync** | Andromeda `Packages/MemoryKit` matches multibrain tip used by bar | ⚠️ partial — multibrain **#15** dotenv on tip; Andromeda still needs rsync / parity PR before #9 ✅ |
| 10 | **No paid spend on nightly** | OpenRouter/Haiku killed on Studio nightly + dreamcatcher | ✅ BIN-36 / HAB-50 |

**Promotion rule:** Items 1–5 and 7 + 9 must be ✅. Item 8 is strongly preferred but Multica-only is acceptable if Linear remains operator-MCP-only. Item 6 is a final human gut-check (now green).

**Why flip stays gated tonight:** #9 dual-home not fully synced yet; broader “battle-test against live multibrain stores” still open per `AGENTS.md`.

## Dual-home package sync

| Home | Role until promotion |
|------|----------------------|
| `~/Developer/multibrain` | Fleet SoT, health, nightly, MemoryKit proofs (`Packages/MemoryKit/PROOFS/`) |
| `~/Developer/Andromeda` | Product / control-plane (Swift UI, capability surface, eventual primary MemoryKit consumer) |
| `~/Developer/multibrain-bar` | Floating macOS client; path-depends on multibrain MemoryKit |

**Current drift (2026-07-15 residual):** Multibrain tip owns dotenv merge + LiveLinear (`LINEAR_LIVE=1` gate) after **#15** + readiness follow-up. Andromeda dual-home may still carry an older create-suite variant — rsync from fleet tip before marking #9 ✅.

**Sync procedure (when promoting or after MemoryKit PRs):**

```bash
# Preferred after fleet tip leads — multibrain → Andromeda
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
- Promoting on Visible Alpha narrative / video alone

## Next human actions (workspace flip)

1. Rsync MemoryKit multibrain → Andromeda and open dual-home parity PR until #9 is ✅.
2. Say the word to flip workspace defaults — agents will **not** do it unilaterally.
