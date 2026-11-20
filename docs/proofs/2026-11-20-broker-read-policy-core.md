# Finite broker-read policy core

**Status: source compiled, focused tests and compiler-access checks passed, independent source review has no substantive findings. Pure core only; no live capability registration.** Base main: `2efbfc04aa13d7405a667e26274125224d9183fc`.

## Scope

The packet introduces typed repository/channel/principal references, finite read requests, per-principal exact resource membership, bounded first-page/issue-list parameters and an immutable authorized intent. Capability identifiers are `github_proxy` and `slack_proxy`; they remain unregistered. No `write.too`, legacy write alias, arbitrary HTTP request, cursor-driven fan-out or automation flag is part of this model.

References use a conservative bounded ASCII grammar. Repository identity is ASCII case-normalized; channel and principal identity are exact case-sensitive values. Shape validation does not certify upstream existence or permissions. Operator-owned resource sets are independently capped at 128; caller limits/pages/issue numbers are validated value types. Production functions are small and documented in two cohesive files; no dynamic JSON, forced unwrap, unchecked concurrency, persistence format or background work was added.

## Executed evidence — November 20, 02:41–02:55 EST

A Swift-native QA preparer recorded SHA-256 hashes for 20 byte-identical real module/test source snapshots. The focused package uses the root target dependency graph for `AndromedaDomain`, `AndromedaSecrets` and `AndromedaTools`, Swift 6 language mode and a macOS 14 deployment floor. The actual full `AndromedaTools` module, including both new files and its preexisting broker files, compiled successfully alongside its real local dependencies.

`swift test --jobs 1` passed **79 tests in 3 Swift Testing suites**, including the independent frozen-contract policy suite and existing curated-broker/secret-leak suites. Parameterized cases are not counted as separate test declarations. The XCTest compatibility wrapper’s zero-test line is not the executed result. Build time was 942 seconds on the shared desktop; the tests themselves took 0.133 seconds. This is a focused module graph, not full root package, RepositoryPolicyTests, UI/snapshots or remote CI certification.

The policy fixtures cover all five approvals, list/authorize scope equivalence, empty/disjoint/equal-ID principals, exact-resource denial, canonical repository case versus exact channel/principal identity, ASCII/traversal/percent/Unicode/control input, max+1 lengths, numeric bounds/Int extremes, independent 128/129 resource caps, and unknown/legacy/write capability-name rejection. Existing legacy write tests still pass intentionally: the old broker is NOT protected by this new core.

Independent complete-source/643-line-test review identified **no substantive findings** against the frozen pure-core contract. This was static review, not an independent native execution or release approval.

Three additional `swiftc -typecheck` fixtures passed their expected contracts against the built real module, including `@testable` consumer access: legal policy authorization compiled with exit 0; direct forged construction failed with exit 1 and the expected `fileprivate` diagnostic; result-request mutation failed with exit 1 and the expected `let` diagnostic. The two deliberate negative rejections are not production compile failures.

A fresh typed verification confirmed all 20 executed source hashes remained unchanged, main remained pinned, and the four exclusively owned paths had **zero overlap with all 7 currently open PR file sets**. Git status confirmed no tracked existing-file changes in the policy worktree. Published-file checks do not prove absence of every unpublished agent change.

## Required integration packet

The integrator must establish the authenticated principal from a trusted host credential binding before calling `BrokerReadPolicy`. Neither a client-supplied principal name/grant nor `AuthorizedBrokerRead` is an authentication credential. `listCapabilities` and `authorize` are pure functions over trusted host grants; no server route invokes them yet.

A future adapter must consume the authorized intent, map only the five approved read operations to fixed vetted origins and finite parameters, and resolve the correct host-held credential only after local permission validation. It must reuse #110 output filtering, #111 complete-response transport and #112 native lookup rather than introducing a second client-facing broker. It must reject legacy tool aliases and writes on the scoped client boundary, even if a legacy instance enables `automationAllowed`.

Secure client authentication/reference transport, neighboring route authentication, same-principal list/call scope, safe audit events, actual upstream least-privilege verification, native/installed failure proofs and soak remain integrator/release work. The current legacy `CuratedToolBroker` and `ToolsBrokerConfiguration` are unchanged; they do not become protected by adding this core. No schema/config/wire persistence is introduced; an ADR/migration is required if the new model is later persisted or exposed as a protocol.

## Ownership and limits

Only new `BrokerReadReferences.swift`, `BrokerReadPolicy.swift`, `BrokerReadPolicyTests.swift` and this proof belong to the packet. Existing dispatcher, configuration, auth, HTTP/Keychain, runtime, MCP, UI, manifests and installers are untouched. No live reads, credential operations, service mutations, client cutover or merge are part of this work. Native/installed/soak proofs and actual secure runtime routing are explicitly absent; these are not three shipped pillars.
