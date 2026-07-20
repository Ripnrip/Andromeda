# Proof — Phase 2 E2E bar ↔ MemoryKit smoke (BIN-30 / BIN-38 follow-up)

**Status:** PASS  
**Date:** 2026-07-15  
**Repos:** multibrain-bar `main` @ `4e3db35` + local MemoryKit path `../multibrain/Packages/MemoryKit`  
**Capability IDs:** `memory.recall` · `memory.store` · `memory.journal` / `memory.session_dump`  
**Linear:** BIN-30 / BIN-38 follow-up  
**Multica:** HAB-44 / HAB-53

## What was proven

1. **macOS bar builds** — `swift build --product MultibrainBar` succeeds (MemoryKit local path).
2. **Live MemoryBridge path** — boots on-disk SwiftData hot store, dispatches palette verbs through `CaptureService` + `RetrievalService` (same path as the floating bar UI).
3. **store → seal → recall** — unique narrative stores, AnimaLedger seals (`MEMORY SEALED!`), recall returns 1 hot hit containing the smoke token.
4. **journal / session-dump** — journal verb stores with journal tags; recall finds the token.
5. **Merkle chain verify** — `CaptureService` default ledger (`AnimaLedger()`) seals; `verifySealChain()` succeeds after store (same default the bar's `MemoryBridge` uses).

## Commands run

```bash
cd ~/Developer/multibrain-bar
swift build --product MultibrainBar
swift test --filter MemoryBridgeE2ESmokeTests
```

Swift: Apple Swift 6.2, target `arm64-apple-macosx14.0`.

## Test output summary

| Test | Result |
|------|--------|
| store → recall round-trip (MemoryBridge) | PASS |
| journal → recall | PASS |
| Merkle seal + verifySealChain | PASS |
| **Suite** | **3/3 PASS** (~0.163s) |

Log excerpt (store+seal+recall):

```
🛡️ ✨ MEMORY SEALED! seal=d040648b1916af5b…
🎉 ✨ STORE COMPLETE id=17FC36DD
🎪 📦 Hot store returned 1 glowing neurons
🎉 ✨ RECALL COMPLETE hits=1 degraded=false
```

## Evidence artifacts

- Tests: `multibrain-bar/Tests/MultibrainBarTests/MemoryBridgeE2ESmokeTests.swift`
- Bridge: `multibrain-bar/Sources/MultibrainBarCore/Services/MemoryBridge.swift`
- Log: `/tmp/bar-e2e-smoke.log`
- This proof: `Packages/MemoryKit/PROOFS/32-bar-e2e-smoke.md` (mirror) + `multibrain-bar/PROOFS/32-bar-e2e-smoke.md`

## Notes / residual

- Smoke uses **temp** SwiftData stores (does not mutate `~/.multibrain/anima-hot.store`) — same APIs as production bridge init.
- **No UI automation** (no XCUITest / Accessibility drive of the floating window). Automated path covers the MemoryBridge service the UI calls; human palette click is optional confirmation.
- Vault ripgrep fallback returned 0 hits (expected for unique smoke tokens not materialized to Obsidian yet).
- Indexes (Qdrant/Ladybug) intentionally not on the hot path — fail-open by design.

## Blockers

**None for this smoke.** Ready to mark Phase-2 E2E bar smoke green.
