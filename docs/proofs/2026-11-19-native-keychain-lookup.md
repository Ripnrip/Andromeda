# Native Keychain lookup — applied-lane focused proof

**Date:** 2026-11-19
**Status:** Focused native compile/test gate passed; not root-package, CI, live Keychain, or merge-readiness proof.

## Scope and provenance

Worktree: `/Users/<user>/Developer/Andromeda/.work/takeover-2026-11-19/keychain`
Branch inspected before edits: `manus/keychain-native-20261119`
HEAD inspected before edits: `2efbfc04aa13d7405a667e26274125224d9183fc`.

The initial read-only Git status showed the already-applied modified `SecretProviding.swift` and untracked `BoundedSecretLookup.swift`, `NativeKeychainLookupTests.swift`, and `BoundedSecretLookupRaceTests.swift`. This repair operated on those actual worktree files, not unapplied drafts. The only Swift file edited during this repair was `Tests/AndromedaSecretsTests/BoundedSecretLookupRaceTests.swift`; this proof is the only other author-owned edit. No production change was warranted by the diagnosed fixture failure.

The parent's intended native changes were preserved: decoding uses `String(decoding:as:)` plus an exact UTF-8 round trip, preserving valid BOM, NUL, decomposed Unicode, whitespace and stored replacement scalars while rejecting malformed bytes. The six-key Security query uses `LAContext.interactionNotAllowed = true` and `kSecUseAuthenticationContext`, not the deprecated authentication-UI flag.

No root manifest, shared test, other worktree, draft, environment, credential, service, or Keychain item was modified. No `.live` lookup was executed on this macOS lane; no authentication, application network call, Git commit, push, or PR operation was performed. Connector availability was inspected without invoking an application operation.

## Exact cause of the 14 failing issues

The original `swift-test.log` failed compilation because `String(validating:as:)` requires macOS 15; it also recorded the deprecated no-UI flag warning. The parent's applied fixes resolved those diagnostics. The subsequent `swift-test-2.log` compiled cleanly and ran 62 Swift Testing tests in four suites, but recorded 14 issues in the controlled race suite.

The race fixture used `DispatchTime(uptimeNanoseconds: 100)` with `.nanoseconds(10)` in both lane construction and explicit `Request` construction. Darwin `DispatchTime` converts through the native monotonic timebase; nanosecond labels do not guarantee that every nanosecond interval is representable. A temporary, non-secret arithmetic diagnostic in the first corrected test run recorded:

```text
KEYCHAIN-CLOCK-DIAGNOSTIC legacy-now=125 legacy-cutoff=125
```

This is in `validation/keychain/swift-test-3.log`. On this native host, adding the fixture's ten nanoseconds did not advance the represented instant at all. `Request.beginLookup()` correctly requires `now.uptimeNanoseconds < expiresAt.uptimeNanoseconds`; equal values therefore timed out and skipped the runner. Manual timer injection did not bypass that timestamp check. `finishLookup()` also correctly rejects timestamps at or beyond the cutoff.

The observed failures follow directly: fresh reuse calls after early cancellation failed their synthetic-success assertions because they received immediate timeout; all eight first-winner order fixtures and the delayed-timer fixture never entered their synthetic runners. Cancellation/setup portions could still pass because their intended outcomes did not require a successful unexpired claim. This was not evidence of a production admission leak or a deadline-coordinator defect.

## Applied repair

`ControlledClock` now owns one shared, representable `.milliseconds(1)` fixture timeout, starts at a synthetic uptime of one second, and advances monotonically by two milliseconds when explicitly told to move past the cutoff. `makeLane`, `makeRequest`, and the timer-attachment fixture all use that same timeout. These are manual clock values: the change adds no sleep, wall-clock wait, retry, timeout swallowing, or production deadline relaxation.

Every explicit fixture request now asserts that its cutoff is strictly future at construction. A new regression test checks a future initial cutoff, explicit advancement past it, and a fresh future cutoff for reuse after advancement. The temporary arithmetic print was removed before final validation. All prior race cases and assertions remain intact.

## Commands and results

Working directory for both repair attempts:

```text
/Users/<user>/Developer/Andromeda/.work/takeover-2026-11-19/keychain
```

The authorized typed preparer creates the focused harness from the actual lane's bytes and records SHA-256 for 20 source/test files. It was invoked in **harness** mode only, never **apply** mode.

```console
swift /Users/<user>/Developer/Andromeda/.work/takeover-2026-11-19/scripts/PrepareBrokerLanes.swift harness keychain
swift test --package-path /Users/<user>/Developer/Andromeda/.work/takeover-2026-11-19/validation/keychain --jobs 2 > /Users/<user>/Developer/Andromeda/.work/takeover-2026-11-19/validation/keychain/swift-test-3.log 2>&1

swift /Users/<user>/Developer/Andromeda/.work/takeover-2026-11-19/scripts/PrepareBrokerLanes.swift harness keychain
swift test --package-path /Users/<user>/Developer/Andromeda/.work/takeover-2026-11-19/validation/keychain --jobs 2 > /Users/<user>/Developer/Andromeda/.work/takeover-2026-11-19/validation/keychain/swift-test-4.log 2>&1
```

| Evidence | Result |
| --- | --- |
| Prior `swift-test.log`, reviewed | macOS 14-floor availability compile failure; deprecated-query warning |
| Prior `swift-test-2.log`, reviewed | Build 8.26 s; 62 tests / 4 suites; 14 failing issues |
| Repair attempt 1, `swift-test-3.log` | Build 4.86 s; 63 tests / 4 suites passed in 1.152 s; native arithmetic diagnostic retained in log |
| Repair attempt 2, final `swift-test-4.log` | Build 6.27 s; 63 tests / 4 suites passed in 1.154 s; final source has no temporary diagnostic |

Both repair commands completed successfully. The final log contains no compiler warning/error or failing issue. Two repair validation attempts were used, within the four-attempt bound. The final framework discovered/started and successfully executed 63 Swift Testing tests in four suites, rather than the previous 62; the increase is the one new clock regression. Parameterized case counts are reported separately by Swift Testing and are not the framework's test-declaration total. The preceding XCTest compatibility summary says zero tests; it is not the Swift Testing result.

The harness manifest uses Swift tools version 6.1, explicit Swift 6 language mode for every target (strict concurrency), and macOS 14 deployment availability. Its emitted version artifact reports `Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)` and toolchain target `arm64-apple-macosx26.0`. Swift Testing reports `arm64e-apple-macos14.0`. This is native-host validation with a macOS 14 deployment floor, not a claim that tests ran on a macOS 14 operating system or on every supported compiler.

## Preserved exercised coverage

The final log reports passing cases for both sequential first-success/first-error variants with no inter-call drain/retry, canceled-before-install custody, both installed/admitted-before-claim cancellation variants, both timer-attachment/activation cancellation variants, all eight completion/cancellation/deadline first-winner orders, and delayed timer delivery where the timestamp check alone rejects a late result. These fixtures retain assertions for running/admitted occupancy after abandonment, one native invocation/return where applicable, skipped invocation where canceled before claim, exact synthetic success on reuse, discarded late success/error, finished request state, detached deadlines, and exactly one controlled timer cancellation/activation.

The unchanged native suite also passes exact-reference/status decoding, ten nonempty UTF-8 cases, seven malformed UTF-8 cases, two unknown statuses, all eleven known statuses, exact noninteractive query construction, SDK constant parity, compatibility, main-actor caller/off-main runner, pre-admission cancellation, running cancellation, overload rejection, zero-cutoff skipping, sequential reuse, and a real one-second Dispatch caller deadline over a synthetic blocked runner. The other passing suites are the unchanged focused `AndromedaTools.CuratedToolBroker` and `SecretLeakDetector` tests; their inclusion is not a root-package gate.

## Final source SHA-256

The final preparer copied the actual worktree bytes into `validation/keychain` and wrote the complete 20-file manifest at:

`/Users/<user>/Developer/Andromeda/.work/takeover-2026-11-19/validation/keychain/source-sha256.json`

The four owned source/test hashes validated by `swift-test-4.log` are:

| Worktree-relative path | SHA-256 |
| --- | --- |
| `Sources/AndromedaSecrets/SecretProviding.swift` | `d94a9efb7a80d73920e59897376b2863273194c281afff756e0ad78e51fe583c` |
| `Sources/AndromedaSecrets/BoundedSecretLookup.swift` | `7e3703ee77c10fa5dcd7a88420034557d7296fe1928312878d89e57a4dbcef02` |
| `Tests/AndromedaSecretsTests/NativeKeychainLookupTests.swift` | `896341544749fb8e693ef469ee1c056b33ec8668dc70f31ee287755ca95a1efa` |
| `Tests/AndromedaSecretsTests/BoundedSecretLookupRaceTests.swift` | `3a868d90a7bb42759e4b50df37db85a42f5e4a55fd16c225df365d614bed24bf` |

These are byte hashes, not Git commits. The first corrected race file included the temporary diagnostic and had hash `8ef6955a7a5da1de05e63f6fc8726f2ba9ee09e457366a459fedc330ff815dd5`; `swift-test-3.log` must not be substituted for the final source proof.

## Actor, clock, race and native-runtime limitations

The coordinator is a narrow locked legacy-reference wrapper, not an actor. Its `@unchecked Sendable` declarations depend on the documented NSLock confinement of occupancy, request state and deadline custody; callbacks and continuation resumption occur outside locks. An actor alone would not make synchronous Security I/O interruptible. Native work remains on a serial Dispatch worker, with a single reserved slot and no waitlist/replacement worker; Swift tasks wait through a checked continuation. The main-actor test proves off-main execution for the injected runner, not independently measured exclusion from every cooperative-executor runtime.

Cancellation and deadline abandon caller waiting, not a synchronous native lookup. The slot remains occupied until the original runner returns. A worker claim is not atomic with later cancellation or deadline expiry, so a native invocation may start after a winning claim even if abandonment follows immediately. Timestamp checks reject late result delivery even when timer delivery is delayed; normal scheduling latency still prevents a guaranteed wall-clock wakeup instant.

Ordered Request fixtures prove selected transition/custody orders, not exhaustive scheduling interleavings. They directly cancel `Request`; public Task cancellation has an additional post-resume cancellation check exercised by the unchanged public-provider fixtures. Manual timers record coordinator activation/cancellation calls and permit adversarial callback delivery after cancellation; they do not prove OS timer deallocation, ARC lifetimes, or live native timer behavior. Manual clock advancement is explicit and consumes no wall time. The existing finite notice/caller/worker cleanup failsafes remain unchanged; no sleeps were added to make races pass. `drainForTesting` is safe here only because all held workers are finite synthetic fixtures, never a potentially uninterruptible Security call.

Query construction and status/data fixtures do not establish actual Keychain accessibility, entitlement behavior, locked-item behavior, or runtime no-UI enforcement. No `SecItemCopyMatching`, `SecItemAdd`, real credential lookup, or native authentication was invoked by these tests on this macOS lane. Swift String/Data also provide no cryptographic zeroization guarantee. Root-package tests, CI, live Security validation and release/merge gates remain unexecuted and unclaimed.

## Parent integration follow-up

On 2026-11-19 at 16:12 EST, a combined exact-source harness containing the actual corrected output, transport and native lookup sources passed **136 Swift Testing tests in six suites**. Five fresh independent processes against the same built snapshot then all exited successfully. The integrated sources include broker-owned bearer validation before HTTP, while native password bytes remain exact. This provides coupled synthetic source/seam regression evidence, not an actual authenticated HTTP/Keychain/no-UI operation. Full root-package compilation/regressions, supported CI and required native/installed/soak gates are separately tracked and not inferred from these passes.

## Root-package follow-up

The parent-owned combined root `swift build --build-tests --jobs 2` passed on 2026-11-19 at 16:17 EST. Root `swift test --skip-build --filter 'AndromedaToolsTests|AndromedaSecretsTests|RepositoryPolicyTests'` subsequently passed **138 tests in seven suites**, including repository policy. UI snapshots were not executed/recorded. The parent-established compiler/test acceptance and representable-clock repair received independent applied-code review with no new substantive finding. This supersedes the earlier root-unexecuted checkpoint only for the stated combined build and targeted suites; remote CI, other root tests, actual live Security/no-UI behavior, installed readiness and soak remain unproved.
