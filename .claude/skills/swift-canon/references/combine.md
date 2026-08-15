# Combine — Legacy Bridges

**Default: async/await + AsyncStream.** Use Combine for system publishers and legacy `ObservableObject` only.

## Bridge

```swift
extension Publisher where Failure == Never {
    func asyncStream() -> AsyncStream<Output> {
        AsyncStream { continuation in
            let c = sink { continuation.yield($0) }
            continuation.onTermination = { _ in c.cancel() }
        }
    }
}
```

## When to use

| Combine | async/await |
|---------|-------------|
| `NotificationCenter`, `Timer`, KVO | New clients, TCA effects |
| `URLSession.dataTaskPublisher` | `URLSession.shared.data(for:)` |
| Legacy `@Published` modules | New `@Observable` code |

## Operators

| Operator | Use |
|----------|-----|
| `map` / `compactMap` | transform before bridge |
| `removeDuplicates` | skip redundant UI updates |
| `debounce` | search fields |
| `switchToLatest` | cancel stale requests |

## Rules

- Confine Combine to **client layer**
- Expose `AsyncStream` or `async` methods outward
- No `AnyCancellable` in reducer `State`
- `@MainActor` subjects — bridge before TCA `.run`

## TCA

```swift
return .run { send in
    for await value in publisher.asyncStream() {
        await send(.updated(value))
    }
}.cancellable(id: CancelID.observer)
```
