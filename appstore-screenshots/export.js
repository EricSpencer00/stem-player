// Exports all 5 App Store screenshots at 1284×2778 (iPhone 6.5" @3x)
// Usage: node appstore-screenshots/export.js
// Server must be running: python3 -m http.server 7893 --directory .

import puppeteer from 'puppeteer';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const URL = 'http://localhost:7893/appstore-screenshots/screenshots-v3.html';
const OUT = path.join(__dirname, 'exported-v3');

(async () => {
  fs.mkdirSync(OUT, { recursive: true });

  const browser = await puppeteer.launch({
    defaultViewport: { width: 428, height: 926, deviceScaleFactor: 3 },
    headless: true,
  });

  const page = await browser.newPage();
  await page.goto(URL, { waitUntil: 'networkidle0' });
  await page.waitForSelector('.shot');

  for (let i = 1; i <= 5; i++) {
    const shot = await page.$(`#s${i}`);
    if (!shot) { console.error(`#s${i} not found`); continue; }

    const out = path.join(OUT, `stemacle-appstore-${i}.png`);
    await shot.screenshot({ path: out, type: 'png' });
    console.log(`✓  ${out}`);
  }

  await browser.close();
  console.log(`\nDone. Check ${OUT}/`);
})();
