# Web Snapshot Tests

Browser screenshot tests for the Next.js marketing site in `web/`. This is the
web-side equivalent of the Point-Free `SnapshotTesting` suites that guard the Swift
surfaces: committed baselines, a failing build on visual drift, and explicit
re-recording.

| | Swift surfaces | Web surfaces |
|---|---|---|
| Harness | Point-Free `SnapshotTesting` | `agent-browser` + `pixelmatch` |
| Baselines | `**/__Snapshots__/*.png` (committed) | `web/tests/snapshots/__Snapshots__/*.png` (committed) |
| Runner | `macos-15` + Xcode 16.4 (`ci.yml`) | `ubuntu-24.04` + pinned Chromium (`web-snapshots.yml`) |
| Re-record | `[record-snapshots]` on the PR head tip | `[record-web-snapshots]` on the PR head tip |
| Failure surface | Red test + uploaded PNGs | Sticky PR comment with a diff table and left/right images |

## Running locally

```console
npm run test:web-snapshots                     # build, serve, verify
npm run test:web-snapshots:record               # rewrite baselines (always exits 1)
node web/tests/snapshots/run.mjs --scenario landing-hero-desktop
node web/tests/snapshots/run.mjs --no-build     # reuse an existing .next build
node web/tests/snapshots/run.mjs --base-url http://localhost:3000
```

Local runs are for **iterating on scenarios**, not for producing committed
baselines. Baselines are bound to the CI runner's image and font rasterisation; a
laptop recording will not pixel-match `ubuntu-24.04` and must not be committed.

## Adding a scenario

Add an entry to `web/tests/snapshots/scenarios.mjs` — the runner derives the
baseline filename, diff artifacts, and PR table row from it. Then re-record on CI.

```js
{
  name: "pricing-desktop",   // becomes pricing-desktop.png; renaming orphans the baseline
  path: "/pricing",
  viewport: [1440, 900],
  scheme: "dark",
  fullPage: true,
  waitFor: "Choose a plan",  // asserted before capture
  settleMs: 900,
}
```

`steps` drives stateful UI before capture (`click`, `fill`, `hover`, `press`,
`scrollIntoView`, `wait`), and `clip` captures a single element instead of the page.

## Re-recording an intentional change

1. Push a commit whose message contains `[record-web-snapshots]`.
2. The workflow rewrites the baselines and uploads them as
   `web-snapshot-baselines-<sha>`.
3. Download the artifact, commit the PNGs, and remove the marker from the tip.

Record mode **always exits non-zero**, matching `SnapshotTesting`. A recording run
is not a verification run and must never read as green.

## Determinism

Zero tolerance: `FAILURE_RATIO = 0` in `run.mjs`. Any differing pixel fails.

Holding that line requires making the *page* deterministic rather than widening a
threshold. `determinism.js` runs before app JS on every document and:

- collapses CSS animations/transitions to ~1ms (rather than `none`, which would
  leave reveal-on-scroll content stuck at `opacity: 0` and bake a blank baseline);
- clamps `setTimeout`/`setInterval` delays, so JS-driven sequencers settle
  immediately instead of being captured mid-animation;
- freezes `Date` and seeds `Math.random`;
- hides `<video>`, whose first frame is not deterministic.

The browser daemon starts **once per run**; each scenario then resets to
`about:blank` and re-establishes its own viewport, colour scheme, and navigation.
The runner asserts that state (viewport dimensions and URL, read back from the page)
before capturing, so emulation that failed to apply fails the scenario instead of
producing a wrong-viewport baseline.

### Findings from bringing this up

Recorded because each one is a trap that reads as green:

- **A 0.05% tolerance hid a real bug.** The sequence diagram's `setTimeout`-driven
  step animation flapped ~1,200 px between identical builds and still passed. The
  fix was timer clamping in `determinism.js`; the tolerance is now `0`.
- **`screenshot --full` silently truncated tall pages.** CDP
  `Page.captureScreenshot` times out past a few thousand pixels and can kill the
  browser, and the truncated 900 px PNG was accepted as a baseline — then compared
  green against an equally truncated capture. Full-page capture now resizes the
  viewport to the document height, and an explicit assertion rejects any capture
  shorter than the measured document.
- **Leaked browser state made the suite non-reproducible.** The first run passed and
  the second failed, with `/design` waiting 25 s for text that was demonstrably
  present on a stale page. Hence the polled text assertion.
- **Closing the browser per scenario made things much worse.** The obvious fix for
  leaked state — a cold browser per scenario — backfired: `close --all` reaps the
  daemon socket asynchronously, so the next `open` failed in roughly 4 of 6
  attempts, and the retry restarted the browser *after* the viewport had been set.
  Emulation was silently dropped and runs captured a 1280×577 white page instead of
  the 390×844 dark mobile page — 350k–750k pixel diffs while every CLI command
  reported success. The daemon now starts once per run, scenarios reset via
  `about:blank`, and the runner **asserts** viewport and URL before capturing.
  Exit codes alone were not evidence that the browser was in the requested state.
- **Viewport-relative CSS creates a resize feedback loop.** `/banner` uses
  `min-h-screen`, so content height is a *function of* viewport height: 952 px at a
  900 px viewport, 1004 px at a 1004 px viewport. Resizing the viewport to fit the
  content therefore changes the content height, and a single resize lands wherever
  timing puts it — a ~533k-pixel flap that survived the cold-start fix and only
  reproduced on a second consecutive run. The runner now iterates the resize to a
  fixed point. This one is worth remembering: the first diagnosis (leaked state) was
  wrong, and only re-running the suite repeatedly exposed it.
- **Viewport emulation outlives navigation.** Full-page capture resizes the viewport
  to the document height, and that emulation survived into the *next* scenario: one
  requesting 1440×900 found itself at 1440×5388, the previous page's full height.
  Setting the viewport before `open` is therefore not sufficient — it is re-applied
  after the page loads and then asserted.
- **`networkidle` does not mean the document is usable.** Immediately after it,
  `document.body` was observed to be `null` mid-document-swap, and an unguarded
  expression throws there — surfacing as a 1-in-3 "text never appeared" failure on
  `/design`, whose text was demonstrably present. Navigation now waits for a real
  body with content, and every page probe is null-guarded.
- **The mobile landing page cannot be captured whole.** At ~18,940 px it exceeds
  Chromium's ~16,384 px surface ceiling, so it is covered as section-scoped clips
  (`landing-mobile-fold`, `-pillars`, `-waitlist`). The runner refuses to record a
  clipped baseline rather than quietly shipping a partial one.

If a scenario flakes, make the page deterministic. Do not raise `FAILURE_RATIO` —
a non-zero budget buys off every future regression smaller than the budget.

### Capture retries vs. comparison

`CAPTURE_ATTEMPTS = 3` retries **capture** — browser startup and navigation — and
never comparison. Each captured PNG is compared exactly once, at zero tolerance.

The distinction is the whole point. Retrying "the browser never reached a usable
document" makes the harness reliable; retrying a pixel mismatch would be rerolling
until a regression slips through. On a 2-CPU runner with ample free memory, roughly
1 scenario in 8 still failed to come up on the first attempt — an environment
failure, not a visual one. Retries are logged with `↻` so persistent flakiness stays
visible rather than being silently absorbed.

Retries do **not** restart the browser. An earlier version closed and reopened it
between attempts, which turned one recoverable scenario failure into a total run
collapse: `close --all` reaps the daemon socket asynchronously, the reopen lost the
race, and all eight scenarios then failed with `open ... exited 1`. `capture()`
already resets and asserts page state, so retrying in place is both sufficient and
far more reliable.

### Resource requirements

Chromium needs real memory and shared memory. The browser is launched with
`--disable-dev-shm-usage` because containers frequently cap `/dev/shm` at 64 MB
(well below what Chrome assumes), plus `--disable-gpu --no-sandbox` for headless CI.

The runner tears the browser down in a `finally` block. If you interrupt a run, check
for leaked processes before trusting later results — accumulated Chrome processes
exhaust a small runner and produce failures that look like page bugs but are not.

## PR output

The workflow posts one sticky comment containing:

- a Markdown table — scenario, route, viewport, status, diff pixels, diff
  percentage, and baseline→actual dimensions (flagged when they change);
- a left→right composite per changed scenario: **baseline · actual · diff**, with a
  green/blue/red accent bar identifying each panel.

Composites are pushed to an orphan `web-snapshot-images` branch under a per-commit
directory, because GitHub comments cannot reference artifact contents. Fork PRs get
a read-only token, so the table degrades to the artifact link instead of failing.

Full-resolution PNGs and a standalone HTML report are always uploaded as
`web-snapshot-report-<sha>`.

## Files

| Path | Role |
|---|---|
| `web/tests/snapshots/scenarios.mjs` | Scenario catalog — the only file most changes touch |
| `web/tests/snapshots/run.mjs` | Runner: capture, compare, report, exit status |
| `web/tests/snapshots/determinism.js` | Pre-app init script that freezes nondeterminism |
| `web/tests/snapshots/render-report.mjs` | Re-renders `report.md` once images have a URL |
| `web/tests/snapshots/lib/agent-browser.mjs` | CLI wrapper (namespaced session, startup retry) |
| `web/tests/snapshots/lib/image-diff.mjs` | Pixel diff + left/right composite |
| `web/tests/snapshots/lib/report.mjs` | Markdown table + HTML report |
| `web/tests/snapshots/lib/server.mjs` | `next build` + `next start` lifecycle |
| `web/tests/snapshots/__Snapshots__/` | Committed baselines |
| `web/tests/snapshots/__Output__/` | Run output (gitignored) |
