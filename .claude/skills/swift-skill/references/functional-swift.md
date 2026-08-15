# Functional Swift

Pure core, imperative shell. Business rules as testable functions; I/O at client/effect edges.

## Principles

1. **Immutable data** — `let`, value types, `Sendable` structs
2. **Pure transforms** — no I/O, no globals, no `Date()` unless injected
3. **Total functions** — `Result` or optional over force-unwrap
4. **Composition** — small functions, explicit pipelines

## Layout

```
Feature/
├── Models/
├── Transform/     # pure only — no SwiftUI, no network
├── Clients/       # effects
└── UI/ or TCA/
```

## Patterns

```swift
// Pure
public func deriveStatus(from input: Input) -> Output { … }

// Shell (reducer effect, client method)
return .run { send in
    let raw = try await client.fetch()
    let derived = deriveStatus(from: raw)
    await send(.derived(derived))
}
```

## Collections

```swift
Dictionary(grouping: items, by: \.key)
items.filter { … }.map { … }
// Prefer declarative over mutable loops when clearer
```

## Result

```swift
public func decode<T: Decodable>(_ type: T.Type, from data: Data) -> Result<T, DecodeError> {
    Result { try JSONDecoder().decode(type, from: data) }
        .mapError { _ in .invalidData }
}
```

## Testing

Pure functions: `#expect` only — no mocks.

## Anti-patterns

- Side effects in `map`
- God functions > ~40 lines
- Mutable singletons for domain state
