/**
 * Pixel comparison plus the left/right composite that lands in the PR comment.
 *
 * Deliberately pure-JS (`pngjs` + `pixelmatch`): no native canvas build, so the
 * suite installs identically on macOS laptops and Linux CI runners.
 */

import { readFile, writeFile } from "node:fs/promises"
import { PNG } from "pngjs"
import pixelmatch from "pixelmatch"

/** Panel accent bar colours: baseline = green, actual = blue, diff = red. */
const PANEL_LABELS = [
  { key: "baseline", rgb: [34, 197, 94] },
  { key: "actual", rgb: [56, 152, 255] },
  { key: "diff", rgb: [239, 68, 68] },
]

const LABEL_BAR_HEIGHT = 10
const GUTTER = 12
const BACKGROUND = [10, 12, 14]

/** Reads a PNG file into a pngjs image. */
export async function readPng(path) {
  return PNG.sync.read(await readFile(path))
}

/** Writes a pngjs image to disk. */
export async function writePng(path, png) {
  await writeFile(path, PNG.sync.write(png))
}

/** Allocates a solid-colour canvas. */
function blank(width, height, rgb = BACKGROUND) {
  const png = new PNG({ width, height })
  for (let i = 0; i < png.data.length; i += 4) {
    png.data[i] = rgb[0]
    png.data[i + 1] = rgb[1]
    png.data[i + 2] = rgb[2]
    png.data[i + 3] = 255
  }
  return png
}

/**
 * Copies `src` onto `dst` at (`dx`, `dy`).
 *
 * `PNG.bitblt` throws when the source overruns the destination, so callers must
 * size the destination first; every call site here pads to the union bounds.
 */
function blit(src, dst, dx, dy) {
  PNG.bitblt(src, dst, 0, 0, src.width, src.height, dx, dy)
}

/** Pads an image to the given bounds, leaving the extra area transparent-dark. */
function pad(src, width, height) {
  if (src.width === width && src.height === height) return src
  const out = blank(width, height)
  blit(src, out, 0, 0)
  return out
}

/**
 * Compares two PNGs and writes the diff mask plus a baseline│actual│diff composite.
 *
 * Size mismatches are padded to the union bounds rather than rejected outright:
 * a taller page is a real, reviewable regression, and the reviewer still wants to
 * see where the content diverged instead of a bare "dimension mismatch" error.
 *
 * @returns {Promise<{diffPixels: number, diffRatio: number, totalPixels: number,
 *   dimensionsChanged: boolean, baselineSize: [number, number], actualSize: [number, number]}>}
 */
export async function compareSnapshots({ baselinePath, actualPath, diffPath, compositePath, threshold = 0.1 }) {
  const [baselineRaw, actualRaw] = await Promise.all([readPng(baselinePath), readPng(actualPath)])

  const width = Math.max(baselineRaw.width, actualRaw.width)
  const height = Math.max(baselineRaw.height, actualRaw.height)
  const dimensionsChanged = baselineRaw.width !== actualRaw.width || baselineRaw.height !== actualRaw.height

  const baseline = pad(baselineRaw, width, height)
  const actual = pad(actualRaw, width, height)
  const diff = new PNG({ width, height })

  const diffPixels = pixelmatch(baseline.data, actual.data, diff.data, width, height, {
    threshold,
    includeAA: true,
    // Dim the unchanged pixels so the red diff mask reads at a glance in a PR.
    alpha: 0.25,
    diffColor: [255, 64, 96],
    aaColor: [255, 205, 0],
  })

  const totalPixels = width * height
  const diffRatio = totalPixels === 0 ? 0 : diffPixels / totalPixels

  if (diffPath) await writePng(diffPath, diff)
  if (compositePath) await writePng(compositePath, buildComposite([baseline, actual, diff]))

  return {
    diffPixels,
    diffRatio,
    totalPixels,
    dimensionsChanged,
    baselineSize: [baselineRaw.width, baselineRaw.height],
    actualSize: [actualRaw.width, actualRaw.height],
  }
}

/**
 * Lays out panels horizontally with a coloured accent bar above each one.
 *
 * The bar colour, not embedded text, identifies the panel: rendering glyphs would
 * mean shipping a font rasteriser for a legend that the PR table already spells out
 * (green = baseline, blue = actual, red = diff, left to right).
 */
export function buildComposite(panels) {
  const width = panels.reduce((sum, panel) => sum + panel.width, 0) + GUTTER * (panels.length + 1)
  const height = Math.max(...panels.map((panel) => panel.height)) + LABEL_BAR_HEIGHT + GUTTER * 2

  const out = blank(width, height)
  let x = GUTTER

  panels.forEach((panel, index) => {
    const accent = PANEL_LABELS[index]?.rgb ?? [148, 163, 184]
    const bar = blank(panel.width, LABEL_BAR_HEIGHT, accent)
    blit(bar, out, x, GUTTER)
    blit(panel, out, x, GUTTER + LABEL_BAR_HEIGHT)
    x += panel.width + GUTTER
  })

  return out
}

/**
 * Builds a two-panel baseline│actual composite for scenarios whose baseline is
 * missing (nothing to diff against, but the reviewer still needs to see the new
 * render next to an empty placeholder).
 */
export async function buildNewSnapshotComposite({ actualPath, compositePath }) {
  const actual = await readPng(actualPath)
  const placeholder = blank(actual.width, actual.height, [24, 28, 32])
  await writePng(compositePath, buildComposite([placeholder, actual]))
  return { width: actual.width, height: actual.height }
}
