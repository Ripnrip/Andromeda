# Broker output safety — executed focused proof, 2026-11-19

## Scope

This prerequisite slice hardens the existing curated broker. It does not ship a secrets vault, new client capability IDs, finite resource authorization, MCP-session consolidation, or installed runtime readiness. Existing injectable providers/transports and automation policy remain in place.

Successful responses receive overlap-aware byte-exact known-token filtering, including supported complete JSON string literals, before UTF-8-safe truncation. Bounded marker choice and final invariants withhold output if replacement/truncation metadata recreates the resolved token. This is known-token filtering, not generic DLP or credential discovery. Invalid UTF-8, sanitization failures, excessive body/work budgets and upstream error bodies are withheld. Slack success positively requires Boolean `ok:true`; malformed/missing/null status is a fixed error. Only reviewed constant error mappings are exposed.

The broker validates nonempty ASCII RFC6750 b64token values up to 4096 bytes before constructing an authenticated request. Invalid whitespace/control/NUL/grammar values yield fixed safe failure and zero HTTP calls. Native generic secret retrieval must still preserve exact bytes; token validity belongs at this broker boundary.

Intentional compatibility changes: accepted upstream body ceiling is 1 MiB independently of the live adapter's default 8 MiB; malformed Slack status no longer succeeds; arbitrary upstream/backend/caller error diagnostics are not echoed; missing-secret errors no longer expose service/account references. The existing regression expectation was narrowly updated to assert the fixed safe error rather than restoring reflection.

## Executed evidence

Baseline: `2efbfc04aa13d7405a667e26274125224d9183fc`. Changes applied in the exclusive output-safety worktree, not the dirty shared checkout.

Toolchain: Apple Swift 6.3.3 (`swiftlang-6.3.3.1.3`, clang `2100.1.1.101`), arm64 macOS. A temporary dependency-free SwiftPM harness preserves the root package's macOS 14 deployment floor, Swift 6 language mode and actual `AndromedaDomain`, `AndromedaSecrets`, and `AndromedaTools` target dependency graph. It copies every Swift file from those modules and their two existing/new test directories byte-for-byte; SHA-256 source receipts were recorded. No test-body or production-code substitution was used.

`swift test` on that focused harness with two compiler jobs completed a native debug build and **83 Swift Testing tests in three suites passed** on 2026-11-19 at 15:58 EST (2.671-second test run). The XCTest wrapper's zero-test summary is not the discovery count; the Swift Testing summary is. Suites: original curated broker, original secret leak detector, and new broker output safety. Parameterized cases execute within the reported test count.

Executed coverage includes raw/decoded overlap, escaped JSON/keys, replacement/metadata boundary recreation, UTF-8 scalar cuts, exact/plus-one body/work bounds, deterministic synchronous checkpoint cancellation, strict Slack classification, forged backend errors, all-route invalid-token zero-HTTP checks, valid bearer-byte preservation, and original benign broker-policy assertions.

Local log and SHA receipts are retained in the task's working artifacts. Full root-package/CI and repeated fresh-process evidence are not established by this first focused run.

## Remaining gates

A transport that cuts a token before broker processing cannot be repaired by output filtering. Adoption must include the separate complete-response-or-error transport change and cross-lane proof. Full root-package compilation/regressions, fresh-process repetition, supported CI SDK acceptance, native performance/RSS/actual task cancellation, installed readiness and soak remain separate gates. Do not infer macOS 14 runtime proof solely from a deployment-target build on the current desktop.

No live credential resolution, upstream network request, service restart, permission change, deployment or merge was used for this proof. Independent static reviews preceded application; subsequent compiler-backed changes and release/CI review gates remain explicit.

## Combined-gate follow-up

On 2026-11-19 at 16:12 EST, the combined exact-source worktree (this output slice, corrected complete-response transport, and corrected native lookup) passed **136 Swift Testing tests in six suites**. Five subsequent independent `swift test --skip-build` processes against that same built snapshot all exited successfully. These runs cover coupled compilation and synthetic regression behavior; they do not substitute for actual native I/O, deployed readiness, supported CI, or full root-package proof. The full root `swift build --build-tests --jobs 2` gate is being evaluated separately. Initial focused logs/source receipts and all five fresh-process logs remain in the task's working artifacts.

## Root-package follow-up

In the parent-owned combined integration worktree, `swift build --build-tests --jobs 2` completed successfully at 16:17 EST on 2026-11-19. Then `swift test --skip-build --filter 'AndromedaToolsTests|AndromedaSecretsTests|RepositoryPolicyTests'` passed **138 tests in seven suites**, including the repository's no-shell-automation policy, at 16:18 EST. UI snapshot suites were compiled but deliberately not executed or recorded; this slice has no UI changes. This is the combined root build plus relevant root execution, not a claim that every root test ran or that remote CI/native installed/soak gates passed. Final applied compiler corrections also received independent review with no new substantive finding.

## `checkedBodyText` extraction follow-up — 19:05 EST

The requested readability refactor reduces `checkedBodyText` from 55 to 33 physical lines, retaining bounds/notice/error orchestration. Four named private stages now own UTF-8 decoding (`decodeUTF8Body`), decoded/raw filtering plus representation checks (`sanitizeBodyText`), scalar-safe truncation/metadata (`truncateBodyText`), and literal invariants (`requireLiteralTokenAbsent`). No public API, algorithm, checkpoint order, output copy, schema or failure-policy change is intended. Independent comparison against the exact committed baseline found no substantive finding; this is source review, not a native-runtime certificate.

The updated exact-source focused harness compiled and **83 tests in three suites passed** at 19:04 EST (2.973-second test run; 724.10-second build under the heavily contended desktop). One compiler job was used. Existing cancellation, overlap, codec, bound, marker and metadata tests were retained unchanged. No full root/integrated/fresh-process/UI gate was rerun for this new code; those earlier results belong to the preceding source snapshot. The previous #110 CI failure in the HUD heavy-suite step is not diagnosed or fixed by this extraction. New-commit CI and the original native/installed/soak/review gates remain required; no merge or deployment occurred.
