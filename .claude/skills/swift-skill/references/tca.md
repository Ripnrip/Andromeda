# TCA — The Composable Architecture

TCA 1.15+: `@Reducer`, `@ObservableState`, `@Dependency`.

## Reducer shape

```swift
@Reducer
struct FeatureReducer: Sendable {
    @ObservableState
    struct State: Equatable, Sendable { }

    enum Action: Equatable, Sendable {
        case userTapped
        case response(Result<Data, Error>)
    }

    @Dependency(\.apiClient) var apiClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action { … }
        }
    }
}
```

## Actions

| Kind | Naming |
|------|--------|
| User | verb: `.submit`, `.refresh` |
| Effect callback | `.response`, `.progress` |

## Clients

```swift
struct APIClient: Sendable {
    var fetch: @Sendable () async throws -> Data
}
extension APIClient: DependencyKey {
    static let liveValue = …
    static let testValue = …
}
```

## Effects

```swift
return .run { [apiClient] send in
    let data = try await apiClient.fetch()
    await send(.response(.success(data)))
} catch: { error, send in
    await send(.response(.failure(error)))
}
```

## Composition

```swift
Scope(state: \.child, action: \.child) { ChildReducer() }
```

## TestStore

```swift
let store = TestStore(initialState: State()) { FeatureReducer() } withDependencies: {
    $0.apiClient.fetch = { Data() }
}
await store.send(.userTapped) { … }
await store.receive(\.response.success)
```

## Rules

- State: value types only
- Guard duplicate in-flight effects
- No business logic in views — `Store` + actions
- Domain-specific MemoryReducer shape → **anima-swift**
