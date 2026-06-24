import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

const appRoot = new URL('../apps/stem-shuffle/', import.meta.url);

function loadHtml() {
  return readFileSync(new URL('./index.html', appRoot), 'utf8');
}

test('stem shuffle is now a neutral compatibility handoff page', () => {
  const html = loadHtml();

  assert.match(html, /Stem Shuffle has moved\./);
  assert.match(html, /Open desktop shell/);
  assert.match(html, /Open Stem Splitter/);
  assert.doesNotMatch(html, /id="libraryList"/);
  assert.doesNotMatch(html, /id="crossfader"/);
  assert.doesNotMatch(html, /id="youtubePlaylistUrl"/);
  assert.doesNotMatch(html, /<script type="module" src="\.\/app\.js"><\/script>/);
});

test('legacy shuffle implementation files are gone', () => {
  for (const file of ['app.js', 'audio-core.js', 'library.js', 'styles.css']) {
    assert.equal(existsSync(new URL(`./${file}`, appRoot)), false, `${file} should be removed`);
  }
});
