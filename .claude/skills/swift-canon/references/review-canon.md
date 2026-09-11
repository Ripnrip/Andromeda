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

- **Every behavioral PR carries a sequence/flow diagram** — mermaid
  `sequenceDiagram`, `flowchart`, or `stateDiagram` of what the PR does,
  rendered to an image for review (`npx -p @mermaid-js/mermaid-cli mmdc`).
  Pure docs/config PRs may mark "n/a — no behavior change". (BofA law,
  2026-08-12 for AI-Config; made fleet-wide 2026-08-26.)
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

## 7. Review-feedback audit law (bodies ≠ threads)

Automated reviewer findings can live in TWO places: inline threads AND the
review body itself. A body-only finding (no inline anchor) never appears in
thread counts — claiming "0 outstanding" from thread enumeration alone is
structurally wrong. (Scar: Andromeda PR #53, Aug 2026 — an unguarded-timer
P2 rode in three consecutive review *bodies*, invisible to a thread-only
sweep, until the user pushed back.)

Audit protocol before claiming all feedback addressed:

1. Enumerate every review thread — resolved and unresolved.
2. Dump every review body; strip the boilerplate block; read what remains.
   A file link + priority badge is a finding even with no thread.
3. Check for threads where the reviewer has the last comment — follow-ups
   hiding inside resolved threads.
4. Only then claim clean — and make the claim falsifiable by listing what
   was checked.

A finding repeated across review rounds means the previous fix didn't take:
read the delta between rounds ("reads the flag but never consults it" =
declaration without a guard).

## 8. The 15-question gate (fleet contract, 2026-09-10)

Every Swift PR answers these before merge. Q1, Q2, Q6, Q8, Q9, Q14 are **merge
blockers**; the rest need an explicit rationale or N/A. Mechanical subset (Q1, Q2,
Q9, Q14-partial) belongs in pre-commit/CI, not reviewer memory.

1. **Enums over magic** — closed sets (errors, allowlists, states, markers) are `enum` + `CaseIterable` + exhaustive switch?
2. **Codable on the wire** — frames/fixtures from types, not string literals; byte-equality where `null` vs absent matters; malformed-input tests stay raw (Exhibit 13's canonical-writer rule).
3. **Smallest clear expression** — function vs property honest about I/O cost; switch > chained ifs; guard let / if let / for case let in their right places; failures typed, not silently zeroed.
4. **Protocol vs enum** — protocols only where behavior genuinely varies.
5. **Functional where it fits** — map/compactMap/reduce for pure collection transforms; streaming loops stay streaming when collecting would allocate or hide side effects.
6. **Actors/Sendable** — shared mutable state actor-isolated; @unchecked needs written justification.
7. **Smallest honest lifetime** — value / one-shot async / AsyncSequence; Combine only at real publisher boundaries.
8. **Emoji telemetry at decision points** — typed events + glyphs through one surface, every meaningful branch, internal + external.
9. **Secrets & data posture** — enum env allowlists; auth before privileged side effects (Face ID before vault push); no PII in logs/mirrors.
10. **Xcode Previews** — loading/empty/error/long-content/Dynamic Type/dark covered.
11. **Snapshot tests** — where layout regressions matter; CI-recorded baselines only (void-baseline law).
12. **Interaction feedback** — intentional haptics, a11y labels, no fake live states.
13. **Performance** — allocation-conscious hot paths, deltas/cursors over full copies, nothing sync on main/timeline.
14. **Exhaustive proof** — CaseIterable-driven tests, Codable fixture builders, rendered diagram for behavior, gallery for UI, e2e paths *run* with receipts.
15. **Better shape?** — simpler API that still keeps 1–14; if not, say why in the PR.

Full skill: `swift-review-gate` (iCloud shared skills + `~/.agents/skills/`).
