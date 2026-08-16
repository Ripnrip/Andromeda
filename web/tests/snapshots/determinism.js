// Page init script registered via `agent-browser open --init-script`.
//
// Runs before any application JavaScript on every document, which is the only
// point early enough to neutralise the three things that make browser
// screenshots flap between otherwise identical builds:
//
//   1. In-flight CSS animations / transitions at capture time.
//   2. Text carets and smooth scrolling.
//   3. Wall-clock and Math.random() leaking into rendered output.
//
// Animations are collapsed to ~0ms rather than disabled outright: reveal-on-scroll
// effects that start at `opacity: 0` would stay invisible forever under
// `animation: none`, producing a blank baseline that silently passes.
;(() => {
  const FROZEN_EPOCH_MS = Date.UTC(2026, 0, 1, 12, 0, 0)

  const style = `
    *, *::before, *::after {
      animation-delay: 0s !important;
      animation-duration: 1ms !important;
      animation-iteration-count: 1 !important;
      transition-delay: 0s !important;
      transition-duration: 1ms !important;
      caret-color: transparent !important;
    }
    html {
      scroll-behavior: auto !important;
    }
    /* Chromium renders a video poster/first frame non-deterministically. */
    video {
      visibility: hidden !important;
    }
  `

  const inject = () => {
    if (document.getElementById("__andromeda_snapshot_determinism__")) return
    const el = document.createElement("style")
    el.id = "__andromeda_snapshot_determinism__"
    el.textContent = style
    document.head?.appendChild(el)
  }

  if (document.head) inject()
  document.addEventListener("DOMContentLoaded", inject, { once: true })

  // Deterministic clock. Frozen rather than removed so `new Date()` call sites
  // keep working; only their rendered output stops moving.
  const RealDate = Date
  const FrozenDate = class extends RealDate {
    constructor(...args) {
      if (args.length === 0) super(FROZEN_EPOCH_MS)
      else super(...args)
    }
    static now() {
      return FROZEN_EPOCH_MS
    }
  }
  FrozenDate.parse = RealDate.parse
  FrozenDate.UTC = RealDate.UTC
  // eslint-disable-next-line no-global-assign
  Date = FrozenDate

  // Collapse `setTimeout`/`setInterval` delays.
  //
  // CSS-only freezing is not sufficient: components that sequence themselves in
  // JavaScript (e.g. the sequence diagram's `visibleSteps` step-through, driven by
  // chained setTimeout) keep advancing on wall-clock time, so a capture lands on
  // whatever frame the timer happened to reach. That produced a real ~1.2k-pixel
  // flap between identical builds — it was under the failure threshold, which is
  // exactly the kind of drift a tolerance would have hidden instead of fixed.
  //
  // Delays are clamped to 1ms rather than fired synchronously: a zero-delay
  // reentrant chain would starve the event loop, and self-rescheduling intervals
  // must still yield. The runner's settle wait then lets any chain run to its
  // terminal state before capture, so the snapshot records the *finished*
  // animation deterministically.
  const CLAMP_MS = 1
  const realSetTimeout = window.setTimeout.bind(window)
  const realSetInterval = window.setInterval.bind(window)

  window.setTimeout = (handler, delay, ...args) =>
    realSetTimeout(handler, Math.min(Number(delay) || 0, CLAMP_MS), ...args)
  window.setInterval = (handler, delay, ...args) =>
    realSetInterval(handler, Math.min(Number(delay) || 0, CLAMP_MS), ...args)

  // Seeded PRNG (mulberry32). Any component that randomises particle positions or
  // shuffles a list now produces the same layout on every run.
  let seed = 0x9e3779b9
  Math.random = () => {
    seed = (seed + 0x6d2b79f5) | 0
    let t = seed
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
})()
