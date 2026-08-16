#!/usr/bin/env node
/**
 * Re-renders `report.md` from the `report.json` produced by a completed run.
 *
 * CI needs two passes: the run itself has no public URL for the composite images
 * yet, and the URL only exists after they are pushed to the image branch. This
 * regenerates the Markdown from the recorded results so the table can embed the
 * images — without re-running the browser, which would risk a different result
 * than the one the check already reported.
 */

import { readFile, writeFile } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"

import { renderMarkdown } from "./lib/report.mjs"

const HERE = path.dirname(fileURLToPath(import.meta.url))
const OUTPUT_DIR = path.join(HERE, "__Output__")

async function main() {
  const raw = await readFile(path.join(OUTPUT_DIR, "report.json"), "utf8")
  const report = JSON.parse(raw)

  const markdown = renderMarkdown({
    results: report.results,
    imageBaseUrl: process.env.WEB_SNAPSHOT_IMAGE_BASE_URL || null,
    artifactUrl: process.env.WEB_SNAPSHOT_ARTIFACT_URL || null,
    commitSha: report.commitSha ?? "unknown",
    recordMode: Boolean(report.recordMode),
    durationMs: report.durationMs ?? 0,
  })

  await writeFile(path.join(OUTPUT_DIR, "report.md"), `${markdown}\n`)
  process.stdout.write("report.md re-rendered with image URLs\n")
}

main().catch((error) => {
  process.stderr.write(`${error.stack ?? error.message}\n`)
  process.exitCode = 1
})
