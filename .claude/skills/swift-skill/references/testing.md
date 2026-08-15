# Testing

## Pyramid

| Layer | Tool | Target |
|-------|------|--------|
| Pure logic | swift-testing `#expect` | transforms, decode |
| TCA | `TestStore` | effects, state |
| UI pixels | SnapshotTesting | stable views |
| E2E | XCUITest | critical paths only — sparingly |

## Pure

```swift
@Test
func derivesCorrectly() {
    #expect(transform(input) == expected)
}
```

## TestStore

```swift
@Test
func flow() async {
    let store = TestStore(initialState: State()) { Reducer() } withDependencies: {
        $0.client = .test
    }
    await store.send(.start) { $0.loading = true }
    await store.receive(\.done) { $0.loading = false }
}
```

## Snapshots

```swift
import SnapshotTesting

@Test @MainActor
func appearance() {
    let view = MyView(state: .error).frame(width: 320)
    assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
}
```

Record: `RECORD_SNAPSHOTS=1 swift test`

Commit `__Snapshots__/`. CI: compare mode only.

## Determinism

- `.environment(\.accessibilityReduceMotion, true)` for motion views
- Fixed dates in fixtures
- Mock all clients

## OTel in tests

Skip `Tracer.bootstrap()` when `XCTestConfigurationFilePath` set.

## Anti-patterns

- Snapshot full app window
- XCUITest for layout regression (use snapshots)
- Live network in unit tests
