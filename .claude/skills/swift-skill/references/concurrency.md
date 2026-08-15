# Concurrency — Swift 6

## Defaults

- Swift 6 language mode, `StrictConcurrency` enabled
- `@MainActor` for UI mutation and `@Observable` UI stores
- `Sendable` for types crossing tasks/reducers/effects

## Patterns

### AsyncStream (preferred for streams)

```swift
public var events: @Sendable () async -> AsyncStream<Event>

// consume
for await event in await client.events() {
    await handle(event)
}
```

### Task groups (parallel I/O)

```swift
await withTaskGroup(of: Result.self) { group in
    for url in urls { group.addTask { await fetch(url) } }
    for await result in group { … }
}
```

### Actor for shared mutable state

```swift
actor Cache {
    private var store: [String: Data] = [:]
    func get(_ key: String) -> Data? { store[key] }
}
```

## Rules

| Do | Don't |
|----|-------|
| Snapshot DTOs across boundaries | Pass `@Model` / `ObservableObject` into `.run` |
| `[client]` capture in effects | Implicit self capture |
| `Task { @MainActor in … }` from callbacks | Mutate UI from background |
| Cancel with `Task.isCancelled` | Fire-and-forget tasks in views |

## @Model / SwiftData

`@Model` stays MainActor — project to `Sendable` snapshot before TCA/network.

## Compiler

```swift
swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
```
