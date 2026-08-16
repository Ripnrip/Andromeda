/**
 * Report rendering: the Markdown table posted to the PR, plus a self-contained
 * HTML report uploaded as a CI artifact for full-resolution review.
 */

const STATUS_META = {
  pass: { icon: "✅", label: "match" },
  fail: { icon: "❌", label: "changed" },
  new: { icon: "🆕", label: "new baseline" },
  recorded: { icon: "📸", label: "recorded" },
  obsolete: { icon: "🗑️", label: "orphaned baseline" },
  error: { icon: "💥", label: "capture failed" },
}

const STICKY_MARKER = "<!-- andromeda-web-snapshots -->"

export { STICKY_MARKER }

/** Formats a pixel ratio as a short percentage string. */
function percent(ratio) {
  if (!Number.isFinite(ratio)) return "—"
  if (ratio === 0) return "0%"
  if (ratio < 0.0001) return "<0.01%"
  return `${(ratio * 100).toFixed(2)}%`
}

function dims(size) {
  return Array.isArray(size) ? `${size[0]}×${size[1]}` : "—"
}

/**
 * Renders the PR comment body.
 *
 * `imageBaseUrl` is optional: when the workflow was able to publish the composite
 * PNGs (same-repo PR, write-scoped token) the table embeds them inline; otherwise
 * it degrades to the artifact link so fork PRs still get the numbers.
 *
 * @param {{results: any[], imageBaseUrl?: string|null, artifactUrl?: string|null,
 *   commitSha: string, recordMode: boolean, durationMs: number}} input
 */
export function renderMarkdown({ results, imageBaseUrl, artifactUrl, commitSha, recordMode, durationMs }) {
  const counts = results.reduce((acc, result) => {
    acc[result.status] = (acc[result.status] ?? 0) + 1
    return acc
  }, {})

  const failed = (counts.fail ?? 0) + (counts.new ?? 0) + (counts.error ?? 0)
  const headline = recordMode
    ? `📸 **Web snapshots re-recorded** — ${results.length} baseline(s) rewritten. Download the \`web-snapshot-baselines\` artifact and commit it.`
    : failed === 0
      ? `✅ **Web snapshots match** — ${results.length} scenario(s), no visual drift.`
      : `❌ **Web snapshots changed** — ${failed} of ${results.length} scenario(s) need review.`

  const lines = [
    STICKY_MARKER,
    "### Web snapshot tests",
    "",
    headline,
    "",
    "| Scenario | Route | Viewport | Status | Diff px | Diff % | Baseline → Actual |",
    "| --- | --- | --- | :--: | --: | --: | --- |",
  ]

  for (const result of results) {
    const meta = STATUS_META[result.status] ?? { icon: "❔", label: result.status }
    const sizeCell = result.dimensionsChanged
      ? `⚠️ ${dims(result.baselineSize)} → ${dims(result.actualSize)}`
      : dims(result.actualSize ?? result.baselineSize)

    lines.push(
      [
        `\`${result.name}\``,
        `\`${result.path}\``,
        result.viewport ? `${result.viewport[0]}×${result.viewport[1]}` : "—",
        `${meta.icon} ${meta.label}`,
        result.diffPixels == null ? "—" : result.diffPixels.toLocaleString("en-US"),
        percent(result.diffRatio),
        sizeCell,
      ].join(" | "),
    )
  }

  lines.push("")

  const visual = results.filter((result) => result.compositeFile && result.status !== "pass")

  if (visual.length > 0) {
    lines.push("#### Left → right: baseline · actual · diff")
    lines.push("")
    lines.push(
      "_Accent bar above each panel: <kbd>green</kbd> baseline · <kbd>blue</kbd> actual · <kbd>red</kbd> diff mask._",
    )
    lines.push("")

    for (const result of visual) {
      lines.push(`<details${visual.length === 1 ? " open" : ""}><summary><code>${result.name}</code> — ${percent(result.diffRatio)} of pixels changed</summary>`)
      lines.push("")
      if (imageBaseUrl) {
        lines.push(`<img src="${imageBaseUrl}/${result.compositeFile}" alt="${result.name} baseline, actual and diff side by side" width="100%">`)
      } else {
        lines.push(
          `> Composite image not published (fork PR or missing write token). See \`${result.compositeFile}\` in the CI artifact.`,
        )
      }
      lines.push("")
      lines.push("</details>")
      lines.push("")
    }
  }

  const footer = []
  if (artifactUrl) footer.push(`[Full-resolution artifact](${artifactUrl})`)
  footer.push(`commit \`${commitSha.slice(0, 7)}\``)
  footer.push(`${(durationMs / 1000).toFixed(1)}s`)

  lines.push("---")
  lines.push("")
  lines.push(
    `${footer.join(" · ")}<br>Intentional change? Push a commit whose message contains \`[record-web-snapshots]\`, then commit the rewritten baselines from the CI artifact.`,
  )

  return lines.join("\n")
}

/** Renders a standalone HTML report with an opacity slider for close inspection. */
export function renderHtml({ results, commitSha, recordMode }) {
  const cards = results
    .map((result) => {
      const meta = STATUS_META[result.status] ?? { icon: "❔", label: result.status }
      const images = ["baselineFile", "actualFile", "diffFile"]
        .map((key) => (result[key] ? `<figure><figcaption>${key.replace("File", "")}</figcaption><img src="${result[key]}" loading="lazy"></figure>` : ""))
        .join("")

      return `
      <section class="card" data-status="${result.status}">
        <header>
          <h2>${result.name}</h2>
          <span class="badge">${meta.icon} ${meta.label}</span>
          <code>${result.path} · ${result.viewport ? `${result.viewport[0]}×${result.viewport[1]}` : "—"}</code>
          <span class="metric">${percent(result.diffRatio)} · ${result.diffPixels ?? "—"} px</span>
        </header>
        ${result.error ? `<pre class="error">${escapeHtml(result.error)}</pre>` : ""}
        <div class="panels">${images}</div>
      </section>`
    })
    .join("")

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Andromeda web snapshots · ${commitSha.slice(0, 7)}</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; padding: 2rem; background: #0a0c0e; color: #e6eef2;
         font: 14px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
  h1 { font-size: 1.25rem; letter-spacing: .18em; text-transform: uppercase; color: #7fe3e8; }
  .card { border: 1px solid #1d262b; border-radius: 8px; padding: 1rem; margin-bottom: 1.5rem; background: #0e1216; }
  .card[data-status="pass"] { border-color: #1f3d2b; }
  .card[data-status="fail"] { border-color: #4d2027; }
  header { display: flex; flex-wrap: wrap; gap: .75rem; align-items: baseline; margin-bottom: 1rem; }
  h2 { font-size: 1rem; margin: 0; }
  .badge { padding: .1rem .5rem; border: 1px solid #2a353c; border-radius: 999px; font-size: .75rem; }
  .metric { margin-left: auto; color: #9fb0b8; }
  code { color: #9fb0b8; }
  .panels { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 1rem; }
  figure { margin: 0; }
  figcaption { font-size: .7rem; letter-spacing: .2em; text-transform: uppercase; color: #7fe3e8; margin-bottom: .35rem; }
  img { width: 100%; border: 1px solid #1d262b; border-radius: 4px; background: #000; }
  pre.error { color: #ff8fa0; white-space: pre-wrap; }
</style>
</head>
<body>
<h1>Andromeda web snapshots</h1>
<p>commit <code>${commitSha}</code>${recordMode ? " · <strong>record mode</strong>" : ""}</p>
${cards}
</body>
</html>`
}

function escapeHtml(value) {
  return String(value).replace(/[&<>]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[char])
}
