# Andromeda Workspace Promotion Readiness

**Status:** GATED — **NO-GO** — do **not** force-move the Cursor workspace into Andromeda yet.  
**Date:** 2026-07-19 (adversarial milestone audit PROOF 44; flip still NO-GO)  
**Locked decision:** dual-home until MemoryKit is battle-tested against live multibrain stores **and** the human says the word.  
**Install policy (locked 2026-07-19):** Andromeda install / sign / LaunchAgent deploy is **ALL SWIFT** (`andromeda-install`) — **no Bash exception**; hybrid rejected. See BIN-101 + PROOF 44.  
**Linear / Multica:** BIN-39 / HAB-56 lineage + BIN-101 / PROOF 44 — checklist items below; workspace flip **still NO-GO**.

## Executive answer (2026-07-19)

**When are we ready to migrate the Cursor workspace to Andromeda?**

| Gate | State | Notes |
|------|-------|-------|
| Adversarial audit (PROOF 44) | ❌ NO-GO | 15+10 lanes; hard blockers listed in proof |
| Memory battle-test checklist #1–#12 | ⚠️ overclaimed | Local/PR tip greens ≠ merged main; see PROOF 44 table A |
| Live vault recall (hot-empty → vault hits) | ⚠️ | Local proof real; CI does not gate |
| Hermetic HUD e2e (store→recall→render) | ⚠️ | Hot hermetic only on PR #10; not live vault/boot |
| CI e2e gates | ❌ | Theater / soft-skips; PR #10 GHA red |
| Multibrain dual-home tip on `main` | ⚠️ | tip↔PR10 identical; Andromeda `main` ~42 files behind |
| Andromeda HUD+Home SoT on `main` | ❌ | **Do not merge [PR #10](https://github.com/Ripnrip/Andromeda/pull/10)** until CI green |
| Swift-native install (BIN-101) | ❌ Todo | Replace `install-and-sign.sh`; no bash exception |
| CloudKit GUI smoke | 🚧 human | PROOF 43 honesty OK; BIN-79 does **not** block flip |
| Human word to flip | ❌ | Agents will **not** flip unilaterally |

**Bottom line:** Flip is **NO-GO**. Adversarial audit (PROOF 44) found premature greens, curtain leaks, spend/secrets issues, and red PR #10 CI. Stay in multibrain for fleet/nightly/PROOFS until hard blockers clear **and** the human says the word.

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
2. **Do not merge Andromeda PR #10** until GHA is green (snapshots + flakes); then merge and close PR #9 as superseded.
3. Clear PROOF 44 hard blockers (curtain scrub, Letta/Home spend, live-vault CI gate, checklist #13–#20, status honesty).
4. Land BIN-101 Swift-native `andromeda-install`; delete `install-and-sign.sh` (no bash exception).
5. Optional: BIN-79 CloudKit GUI smoke (does not block app-workspace flip).
6. **Say the word** to flip workspace defaults — agents will **not** do it unilaterally.
