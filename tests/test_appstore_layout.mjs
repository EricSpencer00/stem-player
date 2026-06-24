import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';
import puppeteer from 'puppeteer';

import { startStaticServer } from './browser-server.mjs';

const REPO_ROOT = resolve(new URL('..', import.meta.url).pathname);

const CANDIDATE_CHROMES = [
  process.env.PUPPETEER_EXECUTABLE_PATH,
  '/Users/eric/Library/Caches/ms-playwright/chromium-1228/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
].filter(Boolean);

function findChromium() {
  for (const candidate of CANDIDATE_CHROMES) {
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

async function launchBrowser() {
  const executable = findChromium();
  if (!executable) {
    throw new Error('No Chromium binary found for the App Store layout test.');
  }
  return puppeteer.launch({
    headless: true,
    executablePath: executable,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });
}

function intersects(a, b) {
  return !(
    a.right <= b.left ||
    a.left >= b.right ||
    a.bottom <= b.top ||
    a.top >= b.bottom
  );
}

function contains(outer, inner) {
  return (
    inner.left >= outer.left &&
    inner.top >= outer.top &&
    inner.right <= outer.right &&
    inner.bottom <= outer.bottom
  );
}

test('App Store screenshots keep headline, body, and art blocks from colliding', async () => {
  const server = await startStaticServer({ root: REPO_ROOT, port: 0 });
  const browser = await launchBrowser();

  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 428, height: 926, deviceScaleFactor: 3 });
    await page.goto(`${server.url}/appstore-screenshots/screenshots-v3.html`, {
      waitUntil: 'networkidle2',
    });

    const layout = await page.evaluate(() => {
      const shotIds = ['s1', 's2', 's3', 's4'];
      const selectors = {
        s1: [
          { selector: '.s1-copy', contain: true },
          { selector: '.s1-track', contain: true },
          { selector: '.s1-result', contain: true },
        ],
        s2: [
          { selector: '.s2-copy', contain: true },
          { selector: '.s2-files', contain: true },
          { selector: '.s2-flow', contain: true },
        ],
        s3: [
          { selector: '.s3-copy', contain: true },
          { selector: '.s3-panel', contain: true },
        ],
        s4: [
          { selector: '.s4-copy', contain: true },
          { selector: '.s4-panel', contain: true },
        ],
      };

      return Object.fromEntries(
        shotIds.map((shotId) => {
          const shot = document.getElementById(shotId);
          const shotRect = shot?.getBoundingClientRect() ?? null;
          const blocks = (selectors[shotId] || [])
            .map(({ selector, contain }) => {
              const el = shot?.querySelector(selector);
              const rect = el?.getBoundingClientRect();
              return rect
                ? {
                    selector,
                    contain,
                    left: rect.left,
                    top: rect.top,
                    right: rect.right,
                    bottom: rect.bottom,
                    width: rect.width,
                    height: rect.height,
                  }
                : null;
            })
            .filter(Boolean);

          return [shotId, { shot: shotRect && {
            left: shotRect.left,
            top: shotRect.top,
            right: shotRect.right,
            bottom: shotRect.bottom,
            width: shotRect.width,
            height: shotRect.height,
          }, blocks }];
        }),
      );
    });

    for (const [shotId, info] of Object.entries(layout)) {
      assert.ok(info.shot, `missing shot container for ${shotId}`);
      for (const block of info.blocks) {
        if (block.contain) {
          assert.ok(
            contains(info.shot, block),
            `${shotId} block ${block.selector} should stay within the shot bounds`,
          );
        }
      }

      for (let i = 0; i < info.blocks.length; i += 1) {
        for (let j = i + 1; j < info.blocks.length; j += 1) {
          const a = info.blocks[i];
          const b = info.blocks[j];
          assert.ok(
            !intersects(a, b),
            `${shotId} blocks ${a.selector} and ${b.selector} should not overlap`,
          );
        }
      }
    }
  } finally {
    await browser.close();
    await server.close();
  }
});

test('App Store screenshots keep the import and control compositions balanced', async () => {
  const server = await startStaticServer({ root: REPO_ROOT, port: 0 });
  const browser = await launchBrowser();

  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 428, height: 926, deviceScaleFactor: 3 });
    await page.goto(`${server.url}/appstore-screenshots/screenshots-v3.html`, {
      waitUntil: 'networkidle2',
    });

    const metrics = await page.evaluate(() => {
      const toolbar = document.querySelector('#s4 .toolbar-btn');
      const toolbarRange = document.createRange();
      toolbarRange.selectNodeContents(toolbar);

      const toolbarRect = toolbar?.getBoundingClientRect();
      const toolbarTextRect = toolbarRange.getBoundingClientRect();
      const noteRect = document.querySelector('#s2 .import-note')?.getBoundingClientRect();
      const discRect = document.querySelector('#s2 .drop-disc')?.getBoundingClientRect();
      const sliders = Array.from(document.querySelectorAll('#s4 .slider')).map((slider) => ({
        width: slider.getBoundingClientRect().width,
        stem:
          slider
            .closest('.control-strip')
            ?.querySelector('.stem-name')
            ?.textContent?.trim() ?? 'unknown',
      }));

      return {
        toolbar: toolbarRect
          ? {
              pillCenterX: (toolbarRect.left + toolbarRect.right) / 2,
              textCenterX: (toolbarTextRect.left + toolbarTextRect.right) / 2,
            }
          : null,
        importFlow:
          noteRect && discRect
            ? {
                noteCenterY: (noteRect.top + noteRect.bottom) / 2,
                discCenterY: (discRect.top + discRect.bottom) / 2,
              }
            : null,
        sliders,
      };
    });

    assert.ok(metrics.toolbar, 'missing screen 4 toolbar button');
    assert.ok(
      Math.abs(metrics.toolbar.pillCenterX - metrics.toolbar.textCenterX) <= 24,
      'screen 4 mute-all label should sit near the center of its control',
    );

    assert.ok(metrics.importFlow, 'missing screen 2 import flow');
    assert.ok(
      Math.abs(metrics.importFlow.noteCenterY - metrics.importFlow.discCenterY) <= 32,
      'screen 2 import note and drop disc should share a visual centerline',
    );

    for (const slider of metrics.sliders) {
      assert.ok(
        slider.width >= 80,
        `screen 4 slider for ${slider.stem} should keep a usable width`,
      );
    }
  } finally {
    await browser.close();
    await server.close();
  }
});
