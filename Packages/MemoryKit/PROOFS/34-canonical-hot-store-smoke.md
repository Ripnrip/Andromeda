# Proof 34 — Canonical Studio Hot Store (`~/.multibrain/anima-hot.store`)

**Status:** PASS  
**Date:** 2026-07-15  
**Repos:** multibrain-bar `MemoryBridgeCanonicalStoreSmokeTests` + MemoryKit path `../multibrain/Packages/MemoryKit`  
**Capability IDs:** `memory.store` · `memory.recall`  
**Readiness:** satisfies `docs/ANDROMEDA-WORKSPACE-READINESS.md` criterion **#6**  
**Bar mirror:** `~/Developer/multibrain-bar/PROOFS/34-canonical-hot-store-smoke.md`

## What was proven

1. Canonical path `~/.multibrain/anima-hot.store` **exists** on Studio and boots via `MemoryBridge()` default (no temp store).
2. Append-only `store` → Merkle seal → `recall` round-trip **PASS** with unique `PROOF34-CANONICAL-*` token.
3. No teardown — residue left for audit; prior memories undisturbed.

## Commands run

```bash
cd ~/Developer/multibrain-bar
swift test --filter CanonicalStoreSmoke
# log: /tmp/canonical-store-smoke.log
```

## Evidence

| Check | Result |
|-------|--------|
| Store file present | ✅ `~/.multibrain/anima-hot.store` |
| Boot / `isReady` | ✅ PASS |
| Store + seal | ✅ ID summary non-empty (example `8E6F7881`) |
| Recall by token | ✅ hot hit containing `PROOF34-CANONICAL-…` |
| Token (example) | `PROOF34-CANONICAL-D923FBA7-03F1-47E1-8FA7-74F66C611D76` |

## Safety notes

- Append-only — tests must **not** delete or reset the canonical store.
- No secrets in narrative; proof tokens are opaque UUID-tagged strings.
- Bar path-depends on multibrain MemoryKit; keep dual-home in sync before treating this as Andromeda-owned.

## Residuals

- Dual-home #9 still open until Andromeda MemoryKit matches multibrain tip.
- Workspace flip remains **GATED**.
