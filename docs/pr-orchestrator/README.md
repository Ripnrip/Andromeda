# pr-orchestrator

Visuals for the AndromedaOrchestrator landing PR (#61).

- `console-obsidian.png` / `console-light.png` — the console shell, both
  schemes, steady-state model (1440×900).
- `gallery-obsidian.png` — the full 28-specimen gallery wall at natural
  height (1280×3000).
- `onboarding-welcome.png` — first-run onboarding, welcome beat (640×420).
- `specimens/` — all 28 catalogue specimens individually, copied verbatim
  from the runner-recorded `CatalogueSnapshotTests` baselines (the PR body's
  gallery tables reference these, so what the PR shows is exactly what CI
  verifies).

Regenerate: `SNAPSHOT_TESTING_RECORD=1 swift test` re-records the baselines
in `Tests/AndromedaOrchestratorTests/__Snapshots__/`; the docs images are
exports of the same hosted captures (same `OrchestratorSnapshotHosting`
path, `bitmapImageRepForCachingDisplay` + `cacheDisplay`). PR-body links
must pin the commit SHA — relative paths do not resolve in PR bodies.

History: the original `gallery-obsidian.png` was a 2-color void —
`EntranceModifier` gated its reduce-motion still on `.task`, which never
fires for ScrollView-hosted content in offscreen snapshot hosts, and the
stock async image strategy let the detached tree tear down before capture.
Both fixed in this PR; see the suite's snapshot support for the synchronous
capture path.
