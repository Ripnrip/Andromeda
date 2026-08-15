# Xcode Previews

## Goals

- Iterate UI without full app launch (~seconds vs minutes)
- **State matrix** — one preview per major visual state

## Basic

```swift
#Preview("Healthy") {
    StatusView(state: .healthy)
}

#Preview("Degraded") {
    StatusView(state: .degraded(reason: "offline"))
}
```

## TCA

```swift
#Preview {
    FeatureView(store: Store(initialState: State()) {
        FeatureReducer()
    } withDependencies: {
        $0.apiClient = .preview
    })
}
```

## Interactive (iOS 17+)

```swift
#Preview {
    @Previewable @State var store = Store(…) { FeatureReducer() }
    FeatureView(store: store)
}
```

## Fixtures module

`PreviewSupport` target with static mocks — not linked in Release.

## Rules

- No network in previews — dependency overrides only
- Pin multiple previews in canvas grid
- `previewDisplayName` per state
- Slow Animations in canvas for motion QA
- `accessibilityReduceMotion` for deterministic snapshot-style previews

## Build time

- Separate UI SPM targets
- Don't import heavy server/OTel in view files
- Colocate `Previews/` subfolder per feature

## Domain requirement example

anima-swift requires one preview per `FabricStatus` — technique is here.
