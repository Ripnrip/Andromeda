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


## Baseline integrity — never green against a void (Aug 2026)

A snapshot suite verifies *consistency*, not *presence*: a void baseline
passes forever. Guard it in-suite:

- `BaselineIntegrityTests` (AndromedaOrchestrator) scans every committed
  `__Snapshots__` PNG and fails on flat images (≤2 sampled colors, or ≤4
  with ≥99% single-color dominance). Adaptive stride, minimum sample count —
  small specimens don't false-positive.
- Record flow: `[record-snapshots]` tip → strict `swift build --build-tests`
  gate → tolerant record step → artifact upload. **Byte-diff the artifact
  against HEAD before landing it** — identical bytes mean the run produced
  nothing (usually a swallowed compile failure).
- Baselines are runner-image-bound: studio-recorded PNGs fail CI verify.
  Land only artifact bytes from the same image that verifies.

## Determinism from the environment

Reduce-motion stills, journal clocks, RNG, locale: derive settled state from
injected environment values (`shown || reduceMotion`, `\.journalNow`),
never from hoping a `.task` fires before capture. See anti-patterns
Exhibit 7.
