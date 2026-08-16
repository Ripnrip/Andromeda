// Screenshot a running Andromeda web instance.
// Usage: node shot.mjs <baseUrl> <outDir>
import { chromium } from "playwright";
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

const browser = await chromium.launch();
for (const vp of VIEWPORTS) {
  const ctx = await browser.newContext({
    viewport: { width: vp.width, height: vp.height },
    deviceScaleFactor: 2,
  });
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

// Light theme capture (only meaningful on branches with the toggle).
// The toggle button is the last button in the nav / design header.
for (const vp of VIEWPORTS) {
  const ctx = await browser.newContext({
    viewport: { width: vp.width, height: vp.height },
    deviceScaleFactor: 2,
  });
  const page = await ctx.newPage();
  for (const route of ROUTES) {
    const url = `${base}${route.path}`;
    await page.goto(url, { waitUntil: "networkidle" });
    let theme = await page.evaluate(() =>
      document.documentElement.classList.contains("dark") ? "dark" : "light"
    );
    if (theme === "dark") {
      const toggle = page
        .locator('button[aria-label^="Switch to"]')
        .first();
      if ((await toggle.count()) > 0) {
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
      } else {
        theme = null;
      }
    }
    if (theme === "light") {
      const file = `${outDir}/${route.name}--${vp.name}--light.png`;
      await page.screenshot({ path: file, fullPage: true });
      console.log(`shot ${route.name} ${vp.name} light: on`);
    } else {
      console.log(`skip light ${route.name} ${vp.name}: theme=${theme}`);
    }
  }
  await ctx.close();
}

await browser.close();
console.log("done");
