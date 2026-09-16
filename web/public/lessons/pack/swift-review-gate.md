---
name: swift-review-gate
description: The fleet's 15-question Swift + UI review gate (from the 2026-09-09/10 #andromeda questionnaire sprint). Apply to every Swift PR before commit/merge — type shape, concurrency, observability, UI, quality. Six questions are merge blockers; the rest need explicit N/A. Includes the pre-commit automation split.
---

# Swift Review Gate — the fleet's 15 questions

Born in the #andromeda vault-widget thread (2026-09-09/10): BofA's design questions × fleet answers (Berserker, Linear, Manus, Cursor) distilled into one contract. Use it **as you work through items** (self-check at commit) and **at review level** (reviewer walks the list on the PR).

## How to apply

- **Pre-commit tier (mechanically checkable)**: Q1, Q2, Q6, Q8 (partially), Q9, Q14 — these can be ast-grep/CI rules; treat as build failures, not style notes.
- **Review tier (judgment)**: the rest — each unchecked question needs an explicit rationale or `N/A` in the PR.
- **Merge blockers**: Q1, Q2, Q6, Q8, Q9, Q14. A PR failing these does not merge.

## The 15 questions

### Type & expression

**Q1. Enums over magic strings.** Every string that is really a finite set (states, labels, error kinds, allowlists, lanes, list markers) is an `enum` with exhaustive `switch`es; `CaseIterable` where tests should iterate. *(From: PR #75 hub refactor, PR #27 ListItemMarker — marker-string loops became a typed enum.)*

**Q2. Codable on the wire.** No hand-built JSON string literals in production code. Error frames, DTOs, and happy-path test fixtures encode from types. Byte-equality tests where wire shape matters (`"id":null` must be a *present* member — absent ≠ null). Deliberately-malformed frames stay raw — Codable cannot emit duplicate keys, and that illegality IS the security property. *(From: HubJSONRPCError + the JSONEncoder key-order trap — macOS 26 JSONEncoder randomizes key order per-process; stable wire bytes need a canonical writer, not plain Codable.)*

**Q3. Smallest clear expression.** Function vs computed property — honest about cost (`diskSpace()` does filesystem I/O: stays a function, should `throws`/return `Result` rather than silently zeroing failures — "no storage" must be distinguishable from "could not inspect"). Prefer `switch` over chained `if`s; `guard let` for early exit, `if let` for local branch, `for case let` for filtered pattern-matching.

**Q4. Protocol vs enum — the right tool.** Protocols only where implementations genuinely vary (module APIs, test boundaries, alternate backends). Finite variation = enum, not a protocol hierarchy.

**Q5. Functional Swift where it fits.** `map`/`compactMap`/`flatMap`/`reduce` when the source is a collection and the transform is pure. Keep streaming loops (`for case let` + progress) when collecting would allocate, delay results, or hide side effects — don't materialize an enumerator to look functional.

### Concurrency & streams

**Q6. Actors / Sendable.** Shared mutable state is actor-isolated or value-typed Sendable. Every `@unchecked Sendable` carries a written justification. Cross-boundary values conform to `Sendable`.

**Q7. Smallest honest lifetime model.** Is this a value, a one-shot `async` function, or an `AsyncSequence`? Choose the smallest model that represents the real lifetime. `AsyncStream`/`AsyncThrowingStream` for incremental/cancellable production (scans, progress, device events). Combine only at real publisher boundaries (existing `@Published`, debounce/merge composition, legacy UI) — never just to replace a loop.

### Observability & security

**Q8. Emoji telemetry at every decision point.** Each meaningful branch emits a typed event with a glyph (🚀🐣💥👋🛑🔌📬📡🚫⚠️🏷️✂️🧹🔁 …) through one enum surface, internal os.Logger + external where it matters. A new decision point without an event = fail.

**Q9. Secrets & data posture.** No ambient environment inheritance (enum allowlists, `EnvironmentAllowKey`-style). Auth before privileged side effects (Face ID before vault push from a Lock Screen widget — `authenticationPolicy = .requiresAuthentication`). No PII in logs/mirrors. Brokered secrets, never embedded.

### UI (when UI changes)

**Q10. Xcode Previews.** Every new UI state covered: loading / empty / error / long content / Dynamic Type / dark mode. Preview-parity suites where the repo has them.

**Q11. Snapshot tests.** Layout/rendering regressions that matter have snapshots — and baselines are CI-recorded, never studio-recorded; a green suite against a void baseline proves nothing (see canon Exhibit 7).

**Q12. Interaction feedback.** Intentional haptics for meaningful taps/confirmations; a11y labels; no fake "live" states.

### Quality

**Q13. Performance.** Hot path allocation-conscious (bytes not strings, reused buffers, deltas/cursors over full copies — a 56s full-vault pull became 0.03s deltas). No sync work on the main/timeline thread. No accidental O(n²).

**Q14. Exhaustive proof.** `CaseIterable` drives tests (allCases → valid / distinct / invariant checks). Tests built from Codable fixture builders. Behavioral changes carry a rendered sequence/flow diagram; UI changes carry a snapshot gallery. E2E paths proven by *running them* (real shipped code, real process, receipts posted) — not by asserting they should work.

**Q15. Better shape?** Is there a simpler API — fewer types, less indirection — that still keeps Q1–Q14? If not, say why in the PR.

## Enforcement ladder

1. **Now**: paste into PR descriptions as checked boxes; reviewers walk it.
2. **Phase 1 hook**: print the 15 Qs on commit; require `REVIEWED=1` or an explicit N/A list.
3. **Phase 2 automation**: ast-grep/CI for the mechanical subset (enum+CaseIterable presence, raw JSON literals in tests, HubEvent coverage on new branches, allowlist usage).

Related canon: swift-canon (review-canon §8 codifies this gate), anti-patterns (Exhibit numbering continues there).
