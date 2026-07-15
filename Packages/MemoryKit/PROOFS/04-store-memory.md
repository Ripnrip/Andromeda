# Task 4 Proof — Transactional `store_memory` (`CaptureService`)

**Status:** PASS  
**Date:** 2026-07-15  
**Branch:** `anima-memory`  
**Spec:** `docs/DATA-CONTRACTS.md` §12  
**Package:** `Packages/MemoryKit`

## What was proven

1. **`CaptureService.storeMemory`** computes deterministic `content_hash` (`sha256:<hex>`) from the narrative via CryptoKit SHA-256.
2. **Hot ACID insert** lands in `SwiftDataContainer` with uniqueness enforced (`checkUniqueHash: true`); returns `MemoryID` immediately.
3. **Optional AnimaSeal** — when an `AnimaLedger` is injected, each capture appends a sealed `AnimaBlock`; `verifySealChain()` succeeds. When ledger is `nil`, capture still succeeds without sealing.
4. **Default visibility = `private`**; explicit overrides (`public` / `friends` / `internal`) are honored; unknown values fall back to `private`.
5. **Hot-path boundary:** `CaptureService` does **not** call Obsidian writers, `QdrantIndexer`, `LadybugIndexer`, or `CloudKitSyncEngine`. After store, `materializedPath` remains `nil`.

## Commands run

```bash
# Frozen package snapshot (avoids mid-build mutation by parallel Anima agents)
rsync -a --exclude '.build' Packages/MemoryKit/ /tmp/memorykit-capture-snap/
cd /tmp/memorykit-capture-snap
swift test --filter CaptureServiceTests \
  --scratch-path /tmp/memorykit-capture-scratch2 \
  --cache-path /tmp/memorykit-capture-cache
```

Swift: Apple Swift 6.2 (`swiftlang-6.2.0.19.9`), target `arm64-apple-macosx26.0`.

## Test output summary

| Result | Count |
|--------|------:|
| PASS   | 8 |
| FAIL   | 0 |

Suite: `📥 The Store Memory Capture Rituals` — **passed** (~0.039s runtime after build).

`Test run with 8 tests in 1 suite passed after 0.039 seconds.`

Covered cases:

| Test | Proves |
|------|--------|
| `🧮 content_hash is deterministic SHA-256 of the narrative` | hash stability + format |
| `📥 store_memory returns MemoryID immediately and persists the snapshot` | insert + round-trip |
| `🔒 Default visibility is private; override is honored` | default + override + fallback |
| `🛡️ AnimaSeal ledger appends and verifies after store_memory` | seal-on-write |
| `🌙 store_memory succeeds without a ledger (seal optional)` | seal-if-available |
| `🌩️ Empty narrative is rejected before any insert` | fail closed on blank |
| `🛡️ Duplicate narrative content_hash is rejected` | uniqueness |
| `🧾 Task4 Proof Harness` | end-to-end hot path + no cold side effects |

## Evidence artifacts

- Log: `/tmp/memorykit-capture-proof.log` (local machine capture)
- Proof harness: `Tests/MemoryKitTests/CaptureServiceTests.swift` → `testTask4StoreMemoryProofHarness`
- Sources:
  - `Sources/MemoryKit/Services/CaptureService.swift`

## Remaining gaps / stubs

- No MCP/tool façade for `store_memory` yet — this is the in-process CaptureService API.
- Recall path (`recall_memory`) is a separate task; CaptureService is write-only.
- Cold path (Obsidian materialization, Qdrant/Ladybug upsert, CloudKit) remains intentionally out of band.
- Andromeda mirror: synced when feasible on same branch.
