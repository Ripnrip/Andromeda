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

Record: `SNAPSHOT_TESTING_RECORD=1 swift test` (fleet convention; CI records via a `[record-snapshots]` tip commit and the baselines artifact).

Commit `__Snapshots__/` — but only baselines recorded on the CI runner image; local macOS 26 PNGs do not pixel-match macos-15 runners. CI: compare mode only.

## Determinism

Every nondeterminism source must be forced to a still, complete frame with pinned content before capture:

- **Reduce-motion forces stills — but the key changed in macOS 26 SDK.** `accessibilityReduceMotion` is now **get-only** (`SwiftUICore` declares `get` only); writing `.environment(\.accessibilityReduceMotion, true)` cannot compile. Write the long-lived SPI storage instead: `.environment(\._accessibilityReduceMotion, true)` (compiles on Xcode 16.4 CI and Xcode 26).
- **`.task`-driven reveals need a runloop pump.** A modifier that starts hidden (`shown = false`) and reveals from its `.task` will be captured pre-task (invisible) by a synchronous draw. Pre-host in an `NSWindow` (`contentViewController`), `window.display()`, then `RunLoop.main.run(until: +0.4s)` so MainActor tasks land; the hosting controller keeps the state when the capture re-hosts it.
- **Pin the RNG source, not just the motion.** Simulators/demo models that randomize data per init or per tick make baselines cross-process flaky even when animations are frozen. Ship a deterministic fixture list in the *source* module (e.g. `SampleData.deterministicRequests`) shared by gallery specimens AND test fixtures; pin metrics too.
- Fixed dates in fixtures; seed any sample generators.
- Mock all clients.

## swift-testing + pointfree 1.19

- Suite trait is `.snapshots(record:)` (plural); `assertSnapshot` takes no `sourceLocation:` — pass `file:`/`testName:` through helpers explicitly, or `#filePath`/`#function` resolve at the helper and every baseline lands under the helper's name.
- One framework per suite: an XCTest class is discoverable by BOTH XCTest and swift-testing runners in one `swift test` — duplicate baselines (`testFoo.`/`foo.` name prefixes) result.

## OTel in tests

Skip `Tracer.bootstrap()` when `XCTestConfigurationFilePath` set.

## Anti-patterns

- Snapshot full app window
- XCUITest for layout regression (use snapshots)
- Live network in unit tests
- Snapshot tests that capture animated or reveal states without pinning the random source (data RNG, ambient loops, entrance timing)
