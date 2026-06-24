// Exports all 4 App Store screenshots at 1284×2778 (iPhone 6.5" @3x)
// Usage: node appstore-screenshots/export.js

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import puppeteer from 'puppeteer';
import { startStaticServer } from '../tests/browser-server.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(__dirname, 'exported-v3');
const VIEWPORT = { width: 428, height: 926, deviceScaleFactor: 3 };
const EXECUTABLE =
  process.env.PUPPETEER_EXECUTABLE_PATH ||
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

(async () => {
  const server = await startStaticServer({ root: path.resolve(__dirname, '..') });
  fs.mkdirSync(OUT, { recursive: true });
  for (const file of fs.readdirSync(OUT)) {
    if (/^stemacle-appstore-\d+\.png$/.test(file)) {
      fs.rmSync(path.join(OUT, file));
    }
  }

  const browser = await puppeteer.launch({
    executablePath: EXECUTABLE,
    defaultViewport: VIEWPORT,
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });

  try {
    const page = await browser.newPage();
    await page.goto(`${server.url}/appstore-screenshots/screenshots-v3.html`, {
      waitUntil: 'networkidle2',
    });
    await page.waitForSelector('.shot');

    for (let i = 1; i <= 4; i++) {
      const shot = await page.$(`#s${i}`);
      if (!shot) {
        console.error(`#s${i} not found`);
        continue;
      }

      const out = path.join(OUT, `stemacle-appstore-${i}.png`);
      await shot.screenshot({ path: out, type: 'png' });
      console.log(`✓  ${out}`);
    }
  } finally {
    await browser.close();
    await server.close();
  }
  console.log(`\nDone. Check ${OUT}/`);
})();
