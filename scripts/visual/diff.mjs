// Visual diff for Andromeda web PRs — the pointfree-snapshot equivalent for browsers.
// Compares two screenshot directories (base vs head), emits:
//   out/diffs/<name>.diff.png        heat-overlay changed pixels
//   out/composites/<name>.png        left-right strip (base | head)
//   out/report.md                    markdown table for the PR comment
// Usage: node diff.mjs <baseDir> <headDir> <outDir>
import fs from "node:fs";
import path from "node:path";
import { PNG } from "pngjs";
import pixelmatch from "pixelmatch";

const [, , baseDir, headDir, outDir] = process.argv;
if (!baseDir || !headDir || !outDir) {
  console.error("usage: node diff.mjs <baseDir> <headDir> <outDir>");
  process.exit(1);
}
for (const d of [`${outDir}/diffs`, `${outDir}/composites`]) {
  fs.mkdirSync(d, { recursive: true });
}

const readPng = (p) => PNG.sync.read(fs.readFileSync(p));
const padTo = (png, w, h) => {
  if (png.width === w && png.height === h) return png;
  const out = new PNG({ width: w, height: h });
  // Fill with a signal magenta so padded regions read as "missing content",
  // not as an innocent background color.
  for (let i = 0; i < out.data.length; i += 4) {
    out.data[i] = 255; out.data[i + 1] = 0; out.data[i + 2] = 255; out.data[i + 3] = 255;
  }
  PNG.bitblt(png, out, 0, 0, png.width, png.height, 0, 0);
  return out;
};

const baseFiles = fs.readdirSync(baseDir).filter((f) => f.endsWith(".png"));
const headFiles = fs.readdirSync(headDir).filter((f) => f.endsWith(".png"));
const all = [...new Set([...baseFiles, ...headFiles])].sort();

const rows = [];
for (const file of all) {
  const inBase = baseFiles.includes(file);
  const inHead = headFiles.includes(file);
  const label = file.replace(/\.png$/, "");

  if (!inBase) {
    rows.push({ label, status: "new", pct: null, note: "page/shot only exists in head" });
    fs.copyFileSync(path.join(headDir, file), path.join(outDir, "composites", file));
    continue;
  }
  if (!inHead) {
    rows.push({ label, status: "removed", pct: null, note: "page/shot no longer captured in head" });
    continue;
  }

  const a = readPng(path.join(baseDir, file));
  const b = readPng(path.join(headDir, file));
  const w = Math.max(a.width, b.width);
  const h = Math.max(a.height, b.height);
  const A = padTo(a, w, h);
  const B = padTo(b, w, h);
  const diffPng = new PNG({ width: w, height: h });
  const changed = pixelmatch(A.data, B.data, diffPng.data, w, h, {
    threshold: 0.1,
    alpha: 0.3,
    includeAA: false,
  });
  const total = w * h;
  const pct = (changed / total) * 100;

  fs.writeFileSync(path.join(outDir, "diffs", `${label}.diff.png`), PNG.sync.write(diffPng));

  // Left-right composite: base | 12px gutter | head, scaled to 700px per side.
  const side = 700;
  const scale = Math.min(side / w, 1);
  const cw = Math.round(w * scale);
  const ch = Math.round(h * scale);
  const strip = new PNG({ width: cw * 2 + 12, height: ch });
  const aSmall = scalePng(A, cw, ch);
  const bSmall = scalePng(B, cw, ch);
  PNG.bitblt(aSmall, strip, 0, 0, cw, ch, 0, 0);
  PNG.bitblt(bSmall, strip, 0, 0, cw, ch, cw + 12, 0);
  fs.writeFileSync(path.join(outDir, "composites", file), PNG.sync.write(strip));

  const verdictStatus =
    changed === 0 ? "unchanged" : pct < 0.1 ? "noise" : "changed";
  const sizeNote =
    a.width !== b.width || a.height !== b.height
      ? `size ${a.width}×${a.height} → ${b.width}×${b.height}`
      : "";
  rows.push({ label, status: verdictStatus, pct, note: sizeNote });
}

function scalePng(src, w, h) {
  // Nearest-neighbor downscale — diff pixels already computed at full res;
  // this is only for the human-readable strip.
  const out = new PNG({ width: w, height: h });
  for (let y = 0; y < h; y++) {
    const sy = Math.floor((y * src.height) / h);
    for (let x = 0; x < w; x++) {
      const sx = Math.floor((x * src.width) / w);
      const si = (sy * src.width + sx) * 4;
      const di = (y * w + x) * 4;
      out.data[di] = src.data[si];
      out.data[di + 1] = src.data[si + 1];
      out.data[di + 2] = src.data[si + 2];
      out.data[di + 3] = src.data[si + 3];
    }
  }
  return out;
}

const verdict = (r) =>
  r.status === "new" ? "🆕 new" :
  r.status === "removed" ? "🗑️ removed" :
  r.status === "unchanged" ? "✅ unchanged" :
  r.status === "noise" ? "✅ unchanged (sub-0.1% AA noise)" :
  `🔴 ${r.pct.toFixed(2)}%`;

let md = "## 🖼️ Web visual diff — base vs this PR\n\n";
md += "Left = base (main), right = head (this PR). Diff heatmaps in the `diffs/` artifacts.\n\n";
md += "| Page | Viewport / theme | Verdict | Notes |\n";
md += "|---|---|---|---|\n";
for (const r of rows) {
  const [page, ...rest] = r.label.split("--");
  md += `| \`${page}\` | ${rest.join(" / ") || "default"} | ${verdict(r)} | ${r.note} |\n`;
}
const changedCount = rows.filter((r) => r.status === "changed" || r.status === "new").length;
md += `\n**${changedCount}** of ${rows.length} shots changed.\n`;

fs.writeFileSync(path.join(outDir, "report.md"), md);
// Machine-readable list of composites worth embedding in the PR comment.
// Changed strips first (highest evidence value), then new shots; the comment
// builder caps embeds and links the rest.
fs.writeFileSync(
  path.join(outDir, "changed.txt"),
  rows
    .filter((r) => r.status === "changed" || r.status === "new")
    .sort((a, b) => (a.status === "changed" ? -1 : 1) - (b.status === "changed" ? -1 : 1))
    .map((r) => `${r.label}.png`)
    .join("\n") + "\n"
);
console.log(md);
