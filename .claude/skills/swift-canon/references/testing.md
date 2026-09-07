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

Commit `__Snapshots__/` — but only baselines recorded on the CI runner image; studio-recorded PNGs do not pixel-match the runner. CI: compare mode only.

**The snapshot environment is (image + Xcode pin + FONTS).** JetBrainsMono
absent on runners while present on studio was the entire runner≠studio
rendering-divergence root (PR #65/#67, Sep 2026): silent font substitution
moves text metrics, and every text-heavy baseline drifts. Install font casks
before the snapshot lanes and verify the font landed (`ls ~/Library/Fonts |
grep` fails loud); baselines are only valid recorded in the whole
environment — a re-record after any leg of that triple changes is a
record-all, not a lane-scoped re-record.

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
  nothing (usually a swallowed compile failure). Every record lane gets the
  compile gate, not one: `continue-on-error` swallows compile failures and
  the upload re-ships committed bytes as "fresh".
- Baselines are runner-image-bound: studio-recorded PNGs fail CI verify.
  Land only artifact bytes from the same image that verifies.
- **A `[record-snapshots]` tip is an image-change event**: it re-records
  EVERY snapshot lane regardless of diff scope (a runner bump invalidates
  all baseline trees, not the lanes the diff happens to touch), runs behind
  compile gates, and lands only after the provenance byte-diff. Record-detect
  must run before the scope early-exit so record tips never dead-end on
  scope-empty diffs.
- **The marker travels in merge subjects.** The record detection reads the
  PR-head tip subject — and a squash-merge subject carries into main's push
  runs. Strip `[record-snapshots]` from merge/PR titles or main records
  instead of asserting after the merge.

## Deterministic vs flaky — discriminate before fixing (Sep 2026)

- **Identical match-percentages across runs** (down to the decimals) = a
  deterministic render against stale bytes → land fresh baselines. Differing
  magnitudes run-to-run = a genuine race → fix determinism at the view. The
  fixes are disjoint; diagnosing one as the other burns record cycles.
- **A single-job CI lane can "pass" by step-skip illusion**: a failure in an
  earlier step (e.g. a flaky timeout test) skips later steps — the snapshot
  lane's absence from the failure list is not a pass. Check step execution,
  not just the failed-step list.
- Byte-diff loops use **absolute paths on both sides** — a relative path in
  a loop whose cwd differs from the path's origin compares a file against
  itself and reports 100% identical (see agent anti-patterns; this produced
  a false "515/515 byte-identical" once).

## Determinism from the environment

Reduce-motion stills, journal clocks, RNG, locale: derive settled state from
injected environment values (`shown || reduceMotion`, `\.journalNow`),
never from hoping a `.task` fires before capture. See anti-patterns
Exhibit 7.
- Snapshot tests that capture animated or reveal states without pinning the random source (data RNG, ambient loops, entrance timing)
