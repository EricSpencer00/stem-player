import { existsSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import puppeteer from "puppeteer";
import { startStaticServer } from "../tests/browser-server.mjs";

const repoRoot = resolve(new URL("..", import.meta.url).pathname);
const outDir = resolve(repoRoot, "appstore-screenshots", "out", "ipad");
const chromes = [
  process.env.PUPPETEER_EXECUTABLE_PATH,
  "/Users/eric/Library/Caches/ms-playwright/chromium-1228/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
].filter(Boolean);

function chromium() {
  return chromes.find((candidate) => existsSync(candidate));
}

const executablePath = chromium();
if (!executablePath) {
  throw new Error("No Chromium binary found. Set PUPPETEER_EXECUTABLE_PATH.");
}

mkdirSync(outDir, { recursive: true });
const server = await startStaticServer({ root: repoRoot, port: 0 });
const browser = await puppeteer.launch({
  headless: true,
  executablePath,
  args: ["--no-sandbox", "--disable-setuid-sandbox"],
});

try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1024, height: 1366, deviceScaleFactor: 2 });
  await page.goto(`${server.url}/appstore-screenshots/screenshots-v3.html`, {
    waitUntil: "networkidle2",
  });
  await page.screenshot({ path: resolve(outDir, "screenshots-overview.png"), fullPage: true });
  console.log(`Exported iPad overview screenshot to ${outDir}`);
} finally {
  await browser.close();
  await server.close();
}
