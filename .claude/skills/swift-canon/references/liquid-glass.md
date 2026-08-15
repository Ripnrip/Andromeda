# Liquid Glass (iOS 26+)

**Only when user requests iOS 26 styling.**

## Basic

```swift
if #available(iOS 26, *) {
    content
        .padding()
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
} else {
    content
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
}
```

## Grouped

```swift
GlassEffectContainer(spacing: 24) {
    HStack { … }
}
```

## Buttons

```swift
Button("Confirm") { }
    .buttonStyle(.glassProminent)
```

## Rules

- `.glassEffect()` **after** layout/appearance modifiers
- `.interactive()` only on tappable elements
- `glassEffectID` + `@Namespace` for morph transitions
- `#available(iOS 26, *)` with material fallback
- Consistent shapes/tints across related elements
