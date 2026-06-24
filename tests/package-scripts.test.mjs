import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

test('default npm test glob excludes the Puppeteer browser parity suite', () => {
  assert.equal(
    existsSync(new URL('./browser-parity.test.mjs', import.meta.url)),
    false,
    'browser parity tests must not use the default *.test.mjs suffix',
  );
  assert.match(pkg.scripts.test, /tests\/\*\.test\.mjs/);
  assert.match(pkg.scripts['test:browser'], /tests\/browser-parity\.browser\.mjs/);
  assert.match(pkg.scripts['test:browser:e2e'], /tests\/browser-parity\.browser\.mjs/);
});

test('browser parity tests skip cleanly when Chromium is unavailable', () => {
  const browserParity = readFileSync(new URL('./browser-parity.browser.mjs', import.meta.url), 'utf8');
  assert.match(browserParity, /const browserTest = chromiumExecutable \? test : test\.skip/);
  assert.match(browserParity, /const chromiumExecutable = findChromium\(\);/);
  assert.match(browserParity, /if \(chromiumExecutable\) \{\s*test\.before\(async \(\) => \{/);
  assert.match(browserParity, /\/usr\/bin\/google-chrome/);
  assert.match(browserParity, /process\.env\.LOCALAPPDATA/);
});
