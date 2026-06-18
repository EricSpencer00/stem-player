const fs = require('fs');
const path = require('path');

function findPlaywrightModule() {
  try {
    return require.resolve('playwright');
  } catch (_) {}

  const npxRoot = '/Users/eric/.npm/_npx';
  for (const dir of fs.readdirSync(npxRoot)) {
    const candidate = path.join(npxRoot, dir, 'node_modules', 'playwright', 'index.js');
    if (fs.existsSync(candidate)) {
      return path.join(npxRoot, dir, 'node_modules', 'playwright');
    }
  }
  throw new Error('Playwright module not found in npx cache. Run `npx -y playwright@1.50.0 --version` first.');
}

(async () => {
  const modulePath = findPlaywrightModule();
  const { chromium } = require(modulePath);

  const root = path.resolve(__dirname, '..');
  const samplePath = path.join(root, 'samples', 'stem-sample-1.mp3');
  const htmlPath = path.join(root, 'index.html');

  const browser = await chromium.launch({
    headless: true,
  });
  const page = await browser.newPage();

  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      throw new Error(`console.error: ${msg.text()}`);
    }
  });

  await page.goto(`file://${htmlPath}`);
  await page.selectOption('#modelMode', 'fast');

  await page.setInputFiles('#fileInput', samplePath);
  await page.waitForSelector('#playbar.active', { timeout: 300000 });
  await page.waitForSelector('#stems-panel.active', { timeout: 300000 });

  const playbarActive = await page.$eval('#playbar', (el) => el.classList.contains('active'));
  const stemsActive = await page.$eval('#stems-panel', (el) => el.classList.contains('active'));
  const waveActive = await page.$eval('#waveRow', (el) => el.classList.contains('active'));
  if (!playbarActive || !stemsActive || !waveActive) {
    throw new Error('Post-upload UI did not fully activate.');
  }

  const drumsLoop0 = page.locator('.loop-row[data-stem="drums"] .loop-btn[data-loop="0"]');
  await drumsLoop0.click();
  const loopOn = await drumsLoop0.evaluate((node) => node.classList.contains('on'));
  if (!loopOn) {
    throw new Error('Loop button did not toggle into active state.');
  }

  const drumsMute = page.locator('.stem-mute-btn[data-stem="drums"]');
  await drumsMute.click();
  const muteText = await drumsMute.textContent();
  if ((muteText || '').trim() !== 'muted') {
    throw new Error(`Expected muted label, got ${muteText}.`);
  }

  let invalidAlert = false;
  page.once('dialog', async (dialog) => {
    const msg = dialog.message();
    if (/audio file/i.test(msg)) invalidAlert = true;
    await dialog.accept();
  });

  await page.setInputFiles('#fileInput', {
    name: 'not-audio.txt',
    mimeType: 'text/plain',
    buffer: Buffer.from('not audio', 'utf8')
  });

  await page.waitForTimeout(750);
  if (!invalidAlert) {
    throw new Error('Invalid file upload did not raise expected alert.');
  }

  await page.click('#btnPlay');
  await page.waitForTimeout(300);
  const btnPlay = await page.$eval('#btnPlay', (n) => n.textContent);
  if (!btnPlay || !btnPlay.includes('pause')) {
    throw new Error('Play button did not enter pause state after click.');
  }

  await page.click('#btnStop');
  const btnPlayAfterStop = await page.$eval('#btnPlay', (n) => n.textContent);
  if (!btnPlayAfterStop || !btnPlayAfterStop.includes('play')) {
    throw new Error('Play button did not return to play state after stop.');
  }

  console.log('PASS upload-smoke');
  await browser.close();
})();
