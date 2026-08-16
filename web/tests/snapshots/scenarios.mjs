/**
 * Declarative snapshot catalog for the Andromeda marketing site.
 *
 * This file is the web-side analogue of a Point-Free `assertSnapshot` call list:
 * every entry produces exactly one committed baseline PNG under `__Snapshots__/`,
 * and CI fails when the rendered page drifts from that baseline.
 *
 * Adding a scenario is the only step needed to gain coverage — the runner derives
 * the baseline filename, the diff artifacts, and the PR table row from these fields.
 *
 * Fields:
 *   name       Stable identifier. Becomes `<name>.png`. Never rename casually:
 *              a rename orphans the baseline and reads as "new snapshot" in CI.
 *   path       Route to capture, relative to the server root.
 *   viewport   `[width, height]` CSS pixels. Height only bounds the viewport;
 *              `fullPage: true` captures the whole scroll height.
 *   scheme     `dark` | `light` — forwarded to `agent-browser set media`.
 *   fullPage   Capture the entire document instead of just the viewport.
 *   clip       CSS selector to capture instead of the page. Use for sections of
 *              pages taller than Chromium's ~16384px surface ceiling, where a
 *              full-page capture would be silently truncated.
 *   waitFor    Optional literal text that must be present before capture. Cheap
 *              insurance against screenshotting a half-streamed RSC payload.
 *   settleMs   Extra quiet time after network idle, for font swap + layout settle.
 *   steps      Optional interaction list applied before capture, so stateful UI
 *              (open menus, submitted forms) can be snapshotted too.
 *              Each step is `{ action, selector?, value? }` where action is one of
 *              `click` | `fill` | `hover` | `press` | `scrollIntoView` | `wait`.
 */

/** @typedef {{action: "click"|"fill"|"hover"|"press"|"scrollIntoView"|"wait", selector?: string, value?: string|number}} Step */

/**
 * @typedef {object} Scenario
 * @property {string} name
 * @property {string} path
 * @property {[number, number]} viewport
 * @property {"dark"|"light"} [scheme]
 * @property {boolean} [fullPage]
 * @property {string} [clip]
 * @property {string} [waitFor]
 * @property {number} [settleMs]
 * @property {Step[]} [steps]
 */

/** @type {Scenario[]} */
export const scenarios = [
  {
    name: "landing-desktop",
    path: "/",
    viewport: [1440, 900],
    scheme: "dark",
    fullPage: true,
    waitFor: "Andromeda",
    settleMs: 900,
  },
  // The mobile landing page stacks to ~19000px, past Chromium's ~16384px capture
  // ceiling, so a single full-page baseline cannot be recorded without silent
  // clipping. It is covered as section-scoped clips instead: same assertions,
  // tighter diffs, and each section fails independently.
  {
    name: "landing-mobile-fold",
    path: "/",
    viewport: [390, 844],
    scheme: "dark",
    fullPage: false,
    waitFor: "Andromeda",
    settleMs: 900,
  },
  {
    name: "landing-mobile-pillars",
    path: "/",
    viewport: [390, 844],
    scheme: "dark",
    clip: "#pillars",
    waitFor: "Andromeda",
    settleMs: 900,
  },
  {
    name: "landing-mobile-waitlist",
    path: "/",
    viewport: [390, 844],
    scheme: "dark",
    clip: "#waitlist",
    waitFor: "Andromeda",
    settleMs: 900,
  },
  {
    name: "landing-hero-desktop",
    path: "/",
    viewport: [1440, 900],
    scheme: "dark",
    // Viewport-only capture of the fold. A tight crop fails fast and loudly on
    // hero regressions that a 12000px full-page diff would bury in noise.
    fullPage: false,
    waitFor: "Andromeda",
    settleMs: 900,
  },
  {
    name: "design-system-desktop",
    path: "/design",
    viewport: [1440, 900],
    scheme: "dark",
    fullPage: true,
    waitFor: "back to landing",
    settleMs: 900,
  },
  {
    name: "demo-desktop",
    path: "/demo",
    viewport: [1440, 900],
    scheme: "dark",
    fullPage: true,
    settleMs: 900,
  },
  {
    name: "banner-desktop",
    path: "/banner",
    viewport: [1440, 900],
    scheme: "dark",
    fullPage: true,
    settleMs: 900,
  },
]

/** Returns the scenario subset selected by `--scenario` filters (empty filter = all). */
export function selectScenarios(filters) {
  if (!filters || filters.length === 0) return scenarios
  const wanted = new Set(filters)
  return scenarios.filter((scenario) => wanted.has(scenario.name))
}
