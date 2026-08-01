# Andromeda Runtime v2 Milestone 3 Implementation Plan

> **For agentic workers:** Implements MarkdownVaultProjection, QdrantProjection, durable JSONL retry queue, and wires them into `andromeda-runtime`.

**Goal:** Add Obsidian-compatible Markdown projection, Qdrant vector projection, durable retry, and composition-root wiring while keeping Swift 6 strict concurrency and zero warnings.

**Architecture:** Keep `AndromedaDomain` as the contract owner (`MemoryProjectionSink`, retry-queue protocol, embedding provider). `AndromedaProjections` owns the concrete sinks, deterministic embedding, and durable retry queue. `AndromedaMemory`'s `MemoryRuntime` enqueues projection failures. `AndromedaServer` composes real sinks at startup.

**Tech Stack:** Swift 6.1, strict concurrency, macOS 14, URLSession, no new third-party dependencies.

## Global Constraints

- Swift 6 language mode, strict concurrency, zero warnings.
- macOS 14 deployment target.
- No new third-party dependencies (URLSession is allowed).
- Do not touch targets `AndromedaHome`, `AndromedaHUD`, `AndromedaAutoCache`, `AndromedaGateway`, `AndromedaCLI`, or `DashboardRoute.swift`.
- Do not modify existing behavior of Memory recall/privacy/idempotency.
- Private memories must not reach the Markdown vault or Qdrant.

## File Structure

### New files

- `Sources/AndromedaDomain/EmbeddingProvider.swift` — `EmbeddingProvider` protocol + deterministic hash bag-of-words contract.
- `Sources/AndromedaDomain/MemoryProjectionRetryQueue.swift` — `MemoryProjectionRetryQueue` protocol so `AndromedaMemory` can enqueue failures without depending on `AndromedaProjections`.
- `Sources/AndromedaProjections/MarkdownVaultProjection.swift` — `MarkdownVaultProjection` actor implementing `MemoryProjectionSink`.
- `Sources/AndromedaProjections/QdrantProjection.swift` — `QdrantProjection` actor implementing `MemoryProjectionSink`.
- `Sources/AndromedaProjections/HashBagOfWordsEmbeddingProvider.swift` — deterministic 384-dim embedding, `Sendable`, no deps.
- `Sources/AndromedaProjections/DurableRetryQueue.swift` — JSONL retry queue (append enqueue, read-all retry, atomic truncate+rewrite after partial success).
- `Sources/AndromedaProjections/ProjectionRuntime.swift` (replace stub) — actor owning retry queue + sinks; exposes `enqueue(record:receipt:)`, `retryPending()`, and `snapshot()`.
- `Tests/AndromedaProjectionTests/MarkdownVaultProjectionTests.swift`
- `Tests/AndromedaProjectionTests/QdrantProjectionTests.swift`
- `Tests/AndromedaProjectionTests/DurableRetryQueueTests.swift`
- `Tests/AndromedaProjectionTests/HashEmbeddingTests.swift`

### Modified files

- `Sources/AndromedaMemory/MemoryRuntime.swift` — accept optional `retryQueue: (any MemoryProjectionRetryQueue)?`, enqueue `retryableFailure` receipts.
- `Sources/AndromedaServer/AndromedaRuntimeServer.swift` — accept `vaultDirectoryURL`, `qdrantBaseURL`, build real sinks, inject retry runtime into `MemoryRuntime`.
- `Sources/andromeda-runtime/main.swift` — add `--vault-dir` and `--qdrant-url` options with defaults.
- `Package.swift` — add `AndromedaMemory` dependency to `AndromedaProjections`; add `AndromedaProjectionTests` test target; add `Foundation` usage only where needed.

## Task 1: Extend domain contracts

**Files:**
- Create: `Sources/AndromedaDomain/EmbeddingProvider.swift`
- Create: `Sources/AndromedaDomain/MemoryProjectionRetryQueue.swift`

**Interfaces:**
- `EmbeddingProvider`: `var dimension: Int { get }; func embedding(for text: String) -> [Float]`
- `MemoryProjectionRetryQueue`: `func enqueue(record: MemoryRecord, receipt: MemoryWriteReceipt) async throws; func retryPending() async throws -> [RetryOutcome]`

**Outcome:** `AndromedaMemory` can depend on these protocols without importing `AndromedaProjections`.

## Task 2: MarkdownVaultProjection

**Files:**
- Create: `Sources/AndromedaProjections/MarkdownVaultProjection.swift`

**Behavior:**
- `sinkID = "memory.projection.markdown.vault"`, `schemaVersion = "memory.projection.markdown.v1"`.
- `accepts(_:)` returns `false` for `.private` privacy, `true` otherwise.
- `write(record:)` renders YAML front matter with `id`, `kind`, `privacy`, `tags`, `created`, `checksum`; body is `summary` then `content`; tags become Obsidian wiki-style `#tag` tokens at end of file.
- Filename: `<memoryID.description>.md`.
- Atomic write: write to `<filename>.<uuid>.tmp` then `FileManager.replaceItemAt(..., withItemAt: ...)`.
- Receipt: `.committed` / `.pending` as appropriate.

## Task 3: Deterministic embedding provider

**Files:**
- Create: `Sources/AndromedaProjections/HashBagOfWordsEmbeddingProvider.swift`

**Behavior:**
- `dimension = 384`.
- Tokenize text to lowercase alphanumeric terms.
- For each term, compute SHA256 hash, fold into 384 bits (6 64-bit chunks or 12 32-bit chunks), accumulate counts into 384 floats.
- L2-normalize the vector.
- Deterministic for identical input.

## Task 4: QdrantProjection

**Files:**
- Create: `Sources/AndromedaProjections/QdrantProjection.swift`

**Behavior:**
- `sinkID = "memory.projection.qdrant"`, `schemaVersion = "memory.projection.qdrant.v1"`.
- `accepts(_:)` returns `false` for `.private`.
- Collection name per project: `andromeda-memories-<projectID.description>` (skip if no projectID, return `.skipped`).
- Upsert payload: Qdrant point with `id = memoryID.description`, `vector = embedding`, payload includes `memory_id`, `kind`, `privacy`, `summary`, `content`, `tags`, `checksum`, `created_at`.
- Network errors / non-2xx → throw, `MemoryRuntime` maps to `.retryableFailure` receipt.
- Use `URLSession.shared` (configurable via initializer).

## Task 5: Durable JSONL retry queue + ProjectionRuntime

**Files:**
- Create: `Sources/AndromedaProjections/DurableRetryQueue.swift`
- Replace: `Sources/AndromedaProjections/ProjectionRuntime.swift`

**Behavior:**
- `PendingProjection` struct: `memoryRecord`, `receipt`, `enqueuedAt`.
- JSONL file: one JSON object per pending projection.
- `enqueue(record:receipt:)`: append a line.
- `retryPending()`: read all entries, attempt each sink, rewrite file keeping still-failed entries, return outcomes.
- `ProjectionRuntime` actor owns `[any MemoryProjectionSink]` and a `DurableRetryQueue`. Implements `MemoryProjectionRetryQueue`.
- On init, optionally load existing pending entries.

## Task 6: Wire MemoryRuntime to enqueue failures

**Files:**
- Modify: `Sources/AndromedaMemory/MemoryRuntime.swift`

**Behavior:**
- Add `retryQueue: (any MemoryProjectionRetryQueue)? = nil` parameter.
- After catching a sink error, still emit the `.retryableFailure` receipt in the response, but also call `await retryQueue?.enqueue(record: record, receipt: failureReceipt)`.

## Task 7: Composition root + CLI flags

**Files:**
- Modify: `Sources/AndromedaServer/AndromedaRuntimeServer.swift`
- Modify: `Sources/andromeda-runtime/main.swift`

**Behavior:**
- `AndromedaRuntimeServer.init(configuration:journalFileURL:operationalStoreURL:vaultDirectoryURL:qdrantBaseURL:logger:)` builds `MarkdownVaultProjection`, `QdrantProjection`, `ProjectionRuntime`, and injects into `MemoryRuntime`.
- Defaults: vault directory = `<journalFileURL.deletingLastPathComponent()>/vault`; Qdrant base URL = `http://localhost:6333`.
- `Serve` gets `--vault-dir` and `--qdrant-url` options.

## Task 8: Tests

**Files:**
- Create tests in `Tests/AndromedaProjectionTests/`.
- Modify: `Package.swift` to add test target.

**Test coverage:**
- Markdown front matter correctness.
- Private memory excluded from vault.
- Atomic write (temp file then final file).
- Embedding stability + dimension 384.
- Qdrant against live `localhost:6333` (skip with message if unreachable).
- Retry durability across restart (write queue, recreate runtime, retry flips receipt).
- Retry success flips receipt to `.committed`.
- End-to-end `remember` → markdown + qdrant receipts.

## Task 9: Verification

**Commands:**
- `swift build`
- `swift test --filter AndromedaProjectionTests`
- `swift test`

**Outcome:** Zero warnings, all tests pass (live Qdrant test may skip if unreachable).
