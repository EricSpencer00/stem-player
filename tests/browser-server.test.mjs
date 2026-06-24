import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const SERVER_JS = readFileSync(new URL('./browser-server.mjs', import.meta.url), 'utf8');

test('browser static server handles file stream errors after piping starts', () => {
  assert.match(SERVER_JS, /const stream = createReadStream\(file\.path\);/);
  assert.match(SERVER_JS, /stream\.on\('error', \(error\) => \{/);
  assert.match(SERVER_JS, /res\.destroy\(error\);/);
  assert.match(SERVER_JS, /stream\.pipe\(res\);/);
});
