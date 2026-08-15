# SwiftUI Views — Composition & Performance

## Composition

- Extract complex subtrees into `struct` subviews
- Prefer **modifiers** over `if/else` branches for state styling (preserves identity)
- Keep `body` pure — no side effects, no heavy work
- `Button` action → method reference, not inline logic
- Context-agnostic — no hard-coded screen sizes

## Performance

- Pass only needed values — not giant config objects
- No object creation in `body`
- `LazyVStack` / `LazyHStack` for long lists
- `ForEach` stable `id` — never `.indices` for dynamic content
- No inline filter in `ForEach` — prefilter
- No `AnyView` in list rows
- Gate `GeometryReader` updates by threshold
- `Self._logChanges()` to debug surprise updates (DEBUG)

## Lists

```swift
ForEach(items) { item in Row(item: item) }  // Identifiable
```

Constant view count per element.

## Layout

- Relative layout over magic numbers
- Business logic in services/models — not views
- `@ViewBuilder let content: Content` for container views

## Scroll

`ScrollViewReader` + stable IDs for programmatic scroll.

## Images

Downsample when decoding `UIImage(data:)` — see performance notes in image-heavy views.

## macOS

`MenuBarExtra`, `.windowStyle`, `.windowLevel(.floating)` — see `macos-patterns.md`.
