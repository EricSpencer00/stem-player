import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { pathToFileURL } from 'node:url';

const repoRoot = new URL('../', import.meta.url);

function readRepo(path) {
  return readFileSync(new URL(path, repoRoot), 'utf8');
}

async function importDesktopModule() {
  const moduleUrl = pathToFileURL(new URL('../native/electron/stemacle-desktop.cjs', import.meta.url).pathname);
  return import(`${moduleUrl.href}?t=${Date.now()}`);
}

test('desktop service persists library records and derives stable cache paths', async () => {
  const desktop = await importDesktopModule();
  const tempRoot = mkdtempSync(join(tmpdir(), 'stemacle-desktop-'));
  const audioPath = join(tempRoot, 'track one.wav');
  writeFileSync(audioPath, 'not real audio, good enough for cache identity');

  try {
    const store = desktop.createDesktopStore(tempRoot);
    const [track] = store.addLibraryPaths([audioPath]);
    const reloaded = desktop.createDesktopStore(tempRoot);

    assert.equal(track.name, 'track one.wav');
    assert.equal(track.sourceKind, 'desktop');
    assert.match(track.cache.stemDir, /stem-cache/);
    assert.match(track.cache.analysisFile, /analysis-cache/);
    assert.equal(reloaded.getState().library.length, 1);
    assert.equal(reloaded.getState().library[0].id, track.id);
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('desktop service exposes model quality catalog, queue, sessions, and export plans', async () => {
  const desktop = await importDesktopModule();
  const tempRoot = mkdtempSync(join(tmpdir(), 'stemacle-desktop-'));
  const audioPath = join(tempRoot, 'source.mp3');
  writeFileSync(audioPath, 'audio bytes');

  try {
    const store = desktop.createDesktopStore(tempRoot);
    const [track] = store.addLibraryPaths([audioPath]);
    const job = store.enqueueAnalysis(track.id, { quality: 'demucs-4stem' });
    const session = store.saveSession({
      name: 'late night loop',
      trackIds: [track.id],
      mixer: { drums: 0.8, vocals: 1 },
    });
    const stemPack = store.planExport(track.id, { kind: 'stem-pack', format: 'wav' });
    const loop = store.planExport(track.id, { kind: 'current-loop', format: 'flac' });

    assert.ok(desktop.MODEL_QUALITY_CATALOG.some((model) => model.id === 'fast-preview'));
    assert.ok(desktop.MODEL_QUALITY_CATALOG.some((model) => model.id === 'demucs-4stem' && model.stems === 4));
    assert.ok(desktop.MODEL_QUALITY_CATALOG.some((model) => model.id === 'demucs-6stem' && model.optional));
    assert.equal(job.status, 'queued');
    assert.equal(job.quality, 'demucs-4stem');
    assert.equal(session.trackIds[0], track.id);
    assert.equal(stemPack.kind, 'stem-pack');
    assert.equal(stemPack.format, 'wav');
    assert.equal(loop.kind, 'current-loop');
    assert.match(store.getState().modelCache.cacheRoot, /model-cache/);
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('desktop shell surfaces cache, queue, session, export, shortcuts, and model controls', () => {
  const html = readRepo('native/index.html');

  assert.match(html, /id="commandPalette"/);
  assert.match(html, /id="analysisQueue"/);
  assert.match(html, /id="modelCacheList"/);
  assert.match(html, /id="exportPanel"/);
  assert.match(html, /id="sessionList"/);
  assert.match(html, /data-quality="fast-preview"/);
  assert.match(html, /data-quality="demucs-4stem"/);
  assert.match(html, /data-quality="demucs-6stem"/);
  assert.match(html, /window\.stemacleNative\.enqueueAnalysis/);
  assert.match(html, /window\.stemacleNative\.exportTrack/);
  assert.match(html, /meta\+k/i);
});

test('electron bridge exposes native desktop operations and menu handlers', () => {
  const preload = readRepo('native/electron/preload.cjs');
  const main = readRepo('native/electron/main.cjs');

  for (const api of [
    'getDesktopState',
    'pickAudioFiles',
    'pickAudioFolder',
    'addLibraryPaths',
    'enqueueAnalysis',
    'saveSession',
    'exportTrack',
    'revealPath',
    'clearDesktopState',
  ]) {
    assert.match(preload, new RegExp(`${api}:`));
  }

  for (const channel of [
    'stemacle:get-desktop-state',
    'stemacle:pick-audio-folder',
    'stemacle:add-library-paths',
    'stemacle:enqueue-analysis',
    'stemacle:save-session',
    'stemacle:export-track',
    'stemacle:reveal-path',
  ]) {
    assert.match(main, new RegExp(channel));
  }

  assert.match(main, /Menu\.buildFromTemplate/);
  assert.match(main, /CommandOrControl\+K/);
});

test('product surface document explains web, desktop, and ios differences', () => {
  const doc = readRepo('docs/STEMACLE_SURFACES.md');

  assert.match(doc, /^# Stemacle Product Surfaces/m);
  assert.match(doc, /## Web App/);
  assert.match(doc, /## Desktop App/);
  assert.match(doc, /## iOS App/);
  assert.match(doc, /offline model cache/i);
  assert.match(doc, /Demucs/i);
  assert.match(doc, /same tactile splitter/i);
  assert.doesNotMatch(doc, /TBD|TODO/);
});
