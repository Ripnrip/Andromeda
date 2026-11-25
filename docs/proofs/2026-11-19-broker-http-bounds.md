# Upstream HTTP bounds — executed focused proof, 2026-11-19

## Scope and behavior

An owned URLSession/task delegate replaces per-byte iteration and swallowed partial-stream failures. The public request/response/protocol seam and legacy byte-limit initializer remain source-compatible. Defaults are 8 MiB download, 1 MiB aggregate request bytes, 64 header fields, four admitted operations, 30-second response-header/idle budget and 60-second total resource budget. Invalid policies, unsafe metadata and saturation fail before starting native work. Independent executor instances retain independent admission gates.

Response collection appends complete bounded chunks only after one valid matching-origin head. Oversize, framing mismatch, midstream failure, redirect, non-trust authentication, cancellation and deadlines are explicit failures, never partial successes. Default TLS trust is not bypassed. Cookies/cache/replayed redirect requests are disabled at the owned native boundary.

A selected outcome is withheld until native invalidation acknowledges teardown, keeping admission owned throughout. A deadline ends selection, not a guaranteed wall-clock teardown or rollback of an upstream mutation. Terminal handle/timer publication guards prevent revival after invalidation; a returned orphan is disposed outside the state lock. Post-registration start/resume and cancellation may reach native effects in either order; no zero-transmission claim is made.

## Executed focused evidence

Baseline: `2efbfc04aa13d7405a667e26274125224d9183fc`. Applied only in the exclusive transport branch.

The exact-source temporary harness preserves macOS 14 deployment floor, Swift 6 language mode and the root `AndromedaDomain`/`AndromedaSecrets`/`AndromedaTools` dependency graph, including all module Swift files, original curated broker tests, original secret leak tests and new bounds fixtures. SHA-256 receipts pin the source snapshot. Toolchain is Apple Swift 6.3.3 (`swiftlang-6.3.3.1.3`, clang `2100.1.1.101`) on arm64 macOS.

The first compile exposed three type-erasure failures at collector catch sites inside locked closures. Explicit `do throws(UpstreamHTTPTransportError)` blocks retain the intended typed failure domain without forced casts or unchecked conformance. After correction, a native debug build succeeded and **64 Swift Testing tests in three suites passed** at 16:00 EST on 2026-11-19 (0.010-second run). The wrapper's zero XCTest count is not the Swift Testing discovery count.

Executed synthetic coverage includes complete binary/exact-limit and bulk chunk transfer, over-limit and advertised lengths, mismatched/truncated framing, metadata rejection, midstream failures, header/resource deadlines, saturation until teardown acknowledgement, direct pre-continuation cancellation, installation-window cancellation, factory-time terminal events, both start/cancel effect orders, duplicate/stale callbacks, and compatibility with the original broker seam. Parameterized scenarios are within the reported test count.

The new manual-teardown fixtures use sticky cleanup synchronized with handle publication. Cleanup requested before publication cannot lose the later acknowledgement obligation. The dedicated two-driver prepublication regression passed; cleanup supplies eventual acknowledgement, not a separately proven hard child-join deadline.

## Not proved / release gates

These are callback/native-adapter compilation and synthetic tests, not actual URLSession network/lifecycle proof. Native allocation/deallocation/read-ahead, real invalidation acknowledgement, pinned-Darwin suspended-task non-revival, redirect/authentication/decompression behavior, real deadline teardown, process RSS, supported CI and full root-package gates remain open. Defensive factory-window fixtures exceed the driver traffic contract and do not establish that Darwin produces that ordering.

The output-safety and native secret lookup slices remain separate dependencies for whole-broker adoption. Local focused logs/source hashes are retained in working artifacts; first-run success does not claim installed readiness or three completed control-plane pillars. No live upstream requests, credentials, service mutations, deployment or merge were used.

## Combined-gate follow-up

The corrected output, transport and native lookup were copied from their actual applied worktrees (not stale drafts) into a parent-owned integration proof branch. Native exact-source compilation and **136 tests in six suites passed** on 2026-11-19 at 16:12 EST, followed by five successful independent test processes against the built snapshot. This verifies combined source/seam and synthetic behavior. It does not establish actual Foundation network/session lifetime, macOS 14 runtime certification or release readiness. The broader root-package build/test gate and CI remain separately tracked.

## Root-package follow-up

Combined isolated root `swift build --build-tests --jobs 2` passed at 16:17 EST on 2026-11-19. Relevant root execution with `--skip-build --filter 'AndromedaToolsTests|AndromedaSecretsTests|RepositoryPolicyTests'` then passed **138 tests in seven suites**, including shell-policy checks. No UI snapshots were run/recorded. This is not every-root-test or actual URLSession/installed/soak proof; remote CI remains separate. The final explicit typed-do correction received independent applied-code review with no new substantive finding.
