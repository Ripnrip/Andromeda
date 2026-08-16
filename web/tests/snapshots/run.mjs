#!/usr/bin/env node
/**
 * Andromeda web snapshot tests — the browser-side equivalent of the Point-Free
 * `SnapshotTesting` suites that guard the Swift surfaces.
 *
 * Contract, deliberately mirrored from the Swift lane:
 *   • Baselines live in `__Snapshots__/` and are committed to the repository.
 *   • A drifted render fails the build; it never auto-heals.
 *   • Re-recording is an explicit, reviewable act (`--record`, or a tip commit
 *     tagged `[record-web-snapshots]`), and record mode always exits non-zero so a
 *     record commit can never be mistaken for a green verification run.
 *   • Baselines are image-toolchain-bound. Record them on the same runner image CI
 *     uses (`ubuntu-24.04` + the Chromium `agent-browser install` pins); a laptop
 *     recording will not pixel-match and must not be committed.
 *
 * Usage:
 *   node web/tests/snapshots/run.mjs
 *   node web/tests/snapshots/run.mjs --record
 *   node web/tests/snapshots/run.mjs --scenario landing-desktop --base-url http://localhost:3000
 */

import { mkdir, readdir, rm, copyFile, writeFile, access } from "node:fs/promises"
import { constants } from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

import { selectScenarios } from "./scenarios.mjs"
import { agentBrowser, installBrowser, closeBrowser, openBrowser } from "./lib/agent-browser.mjs"
import { compareSnapshots, buildNewSnapshotComposite, readPng } from "./lib/image-diff.mjs"
import { renderMarkdown, renderHtml } from "./lib/report.mjs"
import { buildWebApp, startWebApp } from "./lib/server.mjs"

const HERE = path.dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = path.resolve(HERE, "../../..")
const BASELINE_DIR = path.join(HERE, "__Snapshots__")
const OUTPUT_DIR = path.join(HERE, "__Output__")
const INIT_SCRIPT = path.join(HERE, "determinism.js")

/** Per-pixel colour tolerance handed to pixelmatch (0 = exact, 1 = anything). */
const PIXEL_THRESHOLD = 0.1

/**
 * Fraction of pixels allowed to differ before a scenario fails.
 *
 * Held at a hard zero. An earlier draft used 0.05% to absorb "antialiasing churn",
 * and that slack immediately hid a genuine bug: the sequence diagram's
 * setTimeout-driven step animation flapped ~1.2k pixels between identical builds
 * and still reported green. The fix belonged in `determinism.js` (timer clamping),
 * not in the tolerance.
 *
 * Keep this at 0. If a scenario flakes, make the *page* deterministic — a non-zero
 * budget here silently buys off every future regression smaller than the budget.
 */
const FAILURE_RATIO = 0

/**
 * Attempts allowed for *capturing* a scenario (browser startup / navigation).
 *
 * This is not a tolerance for visual differences: each captured screenshot is
 * compared exactly once against its baseline at `FAILURE_RATIO`. Only failures to
 * produce a usable capture are retried.
 */
const CAPTURE_ATTEMPTS = 3

function parseArgs(argv) {
  const options = { record: false, scenarios: [], baseUrl: null, port: 4319, build: true }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === "--record" || arg === "--update") options.record = true
    else if (arg === "--scenario") options.scenarios.push(argv[++i])
    else if (arg === "--base-url") options.baseUrl = argv[++i]
    else if (arg === "--port") options.port = Number(argv[++i])
    else if (arg === "--no-build") options.build = false
    else throw new Error(`Unknown argument: ${arg}`)
  }
  // A tip commit marker is the CI-facing entrypoint into record mode, matching the
  // `[record-snapshots]` convention already used by the Swift lane in ci.yml.
  if (process.env.WEB_SNAPSHOT_RECORD === "1") options.record = true
  return options
}

async function exists(target) {
  try {
    await access(target, constants.F_OK)
    return true
  } catch {
    return false
  }
}

/**
 * Evaluates an expression in the page and returns it as a number.
 *
 * `agent-browser eval` prints its result JSON-encoded, so numbers arrive bare but
 * strings arrive quoted. Keeping the parsing in one place avoids re-introducing the
 * double-encoding mistake at each call site.
 */
async function evalNumber(expression) {
  const { stdout } = await agentBrowser(["eval", expression])
  const value = Number(String(stdout).replace(/"/g, "").trim())
  if (!Number.isFinite(value)) {
    throw new Error(`Expected a number from \`${expression}\`, got: ${stdout.trim()}`)
  }
  return value
}

/**
 * Measures document height, requiring two identical consecutive samples.
 *
 * A single sample can be read mid-layout (font swap, lazy image, reveal
 * transition) and yield a height the page immediately abandons — which then gets
 * baked into a baseline as a permanent one-off. Requiring the value to hold still
 * makes the recorded dimensions reproducible.
 */
async function measureStableHeight(scenarioName, { attempts = 8, intervalMs = 250 } = {}) {
  let previous = null

  for (let attempt = 0; attempt < attempts; attempt += 1) {
    const measured = await evalNumber(
      "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)",
    )

    if (measured <= 0) {
      throw new Error(`Measured a non-positive content height for ${scenarioName}: ${measured}`)
    }
    if (measured === previous) return measured

    previous = measured
    await agentBrowser(["wait", String(intervalMs)])
  }

  throw new Error(
    `Content height for ${scenarioName} never settled (last: ${previous}px). ` +
      `Recording an unstable height would make this baseline permanently flaky.`,
  )
}

/**
 * Drives the browser to a settled state and captures one PNG.
 *
 * The sequence matters: viewport and media are set before navigation so the first
 * paint already uses the right breakpoint, and the page is scrolled end-to-end
 * before capture so IntersectionObserver-gated sections have all fired.
 */
async function capture(scenario, { baseUrl, outPath }) {
  const [width, height] = scenario.viewport
  const url = new URL(scenario.path, baseUrl).toString()

  // Isolation between scenarios, WITHOUT tearing down the daemon per scenario.
  //
  // Closing the browser before each scenario looked like the clean approach, but
  // `close --all` reaps the daemon socket asynchronously and the following `open`
  // then fails ~4 times in 6. The retry path restarted the browser *after* the
  // viewport had been set, so emulation was silently lost and the run captured a
  // 1280x577 white page instead of the 390x844 dark mobile page — 350k-750k pixel
  // diffs from a browser that reported success at every step.
  //
  // Instead the daemon is started once per run and every scenario re-establishes
  // its own state explicitly (viewport, media, navigation), which is then asserted
  // below. `about:blank` between scenarios drops the previous page's scroll offset
  // and DOM without a socket teardown.
  await agentBrowser(["open", "about:blank"], { allowFailure: true })
  await agentBrowser(["set", "media", scenario.scheme ?? "dark", "reduced-motion"])
  await agentBrowser(["set", "viewport", String(width), String(height)])
  await agentBrowser(["open", url])
  await agentBrowser(["wait", "--load", "networkidle"])

  // Re-apply the viewport AFTER navigation.
  //
  // Setting it only before `open` is not reliable here: the previous scenario's
  // resized viewport was observed surviving into the next one (a scenario
  // requesting 1440x900 found itself at 1440x5388, the prior full-page height),
  // because full-page capture resizes the viewport and that emulation outlives the
  // navigation. Re-applying after the page loads pins the value that actually
  // matters for the capture, and the assertion below proves it took effect.
  await agentBrowser(["set", "viewport", String(width), String(height)])

  // `networkidle` is not the same as "document is usable": immediately after it,
  // `document.body` can still be null mid-document-swap. Wait for a real body with
  // content before asserting anything about the page.
  const readyDeadline = Date.now() + 30_000
  let documentReady = false

  while (Date.now() < readyDeadline) {
    const { stdout } = await agentBrowser(
      ["eval", "(() => { const b = document.body; return !!b && b.innerText.length > 0 })()"],
      { allowFailure: true },
    )
    if (/true/i.test(stdout)) {
      documentReady = true
      break
    }
    await agentBrowser(["wait", "250"], { allowFailure: true })
  }

  if (!documentReady) {
    throw new Error(`${scenario.name}: document never became ready at ${url}`)
  }

  // Verify the browser is actually in the state we asked for, before capturing.
  //
  // A zero exit code from the CLI is not proof the page is correct: runs were
  // observed capturing a 1280x577 white page instead of the 390x844 dark mobile
  // page, meaning the viewport and navigation had not taken effect even though
  // every command "succeeded". Those captures then became 350k-750k pixel diffs.
  // Asserting the observable state converts that whole class of silent corruption
  // into a loud, named failure.
  // Read scalars individually. `eval` returns its result JSON-encoded, so an
  // embedded JSON.stringify comes back double-encoded as a quoted string —
  // parsing that as an object is what made an earlier version of this check throw
  // on every scenario.
  const [actualWidth, actualHeight, currentUrl] = await Promise.all([
    evalNumber("window.innerWidth"),
    evalNumber("window.innerHeight"),
    agentBrowser(["get", "url"]).then(({ stdout }) => stdout.trim()),
  ])

  if (actualWidth !== width || actualHeight !== height) {
    throw new Error(
      `${scenario.name}: viewport is ${actualWidth}x${actualHeight} but ${width}x${height} was requested — ` +
        `the browser did not apply the emulation. Refusing to capture a wrong-viewport baseline.`,
    )
  }
  if (!currentUrl.startsWith(new URL(url).origin)) {
    throw new Error(`${scenario.name}: browser is on ${currentUrl}, expected ${url}`)
  }

  if (scenario.waitFor) {
    // Poll for the text ourselves instead of relying on a single `wait --text`.
    //
    // The one-shot form proved flaky here: it occasionally timed out on a page
    // whose text was demonstrably present (verified by reading innerText on the
    // same route). Asserting on innerText directly keeps the guarantee — the text
    // must really be there before capture — while surviving a transient miss,
    // rather than deleting the assertion to make the suite quiet.
    const deadline = Date.now() + 45_000
    let seen = false

    while (Date.now() < deadline) {
      // Guard every hop: right after navigation `document.body` can still be null
      // while Chromium swaps documents, and `wait --load networkidle` returns
      // before that settles. An unguarded expression throws there, which the CLI
      // reports as a failed command — the source of a 1-in-3 "text never appeared"
      // flake on a page whose text was demonstrably present.
      const { stdout } = await agentBrowser(
        [
          "eval",
          `(() => { const b = document.body; return !!b && b.innerText.includes(${JSON.stringify(scenario.waitFor)}) })()`,
        ],
        { allowFailure: true },
      )
      if (/true/i.test(stdout)) {
        seen = true
        break
      }
      await agentBrowser(["wait", "250"], { allowFailure: true })
    }

    if (!seen) {
      throw new Error(`Expected text "${scenario.waitFor}" never appeared on ${scenario.path}`)
    }
  }

  for (const step of scenario.steps ?? []) {
    switch (step.action) {
      case "click":
        await agentBrowser(["click", step.selector])
        break
      case "fill":
        await agentBrowser(["fill", step.selector, String(step.value ?? "")])
        break
      case "hover":
        await agentBrowser(["hover", step.selector])
        break
      case "press":
        await agentBrowser(["press", String(step.value)])
        break
      case "scrollIntoView":
        await agentBrowser(["scrollintoview", step.selector])
        break
      case "wait":
        await agentBrowser(["wait", String(step.value ?? 500)])
        break
      default:
        throw new Error(`Unsupported step action "${step.action}" in scenario ${scenario.name}`)
    }
  }

  // Walk the full scroll height to trigger reveal-on-scroll sections, then return
  // to the top so full-page and viewport captures share an identical origin.
  await agentBrowser([
    "eval",
    `(async () => {
      const step = window.innerHeight;
      for (let y = 0; y < document.body.scrollHeight; y += step) {
        window.scrollTo(0, y);
        await new Promise((r) => requestAnimationFrame(() => setTimeout(r, 24)));
      }
      window.scrollTo(0, 0);
      if (document.fonts && document.fonts.ready) await document.fonts.ready;
      await Promise.all(Array.from(document.images).map((img) =>
        img.complete ? null : new Promise((r) => { img.onload = img.onerror = r; })));
      return document.body.scrollHeight;
    })()`,
  ])

  await agentBrowser(["wait", String(scenario.settleMs ?? 500)])

  if (scenario.clip) {
    // Element-scoped capture. This is how pages taller than Chromium's surface
    // ceiling still get real coverage: each section is asserted independently
    // instead of being dropped from the suite.
    await agentBrowser(["scrollintoview", scenario.clip])
    await agentBrowser(["wait", String(scenario.settleMs ?? 500)])
    await agentBrowser(["screenshot", scenario.clip, outPath])
  } else if (scenario.fullPage === false) {
    await agentBrowser(["screenshot", outPath])
  } else {
    // Full-page capture by viewport resize, NOT `screenshot --full`.
    //
    // `--full` routes through CDP `Page.captureScreenshot` with a
    // beyond-viewport clip, which times out on this project's tall marketing
    // routes (/demo is ~5400px, / is ~10000px) and can take the whole browser
    // down with "CDP response channel closed". That failure previously slipped
    // through as a truncated 900px baseline that still compared green — a
    // fake-green path, so it is fixed here rather than tolerated.
    //
    // Growing the viewport to the document height keeps every capture on the
    // ordinary in-viewport screenshot path.
    const contentHeight = await measureStableHeight(scenario.name)

    // Chromium refuses surfaces past ~16384px per axis; capturing a silently
    // clipped page would be worse than failing loudly.
    const MAX_CAPTURE_HEIGHT = 16_000
    if (contentHeight > MAX_CAPTURE_HEIGHT) {
      throw new Error(
        `${scenario.name} is ${contentHeight}px tall, past the ${MAX_CAPTURE_HEIGHT}px capture ceiling. ` +
          `Split it into section-scoped scenarios instead of recording a clipped baseline.`,
      )
    }

    // Resize to a fixed point, not just once.
    //
    // Viewport-relative CSS (`min-h-screen`, `h-screen`, `dvh`) makes content
    // height a function of viewport height, so growing the viewport to fit the
    // content changes the content height in turn. /banner is exactly this: 952px
    // tall at a 900px viewport, and 1004px tall at a 1004px viewport. A single
    // resize therefore lands wherever timing puts it — the direct cause of a
    // ~533k-pixel flap between otherwise identical runs.
    //
    // Iterating until the height stops changing converges on the stable layout
    // (952px for /banner) and makes the captured dimensions reproducible.
    let targetHeight = contentHeight

    for (let attempt = 0; attempt < 5; attempt += 1) {
      await agentBrowser(["set", "viewport", String(width), String(targetHeight)])
      // Re-settle: the resize re-triggers viewport-relative layout and lazy images.
      await agentBrowser(["wait", "--load", "networkidle"])
      await agentBrowser(["eval", "window.scrollTo(0, 0)"])
      await agentBrowser(["wait", String(scenario.settleMs ?? 500)])

      const settled = await measureStableHeight(scenario.name)
      if (settled === targetHeight) break

      if (attempt === 4) {
        throw new Error(
          `${scenario.name} layout never reached a fixed point (viewport ${targetHeight}px vs content ${settled}px). ` +
            `Viewport-relative CSS is feeding back into content height; capture it with a \`clip\` selector instead.`,
        )
      }
      targetHeight = settled
    }

    await agentBrowser(["screenshot", outPath])
    await agentBrowser(["set", "viewport", String(width), String(height)])

    // Assert the capture is actually full-height. Without this, a degraded
    // screenshot path yields a viewport-tall PNG that then compares green
    // against an equally truncated baseline — green with no coverage.
    const captured = await readPng(outPath)
    if (captured.height < targetHeight * 0.95) {
      throw new Error(
        `${scenario.name} captured ${captured.height}px but the document is ${targetHeight}px tall — ` +
          `the full-page screenshot was truncated. Refusing to record a partial baseline.`,
      )
    }
  }

  // Guard against the silent-truncation class of bug in general: a capture that
  // is exactly viewport-height on a page known to be taller means the screenshot
  // path degraded, and must never be accepted as a baseline.
  if (!(await exists(outPath))) {
    throw new Error(`Screenshot for ${scenario.name} was not written to disk`)
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2))
  const startedAt = Date.now()
  const targets = selectScenarios(options.scenarios)

  if (targets.length === 0) throw new Error("No scenarios selected")

  await rm(OUTPUT_DIR, { recursive: true, force: true })
  for (const dir of ["actual", "baseline", "diff", "composite"]) {
    await mkdir(path.join(OUTPUT_DIR, dir), { recursive: true })
  }
  await mkdir(BASELINE_DIR, { recursive: true })

  let server = null
  let baseUrl = options.baseUrl

  if (!baseUrl) {
    if (options.build) await buildWebApp({ cwd: REPO_ROOT })
    server = await startWebApp({ cwd: REPO_ROOT, port: options.port })
    baseUrl = server.baseUrl
  }

  const results = []

  try {
    await installBrowser({ withDeps: process.env.CI === "true" && process.platform === "linux" })

    // One cold start for the whole run: close any daemon left by a previous run,
    // then start ours with the determinism init script registered. Scenarios reset
    // their own state rather than restarting the browser (see capture()).
    await closeBrowser()
    await openBrowser(INIT_SCRIPT)

    for (const scenario of targets) {
      const actualPath = path.join(OUTPUT_DIR, "actual", `${scenario.name}.png`)
      const baselinePath = path.join(BASELINE_DIR, `${scenario.name}.png`)

      const base = {
        name: scenario.name,
        path: scenario.path,
        viewport: scenario.viewport,
        scheme: scenario.scheme ?? "dark",
      }

      // Bounded retry around *infrastructure* failures only.
      //
      // Browser startup and navigation are genuinely flaky on small runners: on a
      // 2-CPU box with adequate free memory, roughly 1 scenario in 8 failed to
      // reach a usable document on the first try, while a retry succeeded. Those
      // are environment failures, not visual regressions.
      //
      // This retries *capture*, never comparison: a captured PNG is compared
      // exactly once at a zero-pixel threshold. Retrying a pixel mismatch would be
      // rerolling the dice until a regression passes; retrying "the browser never
      // came up" is just making the harness reliable. If every attempt fails the
      // scenario is still reported as an error and the run still fails.
      let captureError = null

      for (let attempt = 0; attempt < CAPTURE_ATTEMPTS; attempt += 1) {
        try {
          await capture(scenario, { baseUrl, outPath: actualPath })
          captureError = null
          break
        } catch (error) {
          captureError = error
          if (attempt < CAPTURE_ATTEMPTS - 1) {
            process.stderr.write(
              `↻ ${scenario.name}: capture attempt ${attempt + 1} failed (${error.message.split("\n")[0]}); retrying\n`,
            )
            // Deliberately does NOT tear the browser down.
            //
            // An earlier version closed and reopened between attempts, which looked
            // like the safer choice and was catastrophic: `close --all` reaps the
            // daemon socket asynchronously, the reopen lost the race, and every
            // subsequent scenario in the run failed with `open ... exited 1`. One
            // recoverable scenario failure took down the entire suite.
            //
            // capture() already resets page state (about:blank, viewport, media,
            // navigation) and asserts it, so simply retrying is both sufficient and
            // far more reliable than restarting the daemon.
            await new Promise((resolve) => setTimeout(resolve, 2_000))
          }
        }
      }

      if (captureError) {
        results.push({
          ...base,
          status: "error",
          error: `${captureError.message} (after ${CAPTURE_ATTEMPTS} attempts)`,
        })
        continue
      }

      if (options.record) {
        await copyFile(actualPath, baselinePath)
        results.push({
          ...base,
          status: "recorded",
          diffPixels: 0,
          diffRatio: 0,
          actualFile: path.posix.join("actual", `${scenario.name}.png`),
        })
        continue
      }

      if (!(await exists(baselinePath))) {
        const composite = path.join(OUTPUT_DIR, "composite", `${scenario.name}.png`)
        const size = await buildNewSnapshotComposite({ actualPath, compositePath: composite })
        results.push({
          ...base,
          status: "new",
          actualSize: [size.width, size.height],
          actualFile: path.posix.join("actual", `${scenario.name}.png`),
          compositeFile: `${scenario.name}.png`,
          error: "No committed baseline. Re-record with [record-web-snapshots] and commit the artifact.",
        })
        continue
      }

      await copyFile(baselinePath, path.join(OUTPUT_DIR, "baseline", `${scenario.name}.png`))

      const comparison = await compareSnapshots({
        baselinePath,
        actualPath,
        diffPath: path.join(OUTPUT_DIR, "diff", `${scenario.name}.png`),
        compositePath: path.join(OUTPUT_DIR, "composite", `${scenario.name}.png`),
        threshold: PIXEL_THRESHOLD,
      })

      const failed = comparison.dimensionsChanged || comparison.diffRatio > FAILURE_RATIO

      results.push({
        ...base,
        status: failed ? "fail" : "pass",
        ...comparison,
        baselineFile: path.posix.join("baseline", `${scenario.name}.png`),
        actualFile: path.posix.join("actual", `${scenario.name}.png`),
        diffFile: path.posix.join("diff", `${scenario.name}.png`),
        compositeFile: `${scenario.name}.png`,
      })
    }

    // Orphaned baselines are reported, never deleted silently: a stale PNG usually
    // means a scenario was renamed, and the reviewer should decide.
    if (!options.record && options.scenarios.length === 0) {
      const known = new Set(targets.map((scenario) => `${scenario.name}.png`))
      const onDisk = (await readdir(BASELINE_DIR)).filter((file) => file.endsWith(".png"))
      for (const file of onDisk) {
        if (known.has(file)) continue
        results.push({
          name: file.replace(/\.png$/, ""),
          path: "—",
          viewport: null,
          status: "obsolete",
          error: "Baseline has no matching scenario in scenarios.mjs.",
        })
      }
    }
  } finally {
    await closeBrowser().catch(() => {})
    if (server) await server.stop().catch(() => {})
  }

  const durationMs = Date.now() - startedAt
  const commitSha = process.env.GITHUB_SHA ?? "local"

  await writeFile(
    path.join(OUTPUT_DIR, "report.json"),
    `${JSON.stringify({ commitSha, recordMode: options.record, durationMs, results }, null, 2)}\n`,
  )
  await writeFile(
    path.join(OUTPUT_DIR, "report.md"),
    `${renderMarkdown({
      results,
      imageBaseUrl: process.env.WEB_SNAPSHOT_IMAGE_BASE_URL || null,
      artifactUrl: process.env.WEB_SNAPSHOT_ARTIFACT_URL || null,
      commitSha,
      recordMode: options.record,
      durationMs,
    })}\n`,
  )
  await writeFile(path.join(OUTPUT_DIR, "index.html"), renderHtml({ results, commitSha, recordMode: options.record }))

  const blocking = results.filter((result) => ["fail", "new", "error", "obsolete"].includes(result.status))
  for (const result of blocking) {
    process.stderr.write(`✗ ${result.name}: ${result.status}${result.error ? ` — ${result.error}` : ""}\n`)
  }
  for (const result of results.filter((result) => result.status === "pass")) {
    process.stdout.write(`✓ ${result.name}\n`)
  }

  process.stdout.write(`\nReport: ${path.join(OUTPUT_DIR, "report.md")}\n`)

  if (options.record) {
    // Same posture as SnapshotTesting's record mode: recording is not a pass.
    process.stderr.write("\nRecord mode is on — baselines were rewritten. Commit them, then rerun without --record.\n")
    process.exitCode = 1
    return
  }

  process.exitCode = blocking.length > 0 ? 1 : 0
}

main().catch((error) => {
  process.stderr.write(`${error.stack ?? error.message}\n`)
  process.exitCode = 1
})
