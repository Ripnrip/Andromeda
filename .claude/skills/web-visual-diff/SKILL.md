---
name: web-visual-diff
description: Andromeda web surface visual regression — Playwright screenshot capture of every route (desktop/mobile × dark/light), pixelmatch diff base-vs-head, left–right composite strips, and the markdown diff table the CI bot posts on every web PR. Use when changing anything under web/, reviewing a web PR, or when asked for screenshot diffs / visual evidence of website changes.
---

# Andromeda Web Visual Diff

**The browser equivalent of the repo's pointfree snapshot suite.** Every PR
touching `web/**` (or this tooling) gets an automated screenshot comparison of
base vs head, posted as a PR comment with a markdown table and left–right
strips. Composites live on the `visual/pr-<n>` branch; full-size shots in the
workflow artifacts.

## Architecture (policy-compliant)

The repo forbids project-maintained shell automation, so the pipeline
orchestrator is a **typed Swift executable** (`scripts/visual` SwiftPM
package, `VisualDiffCore` library + thin `visual-diff` main). The browser
capture/differ stay Node (`shot.mjs` / `diff.mjs`) — Playwright and pixelmatch
are JS-native — and the runner invokes them as subprocesses. The workflow only
calls the runner:

```text
visual-diff capture --side base|head --sha <sha> --port <n>
visual-diff diff    --base shots/base --head shots/head --out out
visual-diff publish --pr <n> --repo <owner/name>
visual-diff comment --pr <n> --repo <owner/name>
```

Build + test the runner: `swift build && swift test --package-path scripts/visual`
(9 tests: comment builder embed cap, flag parsing, tooling-dir resolution).

CI copies `scripts/visual` to `$RUNNER_TEMP/visual-tooling` **before** any
base checkout — the tooling must survive the tree being rewritten to the base
SHA (which predates `scripts/visual`).

## What the pipeline does

1. Builds **base** (`pull_request.base.sha`) and **head** separately.
2. Screenshots every route in `scripts/visual/shot.mjs` (`ROUTES`) at
   **1440×900** and **390×844** (2× DPR, full page), plus a **light-theme**
   pass on pages with a theme toggle (`button[aria-label^="Switch to"]`).
3. `scripts/visual/diff.mjs` pixel-diffs each pair:
   - `<0.1%` changed pixels → **unchanged (AA noise)** — fonts rasterize
     slightly differently run to run; do not chase this.
   - differing dimensions → both padded with magenta, size change noted.
   - emits `out/diffs/*` heatmaps, `out/composites/*` left–right strips
     (left = base, right = head), `out/report.md` table, `out/changed.txt`.
4. The workflow pushes composites to `visual/pr-<n>` and **upserts** the PR
   comment marked `<!-- web-visual-diff -->` (one comment per PR, updated on
   every push — it never spams new comments).

## Reading a diff table

| Verdict | Meaning |
|---|---|
| ✅ unchanged | pixel-identical (or sub-noise) |
| 🔴 N% | N% of pixels differ — inspect the composite strip |
| 🆕 new | shot exists only in head (e.g. new page or new light pass) |
| 🗑️ removed | captured in base, gone in head |

Height changes are expected for content-affecting PRs — the % is against the
**padded union** canvas, so a height change alone reports a small %.

## Running it locally (before pushing)

```console
cd scripts/visual && swift build && cd ../..
scripts/visual/.build/debug/visual-diff capture --side base --sha <base-sha> --port 4173
scripts/visual/.build/debug/visual-diff capture --side head --sha <head-sha> --port 4174
scripts/visual/.build/debug/visual-diff diff --base shots/base --head shots/head --out out
```

`npm install` (not `ci`) at the repo root is deliberate when the optional
native binary is missing — npm/cli#4828 can skip `lightningcss-*` platform
packages; deleting `package-lock.json` + `node_modules` and reinstalling fixes
it (the runner probes and does this automatically). **Never commit the
regenerated lockfile as part of a fix** — the publish step restores it.

## Adding a page

Add it to `ROUTES` in `scripts/visual/shot.mjs`. Every new route multiplies
shots (2 viewports × 2 themes) — keep the list to real surfaces.

## Rules

- Do not "fix" a red diff by re-recording or loosening the threshold; the diff
  is the evidence. If the change is intentional, say so in the PR and move on.
- The bot comment is evidence, not decoration: PRs touching `web/**` merge
  only with the visual diff comment present and its 🔴 rows explained.
- Never edit `.github/workflows/web-visual-diff.yml` to skip the comment step.
- The `visual/pr-*` branches are disposable artifacts — force-pushed by CI;
  never branch off them.
