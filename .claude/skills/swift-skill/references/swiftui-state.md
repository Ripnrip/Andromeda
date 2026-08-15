# SwiftUI State Management

## Property wrapper guide

| Wrapper | Use |
|---------|-----|
| `@State` | Private internal view state |
| `@Binding` | Child **mutates** parent |
| `@State` + `@Observable` class | iOS 17+ owned model |
| `@Bindable` | Injected observable needing bindings |
| `let` | Read-only from parent |

## Rules

- `@State` must be `private`
- Never ` @State var x = parentValue` — only initial literals or defaults
- Nested `ObservableObject` doesn't propagate — pass nested object directly
- `@Observable` handles nesting

## Store (TCA)

```swift
struct MyView: View {
    let store: StoreOf<FeatureReducer>
    var body: some View {
        WithPerceptionTracking {
            // read store.state
        }
    }
}
```

## Observable client

```swift
@MainActor
@Observable
final class AppClient {
    private(set) var items: [Item] = []
}
```

```swift
struct ListView: View {
    @Bindable var client: AppClient
}
```

## Sheets

Prefer `.sheet(item:)` over `.sheet(isPresented:)` for model-driven presentation.

## onChange

```swift
.onChange(of: value) { _, new in … }  // two-parameter form (iOS 17+)
```

See `latest-apis.md` for deprecated variants.
