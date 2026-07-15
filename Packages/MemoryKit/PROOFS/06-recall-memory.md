# Task 6 Proof — RetrievalService `recall_memory`

**Status:** PASS  
**Date:** 2026-07-15  
**Branch:** `anima-memory`  
**Package:** `Packages/MemoryKit`  
**Surface:** hot-store-first recall with optional vault ripgrep; never requires Qdrant/Ladybug

## What was proven

1. **Hot store first** — `RetrievalService.recallMemory` queries `SwiftDataContainer` with project / visibility / tags (conjunction) / date range / free-text filters before any vault IO.
2. **Injectable vault ripgrep** — `ProcessRunning` protocol + `MockProcessRunner` in tests; production default is `LocalProcessRunner`. Mock `--json` ripgrep output merges as `MemoryHit.source == .vault`.
3. **Graceful vault degradation** — missing vault path, nil vault URL, or runner failure sets `vaultDegraded=true` and still returns hot hits (success).
4. **Opt-out** — `includeVaultFallback=false` never invokes the process runner.
5. **No Qdrant/Ladybug dependency** — proof harness succeeds with a missing vault and zero process invocations; indexers are not imported or called from `RetrievalService`.
6. **Ranking** — hot-store hits rank above vault hits with comparable text (hot score bias +100).

## Commands run

```bash
# Isolated package snapshot (avoids parallel-agent .build / source races)
rsync -a --exclude '.build' Packages/MemoryKit/ /tmp/memorykit-recall-pkg/
# Keep only RetrievalServiceTests.swift in the snapshot test target
cd /tmp/memorykit-recall-pkg
swift test --filter RetrievalServiceTests \
  --scratch-path /tmp/memorykit-recall-scratch2 \
  --cache-path /tmp/memorykit-recall-cache
```

Swift: Apple Swift 6.2 (`swiftlang-6.2.0.19.9`), target `arm64-apple-macosx26.0`.  
Log: `/tmp/memorykit-recall-proof.log`

## Test output summary

| Result | Count |
|--------|------:|
| PASS   | 11 |
| FAIL   | 0 |

Suite: `🔍 The Recall Memory Retrieval Rituals` — **passed** (~0.091s runtime after build).

```
Test run with 11 tests in 1 suite passed after 0.091 seconds.
```

Covered cases:

| Test | Proves |
|------|--------|
| Hot store structured filters | project + visibility + tags + date |
| Tag conjunction | all listed tags required |
| Date range | out-of-window excluded |
| Vault ripgrep merge | mock `rg --json` → vault hits |
| Missing vault degrade | success + `vaultDegraded` |
| Nil vault URL degrade | no process invocation |
| Ripgrep runner failure | fail-open to hot hits |
| Vault fallback opt-out | runner never called |
| Empty query throws | `RetrievalServiceError.emptyQuery` |
| Task6 proof harness | hot filters + degrade; no vectors |
| Hot ranks above vault | score ordering |

## Evidence artifacts

- Log: `/tmp/memorykit-recall-proof.log`
- Sources: `Sources/MemoryKit/Services/RetrievalService.swift`
- Tests: `Tests/MemoryKitTests/RetrievalServiceTests.swift`
- Proof harness: `testTask6RecallMemoryProofHarness`

## Remaining gaps / stubs

- Live `rg` binary path defaults to `/opt/homebrew/bin/rg` (injectable); not exercised with a real vault in this suite (mock runner only).
- Vector backends (Qdrant/Ladybug) intentionally absent from this path — optional boost is a later integration.
- Andromeda mirror: synced on same branch for this milestone.
