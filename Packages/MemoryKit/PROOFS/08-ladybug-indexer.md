# Task 8 Proof — LadybugIndexer (`:8286` async upsert)

**Status:** PASS  
**Date:** 2026-07-15  
**Branch:** `anima-memory`  
**Spec:** `docs/DATA-CONTRACTS.md` §13  
**Package:** `Packages/MemoryKit`

## What was proven

1. **Async upsert to Ladybug `:8286`** — `LadybugIndexer` defaults to `http://127.0.0.1:8286` and PUTs nodes to `/nodes` and edges to `/edges` (idempotent upsert, not fire-and-forget POST insert).
2. **`content_hash` → deterministic `point_id`** — `UUID.deterministic(from:)` (truncated SHA-256 → UUID) is the point ID; duplicate upserts reuse the same `point_id` (no node duplication).
3. **Thin metadata only** — payload encodes exactly §13 fields (`content_hash`, `visibility`, `project`, `date`, `tags`, `source_path`) with snake_case keys; node encodes `point_id`; narrative/body/`content` never appear.
4. **Fail-open** — network errors and HTTP 5xx return `false`, set `isDirty = true`, and never throw/halt the caller.
5. **Dirty purification** — `resetDirty()` clears the stale flag after a rebuild/repair ritual.

## Commands run

```bash
# Isolated package (Indexing/Ladybug only) to avoid parallel-agent WIP compile collisions
cd /tmp/memorykit-ladybug-isolate
swift test --filter LadybugIndexerTests \
  --scratch-path /tmp/mk-ladybug-scratch2 \
  --cache-path /tmp/mk-ladybug-cache2
```

Swift: Apple Swift 6.2 (`swiftlang-6.2.0.19.9`), target `arm64-apple-macosx14.0`.

## Test output summary

| Result | Count |
|--------|------:|
| PASS   | 11 |
| FAIL   | 0 |

Suite: `LadybugIndexer Tests 🐞🧪` — **passed** (~0.097s runtime after build).

Covered cases:

| Test | Proves |
|------|--------|
| `Test deterministic UUID generation` | identical hashes → identical UUIDs |
| `Test default base URL targets Ladybug :8286` | hub port contract |
| `Test thin payload + point_id JSON formatting` | §13 snake_case + no heavy body |
| `Test successful node upsert` | PUT `/nodes` + thin body |
| `Test duplicate upsert is idempotent by content_hash` | same `point_id` on re-upsert |
| `Test successful connection upsert` | PUT `/edges` |
| `Test node upsert under network storm (Fail-Open)` | no throw; `isDirty` |
| `Test connection upsert under server error (Fail-Open)` | HTTP 500 → fail-open |
| `Test high-level index and connect convenience methods` | `index` / `connect` wrappers |
| `Test dirty state purification` | `resetDirty()` |
| `Task 8 proof harness — content_hash IDs, thin meta, fail-open` | end-to-end §13 ritual |

## Evidence artifacts

- Log: `/tmp/memorykit-ladybug-proof.log`
- Tests: `Tests/MemoryKitTests/LadybugIndexerTests.swift`
- Source: `Sources/MemoryKit/Indexing/LadybugIndexer.swift`

## Hardening applied this pass

- `LadybugNode` CodingKeys → `point_id` (was camelCase `pointId`)
- Node/edge HTTP method → `PUT` (upsert semantics)
- MockURLProtocol materializes `httpBody` from `httpBodyStream` (URLSession stream quirk)
- Unique mock ports per test (Swift Testing parallel collision fix)
- Proof harness + thin-payload / idempotency coverage

## Remaining gaps / stubs

- Live Ladybug serve (`bin/index_ladybug.py --serve`) today exposes `/health` + `/query` only — `/nodes` and `/edges` upsert routes are the Anima client contract for materialization-time cache writes (Python server upsert surface still TBD).
- Not wired into Dream/materializer yet (async-at-materialization call site is a later integration task).
- Andromeda mirror: synced on same branch for this milestone.
