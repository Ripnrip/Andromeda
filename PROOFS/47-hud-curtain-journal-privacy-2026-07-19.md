# PROOF 47 — HUD curtain journal + privacy slice

**Date:** 2026-07-19  
**Scope:** Andromeda promotion branch working tree; commit, push, CI, and `main` merge remain pending.

## Claims proved

- HUD parses `journal`, `memory.journal`, `session dump`, `sessiondump`, and
  `memory.session_dump`.
- `memory.journal` and `memory.session_dump` retain distinct capability IDs,
  provenance, tags, and generated default bodies.
- Every HUD episodic write (`memory.store`, `infer.write`, journal, session dump)
  passes through `VisibilityFilter.determineVisibility`.
- Missing/unspecified visibility fails closed to `private`; cloak/secrets markers
  force `internal`.
- HUD advertises `journal` and renders a dedicated journal success outcome.
- Hermetic E2E tests do not read, clear, or write the production HUD recent-query
  `UserDefaults` key.

## Evidence

```text
swift test --filter 'HUDCommandTests|HUDRecallE2ESnapshotTests'
PASS — 8 tests, 2 suites

swift test
PASS — 65 Swift Testing tests / 14 suites
PASS — 18 XCTest tests

git diff --check
PASS

IDE diagnostics for four edited Swift files
PASS — no linter errors

Independent review
PASS — no remaining actionable findings
```

The full suite initially rejected four HUD pixel baselines after the command-field
placeholder added `journal`. The four intentional baselines were re-recorded and the
entire suite then passed.

## Honesty boundary

This closes two implementation gaps on the promotion-branch candidate only. It does
not ship the secrets broker, MCP consolidation, inference routing, CloudKit egress,
or the workspace flip. PR #10 merge and CI proof are still required before these HUD
rows count as shipped on Andromeda `main`.
