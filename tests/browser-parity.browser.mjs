// Browser parity tests for the canonical web app and the desktop shell.
//
// These tests run the actual HTML in headless Chromium via Puppeteer and
// assert the user-facing surface that the project documents as the
// parity contract. The goal is to catch visual / interactive regressions
// in the real DOM that the in-process fake-DOM tests in stem-player.test.mjs
// cannot reach — e.g. whether the loop buttons are wired to a real
// <button class="loop-btn" data-stem="drums">, or whether the audio
// splitter end-to-end finishes on a real .mp3 file.
//
// Run with:  npm run test:browser
//
// The tests rely on a Chromium binary on disk. Puppeteer's bundled
// Chrome (149) is not present on this machine; the project's
// appstore-screenshots/export.js uses the same workaround — point
// PUPPETEER_EXECUTABLE_PATH at the existing "Google Chrome for Testing"
// under /Users/eric/Library/Caches/ms-playwright/chromium-1228/. The
// helper below does this automatically if the binary is present.

import assert from 'node:assert/strict';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';
import puppeteer from 'puppeteer';

import { startStaticServer } from './browser-server.mjs';

const REPO_ROOT = resolve(new URL('..', import.meta.url).pathname);

// ---- browser launcher ----

const CANDIDATE_CHROMES = [
  process.env.PUPPETEER_EXECUTABLE_PATH,
  '/Users/eric/Library/Caches/ms-playwright/chromium-1228/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
  process.env.LOCALAPPDATA && `${process.env.LOCALAPPDATA}\\Google\\Chrome\\Application\\chrome.exe`,
  process.env.ProgramFiles && `${process.env.ProgramFiles}\\Google\\Chrome\\Application\\chrome.exe`,
  process.env['ProgramFiles(x86)'] && `${process.env['ProgramFiles(x86)']}\\Google\\Chrome\\Application\\chrome.exe`,
].filter(Boolean);

function findChromium() {
  for (const candidate of CANDIDATE_CHROMES) {
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

const chromiumExecutable = findChromium();
const browserTest = chromiumExecutable ? test : test.skip;

async function launchBrowser() {
  if (!chromiumExecutable) {
    throw new Error(
      'No Chromium binary found. Set PUPPETEER_EXECUTABLE_PATH to a Chrome for Testing binary, ' +
      'or install Chrome at a standard macOS, Linux, or Windows path.',
    );
  }
  return puppeteer.launch({
    headless: true,
    executablePath: chromiumExecutable,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--autoplay-policy=no-user-gesture-required',
    ],
  });
}

// ---- shared test setup ----

let serverHandle = null;
let browser = null;

if (chromiumExecutable) {
  test.before(async () => {
    serverHandle = await startStaticServer({ root: REPO_ROOT, port: 0 });
    browser = await launchBrowser();
  });

  test.after(async () => {
    if (browser) await browser.close();
    if (serverHandle) await serverHandle.close();
  });
}

async function newPage() {
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800, deviceScaleFactor: 1 });
  return page;
}

async function loadApp(page) {
  const url = `${serverHandle.url}/app/index.html`;
  const consoleErrors = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', (err) => consoleErrors.push(String(err)));
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 });
  // Wait for boot to complete (the four stem rows render synchronously,
  // but openPendingNativeTrack is async — give it a tick).
  await page.waitForSelector('.stem-row[data-stem="drums"]', { timeout: 5000 });
  return { url, consoleErrors };
}

function screenshotPath(name) {
  const dir = resolve(REPO_ROOT, 'tests', '__screenshots__');
  mkdirSync(dir, { recursive: true });
  return resolve(dir, name);
}

function intersects(a, b, gap = 0) {
  return !(
    a.right + gap <= b.left ||
    b.right + gap <= a.left ||
    a.bottom + gap <= b.top ||
    b.bottom + gap <= a.top
  );
}

// ===========================================================================
// 1. Boot + structural parity
// ===========================================================================

browserTest('canonical web app boots in a real browser without console errors', async () => {
  const page = await newPage();
  try {
    const { consoleErrors } = await loadApp(page);

    // The app may emit informational warnings (e.g. a sample that
    // can't decode in the test browser); the contract is no *uncaught*
    // error and no ReferenceError. We assert no uncaught errors by
    // checking the page never throws pageerror.
    const uncaught = consoleErrors.filter((m) => /uncaught|ReferenceError|TypeError/i.test(m));
    assert.deepEqual(uncaught, [], `expected no uncaught errors, got: ${uncaught.join(' | ')}`);

    // Capture the idle / boot-time screenshot.
    await page.screenshot({ path: screenshotPath('app-idle.png'), fullPage: false });
  } finally {
    await page.close();
  }
});

browserTest('canonical web app exposes the four stems in the documented visual order', async () => {
  const page = await newPage();
  try {
    await loadApp(page);
    // The visual order on the panel is drums, bass, vocals, melody
    // (matching the Q_RANGE angular layout in the app: bass and
    // vocals get the lower-half real estate, melody the upper half).
    // The all-row is also a .stem-row sibling at the bottom but has
    // no data-stem attribute, so we filter to stems with an attribute.
    const stems = await page.$$eval('.stem-row[data-stem]', (rows) =>
      rows.map((row) => row.getAttribute('data-stem'))
    );
    assert.deepEqual(stems, ['drums', 'bass', 'vocals', 'melody']);

    // The all-row is a stem-row sibling without a data-stem; it must
    // exist (it is the linked-loop row).
    const allRow = await page.$('.stem-row.all-row');
    assert.ok(allRow, 'expected the linked-loop all-row');
  } finally {
    await page.close();
  }
});

browserTest('canonical web app exposes the loop contract: 1/4, 1/2, 1, 2 per stem + an All row', async () => {
  const page = await newPage();
  try {
    await loadApp(page);

    // Each stem row has 4 loop buttons labeled 1/4, 1/2, 1, 2.
    for (const stem of ['drums', 'vocals', 'bass', 'melody']) {
      const labels = await page.$$eval(
        `.loop-row[data-stem="${stem}"] .loop-btn`,
        (buttons) => buttons.map((b) => b.textContent.trim()),
      );
      assert.deepEqual(labels, ['1/4', '1/2', '1', '2'], `bad labels for ${stem}`);
    }

    // The All row exists with the same 4 buttons.
    const allLabels = await page.$$eval(
      '.loop-row[data-stem="all"] .loop-btn',
      (buttons) => buttons.map((b) => b.textContent.trim()),
    );
    assert.deepEqual(allLabels, ['1/4', '1/2', '1', '2']);
  } finally {
    await page.close();
  }
});

browserTest('canonical web app exposes the center circle, play button, and level meter', async () => {
  const page = await newPage();
  try {
    await loadApp(page);

    const ids = await page.evaluate(() => ({
      center: !!document.getElementById('center'),
      btnPlay: !!document.getElementById('btnPlay'),
      levelMeter: !!document.getElementById('levelMeter'),
      device: !!document.getElementById('device'),
      btnMuteAll: !!document.getElementById('btnMuteAll'),
      loopMix: !!document.getElementById('loopAuditionMix'),
      loopSolo: !!document.getElementById('loopAuditionSolo'),
      stemPanel: !!document.getElementById('stems-panel'),
    }));
    for (const [key, present] of Object.entries(ids)) {
      assert.equal(present, true, `expected #${key} in the canonical web app`);
    }
  } finally {
    await page.close();
  }
});

browserTest('canonical web app keeps key idle controls visible and non-overlapping across viewports', async () => {
  const page = await browser.newPage();
  const viewports = [
    { width: 390, height: 844, name: 'phone' },
    { width: 1280, height: 800, name: 'desktop' },
  ];

  try {
    for (const viewport of viewports) {
      await page.setViewport({ ...viewport, deviceScaleFactor: 1 });
      await loadApp(page);
      const boxes = await page.evaluate(() => {
        const selectors = {
          device: '#device',
          center: '#center',
          samples: '#sampleRows',
          hint: '#hint',
          transport: '#playbar',
          stemsPanel: '#stems-panel',
        };
        return Object.fromEntries(Object.entries(selectors).map(([name, selector]) => {
          const el = document.querySelector(selector);
          if (!el) return [name, null];
          const style = getComputedStyle(el);
          const rect = el.getBoundingClientRect();
          return [name, {
            left: rect.left,
            top: rect.top,
            right: rect.right,
            bottom: rect.bottom,
            width: rect.width,
            height: rect.height,
            display: style.display,
            visibility: style.visibility,
            opacity: Number(style.opacity),
            text: el.textContent.trim(),
          }];
        }));
      });

      for (const [name, box] of Object.entries(boxes)) {
        assert.ok(box, `${viewport.name}: expected ${name}`);
        assert.notEqual(box.visibility, 'hidden', `${viewport.name}: ${name} should not be visibility:hidden`);
      }

      for (const name of ['device', 'center', 'samples', 'hint']) {
        assert.ok(
          boxes[name].width > 0 && boxes[name].height > 0,
          `${viewport.name}: ${name} should occupy space`,
        );
      }

      assert.equal(boxes.transport.display, 'none', `${viewport.name}: transport stays hidden while idle`);
      assert.equal(boxes.stemsPanel.display, 'none', `${viewport.name}: stems panel stays hidden while idle`);
      assert.ok(boxes.samples.text.length > 0, `${viewport.name}: sample text should be visible`);
      assert.ok(!intersects(boxes.device, boxes.samples, 4), `${viewport.name}: device and sample rows should not overlap`);
      assert.ok(boxes.hint.text.length > 0, `${viewport.name}: hint text should be visible`);
      assert.ok(!intersects(boxes.samples, boxes.hint, 4), `${viewport.name}: sample rows and hint should not overlap`);
      assert.ok(
        boxes.device.bottom < viewport.height && boxes.samples.bottom <= viewport.height,
        `${viewport.name}: idle call-to-action should fit inside the first viewport`,
      );
    }
  } finally {
    await page.close();
  }
});

browserTest('Mix/Solo loop audition attributes: Mix starts pressed, Solo starts unpressed', async () => {
  // The Solo button lives inside #stems-panel which is display:none
  // until a track is loaded. We can read its aria-pressed attribute
  // regardless (it is always in the DOM), but we cannot click it
  // until the panel becomes active. The click test below is gated.
  const page = await newPage();
  try {
    await loadApp(page);
    const state = await page.evaluate(() => ({
      mix: document.getElementById('loopAuditionMix').getAttribute('aria-pressed'),
      solo: document.getElementById('loopAuditionSolo').getAttribute('aria-pressed'),
      panelActive: document.getElementById('stems-panel').classList.contains('active'),
    }));
    assert.equal(state.mix, 'true', 'mix starts pressed');
    assert.equal(state.solo, 'false', 'solo starts unpressed');
    assert.equal(state.panelActive, false, 'stems-panel is hidden until a track loads');
  } finally {
    await page.close();
  }
});

browserTest('clicking Solo flips the Mix/Solo loop audition state', async (t) => {
  // Solo is in #stems-panel which is hidden until a track loads.
  // The click is only meaningful after a real splitter run, so gate
  // it on the e2e flag.
  if (process.env.STEMACLE_BROWSER_E2E !== '1') {
    t.skip('Solo click requires a loaded track — gated on STEMACLE_BROWSER_E2E=1');
    return;
  }
  const page = await newPage();
  try {
    await loadApp(page);
    const sampleButton = await page.$('#sampleRows button');
    await sampleButton.click();
    await page.waitForFunction(
      () => document.getElementById('stems-panel')?.classList.contains('active'),
      { timeout: 240000, polling: 500 },
    );
    await page.click('#loopAuditionSolo');
    const after = await page.evaluate(() => ({
      mix: document.getElementById('loopAuditionMix').getAttribute('aria-pressed'),
      solo: document.getElementById('loopAuditionSolo').getAttribute('aria-pressed'),
    }));
    assert.equal(after.solo, 'true');
    assert.equal(after.mix, 'false');

    await page.click('#loopAuditionMix');
    const back = await page.evaluate(() => ({
      mix: document.getElementById('loopAuditionMix').getAttribute('aria-pressed'),
      solo: document.getElementById('loopAuditionSolo').getAttribute('aria-pressed'),
    }));
    assert.equal(back.mix, 'true');
    assert.equal(back.solo, 'false');
  } finally {
    await page.close();
  }
});

// ===========================================================================
// 2. Sample button + audio splitter end-to-end
// ===========================================================================

browserTest('sample button is rendered with the bundled track titles', async () => {
  const page = await newPage();
  try {
    await loadApp(page);
    const sampleTitles = await page.$$eval('#sampleRows button', (buttons) =>
      buttons.map((b) => b.textContent.trim()),
    );
    // There should be at least one sample row (the bundle has three
    // sample .mp3 files). The text content includes the track name.
    assert.ok(sampleTitles.length >= 1, `expected sample buttons, got ${sampleTitles.length}`);
    for (const title of sampleTitles) {
      assert.ok(title.length > 0, 'sample button should have a non-empty title');
    }
  } finally {
    await page.close();
  }
});

browserTest('clicking a sample triggers the splitter and reaches a ready state', async (t) => {
  // The real splitter is heavy: it tries to download an ONNX model
  // (~80 MB) and runs the inference in WebAssembly. The first run is
  // typically 60-180 seconds on a modern Mac. We allow 4 minutes to
  // accommodate the cold-start path; in CI we expect this to take
  // most of that. To run this test, set STEMACLE_BROWSER_E2E=1.
  if (process.env.STEMACLE_BROWSER_E2E !== '1') {
    t.skip('splitter end-to-end is gated on STEMACLE_BROWSER_E2E=1 — it downloads the ONNX model and may take several minutes');
    return;
  }

  const page = await newPage();
  try {
    await loadApp(page);
    const sampleButton = await page.$('#sampleRows button');
    assert.ok(sampleButton, 'expected at least one sample button');

    await sampleButton.click();

    // Wait up to 4 minutes for state.ready to flip. The model
    // download is ~80 MB and the inference is on the order of
    // 30-60 seconds on a modern machine; the slow path is the DSP
    // fallback if the model can't be reached.
    const ready = await page.waitForFunction(
      () => {
        const hint = document.getElementById('hint');
        return hint && /Use the mixer/i.test(hint.textContent || '');
      },
      { timeout: 240000, polling: 500 },
    ).then(() => true).catch(() => false);

    assert.equal(ready, true, 'expected the splitter to reach the ready state');

    const state = await page.evaluate(() => {
      const filename = document.getElementById('filename').textContent;
      const cur = document.getElementById('timeCur').textContent;
      const tot = document.getElementById('timeTot').textContent;
      return { filename, cur, tot };
    });
    assert.ok(state.filename.length > 0, 'filename should be set after a sample loads');
    assert.notEqual(state.tot, '0:00', 'total time should be non-zero after a sample loads');

    await page.screenshot({ path: screenshotPath('app-sample-loaded.png'), fullPage: false });
  } finally {
    await page.close();
  }
});

// ===========================================================================
// 3. Loop control parity
// ===========================================================================

browserTest('loop button toggles the aria-pressed / active class for the right stem only', async (t) => {
  if (process.env.STEMACLE_BROWSER_E2E !== '1') {
    t.skip('loop UI test requires a loaded track — gated on STEMACLE_BROWSER_E2E=1');
    return;
  }

  const page = await newPage();
  try {
    await loadApp(page);
    const sampleButton = await page.$('#sampleRows button');
    await sampleButton.click();
    await page.waitForFunction(
      () => /Use the mixer/i.test(document.getElementById('hint')?.textContent || ''),
      { timeout: 240000, polling: 500 },
    );

    // Click 1-measure loop on drums (data-loop="2").
    await page.click('.loop-row[data-stem="drums"] .loop-btn[data-loop="2"]');
    const pressed = await page.$$eval(
      '.loop-row[data-stem="drums"] .loop-btn[aria-pressed="true"]',
      (btns) => btns.map((b) => b.getAttribute('data-loop')),
    );
    assert.deepEqual(pressed, ['2'], 'drums 1-measure loop should be pressed');

    // Other stems should not be affected.
    const otherPressed = await page.$$eval(
      '.loop-row:not([data-stem="drums"]):not([data-stem="all"]) .loop-btn[aria-pressed="true"]',
      (btns) => btns.map((b) => `${b.getAttribute('data-stem')}/${b.getAttribute('data-loop')}`),
    );
    assert.deepEqual(otherPressed, [], `no other stem should be looped, got: ${otherPressed.join(', ')}`);

    // Click again to clear.
    await page.click('.loop-row[data-stem="drums"] .loop-btn[data-loop="2"]');
    const cleared = await page.$$eval(
      '.loop-row[data-stem="drums"] .loop-btn[aria-pressed="true"]',
      (btns) => btns.map((b) => b.getAttribute('data-loop')),
    );
    assert.deepEqual(cleared, [], 'drums loop should be cleared after a second click');
  } finally {
    await page.close();
  }
});

// ===========================================================================
// 4. Native app download handoff
// ===========================================================================

browserTest('Stem Shuffle native handoff points at the release shelf, not a removed native web shell', async () => {
  const page = await newPage();
  try {
    const url = `${serverHandle.url}/apps/stem-shuffle/index.html`;
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForSelector('.actions a', { timeout: 5000 });

    const links = await page.$$eval('.actions a', (anchors) =>
      anchors.map((a) => ({ text: a.textContent.trim(), href: a.getAttribute('href') }))
    );
    assert.deepEqual(links, [
      { text: 'Open Stem Splitter', href: '/app/' },
      { text: 'Get native apps', href: '/' },
    ]);

    await page.goto(`${serverHandle.url}/`, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForSelector('[data-release="mac-dmg"], [data-release="ios"]', { timeout: 5000 });
  } finally {
    await page.close();
  }
});
