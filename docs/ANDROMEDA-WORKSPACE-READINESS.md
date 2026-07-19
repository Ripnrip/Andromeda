# Andromeda Workspace Promotion Readiness

**Status:** GATED — do **not** force-move the Cursor workspace into Andromeda yet.  
**Date:** 2026-07-19 (HUD vault-true + e2e gates; checklist expanded; flip still GATED)  
**Locked decision:** dual-home until MemoryKit is battle-tested against live multibrain stores **and** the human says the word.  
**Linear / Multica:** BIN-39 / HAB-56 lineage — checklist items below; workspace flip **still GATED**.

## Executive answer (2026-07-19)

**When are we ready to migrate the Cursor workspace to Andromeda?**

| Gate | State | Notes |
|------|-------|-------|
| Memory battle-test checklist #1–#10 | ✅ | Visible Alpha + residual wave |
| Live vault recall (hot-empty → vault hits) | ✅ | `RetrievalServiceVaultLiveTests` + rebuilt HUD |
| Hermetic HUD e2e (store→recall→render) | ✅ | `HUDRecallE2ESnapshotTests` on Andromeda PR #10 |
| CI e2e gates | ✅ wired | Andromeda PR #9/#10 (nested MemoryKit + named filters) |
| Multibrain dual-home tip on `main` | ✅ | `b73bc2b` (fleet-observe + PROOFS 31–43) |
| Andromeda HUD+Home SoT on `main` | 🚧 | **Merge [PR #10](https://github.com/Ripnrip/Andromeda/pull/10)** first |
| CloudKit GUI smoke | 🚧 human | PROOF 43 agent smoke only (BIN-79) |
| Human word to flip | ❌ | Agents will **not** flip unilaterally |

**Bottom line:** MemoryKit is battle-tested enough for a **product** flip. You are **one merge + one explicit “flip it”** away from making `~/Developer/Andromeda` the default app workspace. Stay in multibrain for fleet/nightly/PROOFS until then (and keep fleet SoT there even after flip).

**Recommended flip sequence (when you say the word):**
1. Merge Andromeda PR #10 (and close PR #9 as superseded).
2. Rsync/pin MemoryKit dual-home SHA (multibrain `main` ↔ Andromeda `main`).
3. Open Cursor on `~/Developer/Andromeda` as default; keep multibrain open for fleet ops or as a second root.
4. Optional: 2–3 days HUD dogfood on live vault before declaring dual-home “write-primary” Andromeda.

## Visible Alpha closeout (2026-07-15 evening)

Tonight closed the **Visible Alpha** capability curtain as a visible chapter — not a workspace promotion:

- E2E bar smoke **PASS** (proof 32): `MemoryBridgeE2ESmokeTests` 3/3; bar remembers via MemoryKit.
- Live `project.state` → Multica **PASS** (proof 33); Multica live green.
- Live `project.state` → Linear **PASS** via dotenv + `LINEAR_LIVE=1` (`LiveLinearProjectStateTests`).
- Canonical Studio hot store **PASS** (proof 34): `~/.multibrain/anima-hot.store` store→seal→recall.
- Dotenv + `LINEAR_LIVE` gate + proof 34 synced Andromeda ← multibrain tip; readiness checklist **#9 ✅**.
- Autocache gateway + MemoryKit UI wave already on Andromeda main.

**Flip remained gated.** Checklist progress ≠ default Cursor workspace promotion.

## HUD vault-true wave (2026-07-18→19)

- Stale AndromedaHUD binary (hot-store-only) returned empty for `"cloak"` while vault had matches — rebuilt via `scripts/install-and-sign.sh hud`.
- Live vault regression: hot=0, vaultHitCount=12, `degraded=false` (`RetrievalServiceVaultLiveTests` in both homes).
- Hermetic e2e: real submit pipeline → pixel baselines (`Dark_E2E_Recalled` / `Dark_E2E_Empty`).
- Dirty trees reconciled: Andromeda → clean PR #10; multibrain → committed `b73bc2b` + planning docs this session.

## What “memory battle-tested live” means

All of the following must be green before promoting Andromeda as the default app workspace:

| # | Criterion | Evidence / how to prove | Status (2026-07-19) |
|---|-----------|-------------------------|---------------------|
| 1 | **E2E bar smoke green** | `MemoryBridgeE2ESmokeTests` 3/3; proof `Packages/MemoryKit/PROOFS/32-bar-e2e-smoke.md` | ✅ PASS |
| 2 | **store → Merkle seal → recall** on Studio hot path | CaptureService default `AnimaLedger` + bar MemoryBridge | ✅ PASS |
| 3 | **journal / session_dump path** | Bar journal verb → hot store → recall | ✅ PASS |
| 4 | **Materializer fail-open** | Obsidian materializer errors must not block hot `store_memory` return | ✅ by design |
| 5 | **Indexes fail-open** | Qdrant / Ladybug down ⇒ recall still serves hot (vault degraded OK) | ✅ by design |
| 6 | **Canonical Studio store smoke** | One store/recall against `~/.multibrain/anima-hot.store` | ✅ PASS — proof 34 |
| 7 | **`project.state` live Multica** | `MULTICA_LIVE=1` list/create; proof 33 | ✅ PASS |
| 8 | **`project.state` live Linear** | Dotenv + `LINEAR_LIVE=1` suite | ✅ PASS |
| 9 | **Dual-home MemoryKit sync** | Andromeda `Packages/MemoryKit` matches multibrain tip | ✅ PASS at tip; re-pin after PR #10 merge |
| 10 | **No paid spend on nightly** | OpenRouter/Haiku killed on Studio nightly + dreamcatcher | ✅ BIN-36 / HAB-50 |
| 11 | **Live vault fallback** | Hot-empty recall still returns vault hits (`cloak` proof) | ✅ PASS — 2026-07-19 |
| 12 | **HUD e2e + CI gates** | Hermetic store→recall→render + named CI steps | ✅ wired (land on Andromeda `main` with PR #10) |

**Promotion rule:** Items 1–5, 7, 9–12 must be ✅ on **merged** Andromeda `main`. Item 8 preferred. Item 6 is a final human gut-check (green). Then **human says the word**.

**Why flip stays gated tonight:** Checklist is green in dual-home + PR #10, but Andromeda `main` does not yet carry HUD SoT / e2e / CI until PR #10 merges, and agents do not flip Cursor roots unilaterally.

## Dual-home package sync

| Home | Role until promotion | Role after promotion |
|------|----------------------|----------------------|
| `~/Developer/multibrain` | Fleet SoT, health, nightly, MemoryKit proofs | **Still** fleet/nightly/PROOFS SoT |
| `~/Developer/Andromeda` | Product / control-plane (Swift UI, HUD, Home) | **Default app / Cursor workspace** |
| `~/Developer/multibrain-bar` | Floating macOS client; path-depends on MemoryKit | Slim bar; HUD owns daily recall surface |

**Current tips (2026-07-19):**
- multibrain `main`: `b73bc2b` (fleet-observe + proofs) + planning-doc commit this session
- Andromeda promote branch: `feat/andromeda-hud-core-promote` (PR #10) — merge before flip

**Sync procedure (when promoting or after MemoryKit PRs):**

```bash
# Preferred after fleet tip leads — multibrain → Andromeda
rsync -a --delete --exclude '.build' --exclude '.swiftpm' \
  ~/Developer/multibrain/Packages/MemoryKit/ \
  ~/Developer/Andromeda/Packages/MemoryKit/
# Then PR in Andromeda with proof note + SHA pin
```

Do **not** flip the Cursor workspace root to Andromeda until the checklist above is signed off **and** the human says the word.

## Explicit non-goals

- Forcing Cursor / agent default cwd into Andromeda without the human word
- Exposing Linear / Multica / n8n brands in client menus
- Declaring battle-tested because unit tests alone are green
- Promoting on Visible Alpha narrative / video alone
- Abandoning multibrain as fleet SoT after the app-workspace flip

## Next human actions (workspace flip)

1. ~~Rsync MemoryKit until #9 is ✅~~ — done 2026-07-16; re-landed 2026-07-19 on multibrain `main`.
2. **Merge Andromeda PR #10**; close PR #9 as superseded.
3. Optional: BIN-79 CloudKit GUI smoke (does not block app-workspace flip).
4. **Say the word** to flip workspace defaults — agents will **not** do it unilaterally.
