# Andromeda Review Canon

This file is the **hard review law** layered on top of general Swift craft.

## 1. Compile-first scope discipline

- If the PR says it is a compile/package/gate fix, keep it that way.
- Do not smuggle in design-system rollout, product reshaping, HTTP/runtime changes, or unrelated cleanup under a "green the build" label.
- If a branch grew too wide, restack it from the correct base and cut a clean diff.

## 2. Swift 6 reality checks

- Treat strict-concurrency failures as real defects, not annoying compiler drama.
- Common Swift 6 review catches:
  - non-`Sendable` types crossing tasks
  - static arrays/tables holding non-`Sendable` element types
  - actor isolation violations
  - non-exhaustive switches over newer enums
  - legacy snapshot/testing APIs that now need updated call patterns

When plain data is crossing boundaries, prefer making the value type `Sendable` instead of papering over with broad actor isolation unless the semantics truly require it.

## 3. Truth in UI and product surfaces

Never let demo gloss turn into product lies.

### Do not claim shipped if it is:
- spec only
- placeholder data
- unwired probe state
- aspirational backend surface
- future capability name with no live implementation

### Do not leak behind-the-curtain internals when contract says not to:
- provider model names
- provider brand names
- raw storage/vendor brand details when the UI is supposed to show stable capability or store abstractions
- secret-bearing implementation details

If the real state is incomplete, say `spec`, `planned`, `unwired`, `placeholder`, or `demo`.

## 4. Snapshot and visual proof law

For PRs with visual/UI changes or snapshot changes:

- include a **gallery in the PR body**
- use committed, repo-backed images or committed gallery assets
- do not rely on private artifact links
- do not bury the only proof in a review comment

Be explicit about what the images are:

- **recorded snapshot baselines** when they are true snapshots committed for regression proof
- **package-surface proofs for review** when they are representative renders/screens, not authoritative baselines

If a PR does not change visual/UI surfaces, do not run or expand snapshot burden by default.

## 5. Merge hygiene

- No merge while substantive unresolved comments remain.
- COMMENTED review with real findings still blocks if the substance is unresolved.
- Reply to threads point-by-point.
- Resolve only after the code or scope disposition truly addresses the concern.

Green CI is necessary, not sufficient.

## 6. Andromeda repo law

- Swift-first repo: if it can be Swift, it should be Swift.
- No bash implementation surface for project-maintained automation.
- Keep visibility and honesty intact: observable states, honest status, no fake success.
- Respect package boundaries and modularity. A package PR should not casually bleed into unrelated targets.

## 7. CI review law

Prefer CI that reflects the diff:

- cache shared SwiftPM artifacts
- avoid redundant dependency resolution when manifests did not change
- avoid always-on E2E when changed paths do not justify it
- keep gating explicit so reviewers can trust what was and was not exercised

Optimization must not make truth worse. Faster CI is good only if the lane semantics stay legible and honest.
