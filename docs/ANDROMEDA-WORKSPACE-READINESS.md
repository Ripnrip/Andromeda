# Andromeda Workspace Promotion Readiness

**Status:** GATED — do **not** force-move the Cursor workspace into Andromeda yet.  
**Date:** 2026-07-16 (dual-home MemoryKit sync closed — #9 ✅; flip still GATED)  
**Locked decision:** dual-home until MemoryKit is battle-tested against live multibrain stores.  
**Linear / Multica:** BIN-39 / HAB-56 — checklist #9 dual-home MemoryKit is ✅; workspace flip **still GATED** until the human says the word.

## Visible Alpha closeout (2026-07-15 evening)

Tonight closed the **Visible Alpha** capability curtain as a visible chapter — not a workspace promotion:

- E2E bar smoke **PASS** (proof 32): `MemoryBridgeE2ESmokeTests` 3/3; bar remembers via MemoryKit.
- Live `project.state` → Multica **PASS** (proof 33); Multica live green.
- Live `project.state` → Linear **PASS** via dotenv + `LINEAR_LIVE=1` (`LiveLinearProjectStateTests`); smoke probes BIN-44…49 / HAB-67…69 cancelled after proof.
- Canonical Studio hot store **PASS** (proof 34): `~/.multibrain/anima-hot.store` store→seal→recall.
- Dotenv + `LINEAR_LIVE` gate + proof 34 synced Andromeda ← multibrain tip (`44bd6a3`); readiness checklist **#9 ✅**.
- Autocache gateway + MemoryKit UI wave already on Andromeda main.

**Flip remains gated.** Checklist progress ≠ default Cursor workspace promotion.

## What “memory battle-tested live” means

All of the following must be green before promoting Andromeda as the default app workspace:

| # | Criterion | Evidence / how to prove | Status (2026-07-16) |
|---|-----------|-------------------------|-------------------------|
| 1 | **E2E bar smoke green** | `MemoryBridgeE2ESmokeTests` 3/3; proof `Packages/MemoryKit/PROOFS/32-bar-e2e-smoke.md` | ✅ PASS |
| 2 | **store → Merkle seal → recall** on Studio hot path | CaptureService default `AnimaLedger` + bar MemoryBridge | ✅ PASS (temp stores; same APIs) |
| 3 | **journal / session_dump path** | Bar journal verb → hot store → recall | ✅ PASS |
| 4 | **Materializer fail-open** | Obsidian materializer errors must not block hot `store_memory` return | ✅ by design (hot path isolated); live Dream pass still fleet ops |
| 5 | **Indexes fail-open** | Qdrant / Ladybug down ⇒ recall still serves hot (vault degraded OK) | ✅ by design; optional Studio chaos check residual |
| 6 | **Canonical Studio store smoke** | One store/recall against `~/.multibrain/anima-hot.store` (not only temp) | ✅ PASS — store exists; proof `Packages/MemoryKit/PROOFS/34-canonical-hot-store-smoke.md` (bar mirror `multibrain-bar/PROOFS/34-…`) |
| 7 | **`project.state` live Multica** | `MULTICA_LIVE=1` list/create; proof `Packages/MemoryKit/PROOFS/33-project-state-live-bridge.md` | ✅ PASS |
| 8 | **`project.state` live Linear** | Dotenv + `LINEAR_LIVE=1` suite | ✅ PASS — `LINEAR_LIVE=1 swift test --filter LiveLinearProjectStateTests` green via `~/Developer/multibrain/.env` (key never logged); proof 33 Linear section |
| 9 | **Dual-home MemoryKit sync** | Andromeda `Packages/MemoryKit` matches multibrain tip used by bar | ✅ PASS — rsync multibrain→Andromeda; drift 4→0; fleet SoT `44bd6a3`; flip still GATED |
| 10 | **No paid spend on nightly** | OpenRouter/Haiku killed on Studio nightly + dreamcatcher | ✅ BIN-36 / HAB-50 |

**Promotion rule:** Items 1–5 and 7 + 9 must be ✅. Item 8 is strongly preferred but Multica-only is acceptable if Linear remains operator-MCP-only. Item 6 is a final human gut-check (now green).

**Why flip stays gated:** Checklist #9 is ✅, but broader "battle-test against live multibrain stores" remains open per `AGENTS.md`. Agents will **not** flip the Cursor workspace until the human says the word.

## Dual-home package sync

| Home | Role until promotion |
|------|----------------------|
| `~/Developer/multibrain` | Fleet SoT, health, nightly, MemoryKit proofs (`Packages/MemoryKit/PROOFS/`) |
| `~/Developer/Andromeda` | Product / control-plane (Swift UI, capability surface, eventual primary MemoryKit consumer) |
| `~/Developer/multibrain-bar` | Floating macOS client; path-depends on multibrain MemoryKit |

**Current drift (2026-07-16):** **0** meaningful files (ex `.build` / `.DS_Store`). Andromeda MemoryKit matches multibrain `origin/main` `44bd6a3` (`44bd6a3e62383013232896436d675003fb9813a5`). Synced: proof 34, proof 33 Linear section, `linearKeyPresentFromEnvironment`, `LINEAR_LIVE=1` suite gate.

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

1. ~~Rsync MemoryKit multibrain → Andromeda until #9 is ✅~~ — done 2026-07-16 (drift 4→0).
2. Say the word to flip workspace defaults — agents will **not** do it unilaterally.
