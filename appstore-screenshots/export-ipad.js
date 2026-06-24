// Exports the iPad App Store screenshot at 2048×2732 (13-inch iPad portrait).
// Usage: node appstore-screenshots/export-ipad.js

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import puppeteer from 'puppeteer';
import { startStaticServer } from '../tests/browser-server.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(__dirname, 'exported-ipad');
const EXECUTABLE =
  process.env.PUPPETEER_EXECUTABLE_PATH ||
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const IPAD_UA =
  'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

(async () => {
  const server = await startStaticServer({ root: path.resolve(__dirname, '..') });
  const browser = await puppeteer.launch({
    executablePath: EXECUTABLE,
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });

  try {
    fs.mkdirSync(OUT, { recursive: true });

    const page = await browser.newPage();
    await page.setUserAgent(IPAD_UA);
    await page.setViewport({
      width: 1024,
      height: 1366,
      deviceScaleFactor: 2,
      isMobile: true,
      hasTouch: true,
    });

    await page.goto(`${server.url}/native/index.html`, { waitUntil: 'networkidle2' });
    const out = path.join(OUT, 'stemacle-ipad-13.png');
    await page.screenshot({ path: out, fullPage: false });
    console.log(`✓  ${out}`);
  } finally {
    await browser.close();
    await server.close();
  }
})();
