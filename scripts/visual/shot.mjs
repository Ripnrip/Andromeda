// Screenshot a running Andromeda web instance.
// Usage: node shot.mjs <baseUrl> <outDir>
import { chromium } from "playwright";
import { PNG } from "pngjs";
import fs from "node:fs";

const base = process.argv[2];
const outDir = process.argv[3];
fs.mkdirSync(outDir, { recursive: true });

const ROUTES = [
  { path: "/", name: "landing" },
  { path: "/banner", name: "banner" },
  { path: "/demo", name: "demo" },
  { path: "/design", name: "design" },
];

const VIEWPORTS = [
  { name: "desktop", width: 1440, height: 900 },
  { name: "mobile", width: 390, height: 844 },
];

// Motion is disabled in every context: the site's CSS runs perpetual
// marquee/pan/pulse animations that only stop under prefers-reduced-motion.
// Without this, identical base and head pages can be captured at different
// animation phases and report false visual changes.
const CONTEXT_OPTIONS = (vp) => ({
  viewport: { width: vp.width, height: vp.height },
  deviceScaleFactor: 2,
  reducedMotion: "reduce",
});

/// Mean luminance of a saved screenshot (0–255), sampled for speed.
async function meanLuminance(file) {
  const png = PNG.sync.read(fs.readFileSync(file));
  let sum = 0;
  let n = 0;
  const stride = 4 * 97; // sample ~1% of pixels
  for (let i = 0; i < png.data.length; i += stride) {
    sum += (png.data[i] + png.data[i + 1] + png.data[i + 2]) / 3;
    n++;
  }
  return sum / n;
}

const LIGHT_MIN_LUMINANCE = 150;

const browser = await chromium.launch();
for (const vp of VIEWPORTS) {
  const ctx = await browser.newContext(CONTEXT_OPTIONS(vp));
  const page = await ctx.newPage();
  for (const route of ROUTES) {
    const url = `${base}${route.path}`;
    await page.goto(url, { waitUntil: "networkidle" });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(700);
    const file = `${outDir}/${route.name}--${vp.name}.png`;
    await page.screenshot({ path: file, fullPage: true });
    const bytes = fs.statSync(file).size;
    console.log(`shot ${route.name} ${vp.name}: ${(bytes / 1024).toFixed(0)}KB`);
  }
  await ctx.close();
}

// Light theme capture. Only meaningful when the surface actually has a theme
// toggle; a shot only earns the `--light` name when its pixels measure
// bright — class/DOM heuristics alone have mislabeled dark renders before.
for (const vp of VIEWPORTS) {
  const ctx = await browser.newContext(CONTEXT_OPTIONS(vp));
  const page = await ctx.newPage();
  for (const route of ROUTES) {
    const url = `${base}${route.path}`;
    await page.goto(url, { waitUntil: "networkidle" });
    const toggle = page.locator('button[aria-label^="Switch to"]').first();
    const hasToggle = (await toggle.count()) > 0;
    let theme = hasToggle
      ? await page.evaluate(() =>
          document.documentElement.classList.contains("dark") ? "dark" : "light"
        )
      : null;
    if (theme === "dark" && hasToggle) {
      try {
        await toggle.click({ timeout: 2000 });
        await page.evaluate(() => document.fonts.ready);
        await page.waitForTimeout(500);
        theme = await page.evaluate(() =>
          document.documentElement.classList.contains("dark") ? "dark" : "light"
        );
      } catch {
        theme = "toggle-failed";
      }
    }
    if (theme === "light") {
      const file = `${outDir}/${route.name}--${vp.name}--light.png`;
      await page.screenshot({ path: file, fullPage: true });
      const luminance = await meanLuminance(file);
      if (luminance >= LIGHT_MIN_LUMINANCE) {
        console.log(`shot ${route.name} ${vp.name} light: on (luminance ${luminance.toFixed(0)})`);
      } else {
        // The DOM claimed light but the render stayed dark — refuse the
        // label instead of shipping a mislabeled duplicate.
        fs.unlinkSync(file);
        console.log(
          `skip light ${route.name} ${vp.name}: rendered dark (luminance ${luminance.toFixed(0)} < ${LIGHT_MIN_LUMINANCE})`
        );
      }
    } else {
      console.log(`skip light ${route.name} ${vp.name}: theme=${theme}`);
    }
  }
  await ctx.close();
}

await browser.close();
console.log("done");
