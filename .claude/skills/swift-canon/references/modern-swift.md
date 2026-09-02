# Modern Swift — 6.0 → 6.2 additions

Canon for the features that landed after most existing docs were written. Use these before reaching for older idioms they replace.

## Typed throws (SE-0413, Swift 6.0)

```swift
enum RetainError: Error, Sendable { case unauthorized, malformedPayload, enqueueFailed(String) }

func retain(_ record: OutboxRecord) throws(RetainError) { … }
```

- **Where:** vendored clients, contract surfaces (routers, bridges, parsers) where callers can and should `switch` on failure.
- **Where not:** app-edge glue — plain `throws` keeps ergonomics; don't force typed throws up through UI layers.

## Mutex / Atomic (Synchronization, Swift 6)

```swift
final class Counter: Sendable {
    private let count = Mutex(0)
    func increment() -> Int { count.withLock { $0 += 1; return $0 } }
}
```

- Replaces every hand-rolled `NSLock`/`os_unfair_lock` wrapper class.
- `Mutex` gives value-in/value-out `withLock` — no escaping the lock scope, no re-entrancy footguns.
- `Atomic<Value>` for counters/flags read on hot paths.

## @concurrent + isolation modernization (Swift 6.2)

```swift
@concurrent
func hashPayload(_ data: Data) -> String { /* CPU-bound */ }
```

- `@concurrent` moves the *function* off the caller's executor — the modern replacement for `Task.detached` in most cases.
- 6.2 also made `Task { }` bodies default to the surrounding isolation: if you still write `Task.detached` ask why, and prefer `@concurrent` helpers.
- `nonisolated(nonsending)` (6.0) for sync helpers that stay on the caller's executor — right default for cheap pure functions.

## AsyncStream.makeStream() (SE-0388)

```swift
let (stream, continuation) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .unbounded)
```

- One expression instead of the continuation-then-wrap dance. Use for bridging delegates/callbacks.

## Span / RawSpan (SE-0467, Swift 6.2) — systems code only

- Lifetime-scoped non-owning views over memory for parsers/interop; reaches for `UnsafeBufferPointer` far less often.
- Don't introduce in app-level code; it's for hot paths and binary formats.

## What this replaces (do not write these in new code)

| Old idiom | Modern replacement |
|---|---|
| `Task.detached { }` for CPU work | `@concurrent func` + normal `await` |
| Hand-rolled lock class | `Mutex` / `Atomic` |
| Callback → continuation dance | `AsyncStream.makeStream` |
| Stringly error enums at contract boundaries | `throws(TypedError)` |
