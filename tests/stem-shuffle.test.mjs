import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { pathToFileURL } from 'node:url';

const appRoot = new URL('../apps/stem-shuffle/', import.meta.url);

function loadHtml() {
  return readFileSync(new URL('./index.html', appRoot), 'utf8');
}

async function importModule(relativePath) {
  const absolutePath = path.resolve(new URL(relativePath, appRoot).pathname);
  return import(`${pathToFileURL(absolutePath).href}?t=${Date.now()}`);
}

test('stem shuffle app exists as a separate standalone entrypoint', () => {
  const html = loadHtml();

  assert.match(html, /<title>Stem Shuffle<\/title>/);
  assert.match(html, /<script type="module" src="\.\/app\.js"><\/script>/);
  assert.match(html, /id="libraryList"/);
  assert.match(html, /id="crossfader"/);
  assert.match(html, /id="youtubePlaylistUrl"/);
});

test('youtube playlist parsing captures canonical playlist URLs', async () => {
  const mod = await importModule('./library.js');
  const parsed = mod.parseYouTubePlaylistUrl('https://www.youtube.com/watch?v=abc123&list=PLxyz987');

  assert.equal(parsed.playlistId, 'PLxyz987');
  assert.equal(parsed.canonicalUrl, 'https://www.youtube.com/playlist?list=PLxyz987');
});

test('youtube adapters stay pending until a resolver is added', async () => {
  const mod = await importModule('./library.js');
  const adapter = mod.createPendingYouTubeAdapter('https://www.youtube.com/playlist?list=PLxyz987');

  assert.equal(adapter.kind, 'youtube');
  assert.equal(adapter.status, 'pending');
  assert.deepEqual(adapter.tracks, []);
});

test('compatibility scoring prefers tracks with closer tempo and key', async () => {
  const mod = await importModule('./library.js');
  const near = mod.scoreCompatibility(
    { tempo: 120, keyClass: 0, duration: 180, analysisStatus: 'ready' },
    { tempo: 122, keyClass: 1, duration: 176, analysisStatus: 'ready' },
  );
  const far = mod.scoreCompatibility(
    { tempo: 120, keyClass: 0, duration: 180, analysisStatus: 'ready' },
    { tempo: 89, keyClass: 8, duration: 91, analysisStatus: 'ready' },
  );

  assert.ok(near > far);
});

test('pair picking chooses a ready compatible pair', async () => {
  const mod = await importModule('./library.js');
  const pair = mod.pickCompatiblePair([
    { id: 'left', tempo: 120, keyClass: 0, duration: 180, analysisStatus: 'ready' },
    { id: 'right', tempo: 121, keyClass: 1, duration: 182, analysisStatus: 'ready' },
    { id: 'bad', tempo: 88, keyClass: 9, duration: 75, analysisStatus: 'ready' },
    { id: 'pending', tempo: 120, keyClass: 0, duration: 180, analysisStatus: 'pending' },
  ]);

  assert.equal(pair.left.id, 'left');
  assert.equal(pair.right.id, 'right');
  assert.ok(pair.score > 0);
});

test('crossfade math leans left at 0, center at 0.5, and right at 1', async () => {
  const mod = await importModule('./audio-core.js');

  assert.deepEqual(mod.computeDeckMixGains(0), { left: 1, right: 0 });
  assert.deepEqual(mod.computeDeckMixGains(0.5), { left: 0.5, right: 0.5 });
  assert.deepEqual(mod.computeDeckMixGains(1), { left: 0, right: 1 });
});
