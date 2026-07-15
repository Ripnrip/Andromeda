# Task 1 Proof — SwiftData Hot Store (`AnimaEpisodicRecord`)

**Status:** PASS  
**Date:** 2026-07-15  
**Branch:** `anima-memory`  
**Spec:** `docs/DATA-CONTRACTS.md` §12  
**Package:** `Packages/MemoryKit`

## What was proven

1. **`AnimaEpisodicRecord` SwiftData `@Model`** exists with unique `id` + `contentHash`, visibility, provenance, tags, and nullable `materializedPath`.
2. **Actor-isolated `SwiftDataContainer` (`ModelActor`)** creates in-memory / on-disk containers and performs explicit ACID `insert` / `fetch` / `update` / `delete` via `ModelContext.save()` (autosave disabled).
3. **Round-trip store/recall** works for private visibility + provenance + content hash.
4. **Uniqueness guard** (`checkUniqueHash: true`) throws `AnimaStorageError.duplicateContentHash` on duplicate hash.
5. **Hot-path boundary:** `SwiftDataContainer.insert` only touches local SwiftData. It does **not** call Obsidian writers, `QdrantIndexer`, or `LadybugIndexer`. After insert, `materializedPath` remains `nil` (cold projection not invoked). Documented in `testTask1HotStoreProofHarness`.

## Commands run

```bash
cd /Users/admin/Developer/multibrain/Packages/MemoryKit
swift test --filter SwiftDataStoreTests
```

Swift: Apple Swift 6.2 (`swiftlang-6.2.0.19.9`), target `arm64-apple-macosx26.0`.

## Test output summary

| Result | Count |
|--------|------:|
| PASS   | 9 |
| FAIL   | 0 |

Suite: `🔮 The Sacred Vault Testing Rituals` — **passed** (~0.036s runtime after build).

Covered cases:

- Insertion & retrieval (id + contentHash)
- Unique constraint check (`checkUniqueHash`)
- Native upsert (same id/hash, `checkUniqueHash: false`)
- Selective filters (project / agent / visibility)
- Update + delete + clearAll
- Concurrent 50-write / 50-read stress
- **Task1 proof harness** (private + provenance + unique + no cold-path side effects)

## Evidence artifacts

- Log: `/tmp/memorykit-swiftdata-proof.log` (local machine capture)
- Proof harness: `Tests/MemoryKitTests/SwiftDataStoreTests.swift` → `testTask1HotStoreProofHarness`
- Sources:
  - `Sources/MemoryKit/Models/AnimaEpisodicRecord.swift`
  - `Sources/MemoryKit/Storage/SwiftDataContainer.swift`

## Remaining gaps / stubs

- No end-to-end `store_memory` MCP/tool façade wired yet — proof is container-level, not product API.
- Merkle seal on insert is **not** asserted here (seal lives in Crypto; Task 1 scope is hot store txn).
- Cold path (Obsidian materialization, Qdrant/Ladybug upsert) is intentionally **out of band**; indexers exist as separate stubs/modules and are not invoked from `SwiftDataContainer`.
- Spec sketch marks `@Model` as `Sendable`; as-built uses `@Model` class + `AnimaEpisodicRecordSnapshot: Sendable` for actor boundaries (preferred under Swift 6).
- Andromeda mirror: synced when feasible on same branch (see commit notes).
