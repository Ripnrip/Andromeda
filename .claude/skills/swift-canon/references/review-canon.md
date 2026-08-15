# Review Canon

General Swift PR discipline for any project.

## 1. Keep scope honest

- Compile fixes should stay compile fixes.
- Snapshot churn should only appear when visuals changed or a real baseline update is intended.
- Server contract changes should not be hidden inside unrelated runtime fixes.

## 2. Let the compiler teach you

- Swift 6 sendability/isolation errors are not optional.
- Non-exhaustive switches matter.
- Deprecation cleanups should follow the platform's intended migration path, not ad-hoc suppression.

## 3. Visual proof should be real

- Snapshot/UI PRs should carry body-level proof when the repo expects it.
- Use real images, stable links, or committed artifacts — not hand-wavy descriptions.

## 4. Review thread hygiene

- Answer the actual comment.
- Resolve only after fixing or explicitly deferring with agreement.
- Do not merge with substantive unresolved comments just because the UI looks green.

## 5. Generated code law

- Regenerate; do not hand-edit.
- Keep generated output separate from handwritten logic.

## 6. Testing law

- Pure logic → unit tests
- reducer/stateful logic → TestStore or equivalent
- UI rendering → snapshots
- critical full-path behavior → E2E sparingly

Use the smallest truthful test that proves the change.
