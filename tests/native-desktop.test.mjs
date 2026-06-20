import assert from 'node:assert/strict';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
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

test('desktop service indexes roots, metadata, tool state, and stable cache paths', async () => {
  const desktop = await importDesktopModule();
  const tempRoot = mkdtempSync(join(tmpdir(), 'stemacle-desktop-'));
  const crateRoot = join(tempRoot, 'crate');
  mkdirSync(crateRoot, { recursive: true });
  const audioPath = join(crateRoot, 'track one.wav');
  writeFileSync(audioPath, 'not real audio, good enough for cache identity');

  try {
    const store = desktop.createDesktopStore(tempRoot, {
      toolState: {
        ffmpeg: { available: true, command: '/fake/ffmpeg' },
        ffprobe: { available: true, command: '/fake/ffprobe' },
        demucs: { available: true, command: '/fake/demucs' },
        ytDlp: { available: true, command: '/fake/yt-dlp' },
      },
      adapters: {
        readMetadata: async () => ({
          duration: 91.2,
          sampleRate: 44100,
          channels: 2,
          bpm: 126,
          key: 'Am',
        }),
      },
    });
    const [track] = await store.addLibraryPaths([crateRoot]);
    const reloaded = desktop.createDesktopStore(tempRoot);
    const state = store.getState();

    assert.equal(track.name, 'track one.wav');
    assert.equal(track.sourceKind, 'desktop');
    assert.equal(track.duration, 91.2);
    assert.equal(track.bpm, 126);
    assert.equal(track.key, 'Am');
    assert.match(track.cache.stemDir, /stem-cache/);
    assert.match(track.cache.analysisFile, /analysis-cache/);
    assert.match(track.cache.manifestFile, /analysis-cache/);
    assert.match(state.paths.downloadRoot, /downloads/);
    assert.equal(state.libraryRoots.length, 1);
    assert.equal(state.libraryRoots[0].path, crateRoot);
    assert.equal(state.tools.demucs.available, true);
    assert.equal(state.tools.ytDlp.available, true);
    assert.ok(state.modelCache.models.some((model) => model.id === 'mdx-extra-q'));
    assert.equal(reloaded.getState().library.length, 1);
    assert.equal(reloaded.getState().library[0].id, track.id);
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('desktop service runs analysis, download, export, and file-read jobs through adapters', async () => {
  const desktop = await importDesktopModule();
  const tempRoot = mkdtempSync(join(tmpdir(), 'stemacle-desktop-'));
  const audioPath = join(tempRoot, 'source.mp3');
  writeFileSync(audioPath, 'audio bytes');

  try {
    const store = desktop.createDesktopStore(tempRoot, {
      toolState: {
        ffmpeg: { available: true, command: '/fake/ffmpeg' },
        ffprobe: { available: true, command: '/fake/ffprobe' },
        demucs: { available: true, command: '/fake/demucs' },
        ytDlp: { available: true, command: '/fake/yt-dlp' },
      },
      adapters: {
        readMetadata: async (filePath) => ({
          duration: filePath.endsWith('source.mp3') ? 88.4 : 76.1,
          sampleRate: 44100,
          channels: 2,
          bpm: 122,
          key: 'C',
        }),
        runDemucs: async ({ outputDir }) => {
          mkdirSync(outputDir, { recursive: true });
          for (const stem of ['vocals', 'drums', 'bass', 'other']) {
            writeFileSync(join(outputDir, `${stem}.wav`), `${stem} audio`);
          }
          return {
            stemFiles: {
              vocals: join(outputDir, 'vocals.wav'),
              drums: join(outputDir, 'drums.wav'),
              bass: join(outputDir, 'bass.wav'),
              other: join(outputDir, 'other.wav'),
            },
          };
        },
        runDownload: async ({ outputDir }) => {
          mkdirSync(outputDir, { recursive: true });
          const filePath = join(outputDir, 'downloaded-track.mp3');
          writeFileSync(filePath, 'downloaded audio');
          return { filePath, title: 'Downloaded track' };
        },
        convertAudio: async ({ inputPath, outputPath }) => {
          mkdirSync(join(outputPath, '..'), { recursive: true });
          copyFileSync(inputPath, outputPath);
          return { outputPath };
        },
      },
    });
    const [track] = await store.addLibraryPaths([audioPath]);
    const analysisJob = store.enqueueAnalysis(track.id, { quality: 'demucs-4stem' });
    const downloadJob = store.enqueueDownload('https://example.com/watch?v=abc123');
    await store.waitForIdle();
    const session = store.saveSession({
      name: 'late night loop',
      trackIds: [track.id],
      mixer: { drums: 0.8, vocals: 1 },
    });
    const exportJob = store.enqueueExport(track.id, { kind: 'stem-pack', format: 'wav', quality: 'demucs-4stem' });
    await store.waitForIdle();
    const filePayload = store.readTrackFile(track.id);
    const state = store.getState();
    const updatedTrack = state.library.find((entry) => entry.id === track.id);
    const completedAnalysis = state.queue.find((job) => job.id === analysisJob.id);
    const completedDownload = state.queue.find((job) => job.id === downloadJob.id);
    const completedExport = state.queue.find((job) => job.id === exportJob.id);

    assert.ok(desktop.MODEL_QUALITY_CATALOG.some((model) => model.id === 'fast-preview'));
    assert.ok(desktop.MODEL_QUALITY_CATALOG.some((model) => model.id === 'demucs-4stem' && model.stems === 4));
    assert.ok(desktop.MODEL_QUALITY_CATALOG.some((model) => model.id === 'mdx-extra-q'));
    assert.equal(completedAnalysis.status, 'completed');
    assert.equal(completedDownload.status, 'completed');
    assert.equal(completedExport.status, 'completed');
    assert.equal(analysisJob.quality, 'demucs-4stem');
    assert.equal(session.trackIds[0], track.id);
    assert.equal(updatedTrack.stemAvailability.demucs4, true);
    assert.ok(existsSync(join(updatedTrack.cache.stemDir, 'demucs-4stem', 'vocals.wav')));
    assert.match(state.modelCache.cacheRoot, /model-cache/);
    assert.ok(state.library.some((entry) => entry.sourceKind === 'download'));
    assert.equal(state.exports[0].status, 'completed');
    assert.equal(state.exports[0].kind, 'stem-pack');
    assert.equal(state.exports[0].format, 'wav');
    assert.ok(existsSync(join(updatedTrack.cache.exportDir, 'stem-pack', 'vocals.wav')));
    assert.equal(filePayload.name, 'source.mp3');
    assert.equal(filePayload.mimeType, 'audio/mpeg');
    assert.equal(Buffer.from(filePayload.bytes).toString('utf8'), 'audio bytes');
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('desktop service fails demucs and download jobs cleanly when native tools are unavailable', async () => {
  const desktop = await importDesktopModule();
  const tempRoot = mkdtempSync(join(tmpdir(), 'stemacle-desktop-'));
  const audioPath = join(tempRoot, 'source.wav');
  writeFileSync(audioPath, 'audio bytes');

  try {
    const store = desktop.createDesktopStore(tempRoot, {
      toolState: {
        ffmpeg: { available: false, command: null },
        ffprobe: { available: false, command: null },
        demucs: { available: false, command: null },
        ytDlp: { available: false, command: null },
      },
    });
    const [track] = await store.addLibraryPaths([audioPath]);
    const analysisJob = store.enqueueAnalysis(track.id, { quality: 'demucs-4stem' });
    const downloadJob = store.enqueueDownload('https://example.com/watch?v=abc123');
    await store.waitForIdle();

    const state = store.getState();
    const failedAnalysis = state.queue.find((job) => job.id === analysisJob.id);
    const failedDownload = state.queue.find((job) => job.id === downloadJob.id);

    assert.equal(failedAnalysis.status, 'failed');
    assert.match(failedAnalysis.error, /demucs/i);
    assert.equal(failedDownload.status, 'failed');
    assert.match(failedDownload.error, /yt-dlp/i);
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('desktop shell surfaces downloads, roots, caches, queue, session, export, shortcuts, and model controls', () => {
  const html = readRepo('native/index.html');

  assert.match(html, /id="commandPalette"/);
  assert.match(html, /id="analysisQueue"/);
  assert.match(html, /id="modelCacheList"/);
  assert.match(html, /id="exportPanel"/);
  assert.match(html, /id="sessionList"/);
  assert.match(html, /id="downloadUrlInput"/);
  assert.match(html, /id="libraryRoots"/);
  assert.match(html, /id="toolStatusList"/);
  assert.match(html, /id="cacheRootList"/);
  assert.match(html, /id="recentProjectsList"/);
  assert.match(html, /data-quality="fast-preview"/);
  assert.match(html, /data-quality="demucs-4stem"/);
  assert.match(html, /data-quality="demucs-6stem"/);
  assert.match(html, /data-quality="mdx-extra-q"/);
  assert.match(html, /window\.stemacleNative\.enqueueAnalysis/);
  assert.match(html, /window\.stemacleNative\.enqueueDownload/);
  assert.match(html, /window\.stemacleNative\.exportTrack/);
  assert.match(html, /window\.stemacleNative\.rescanLibrary/);
  assert.match(html, /window\.stemacleNative\.onStateChanged/);
  assert.match(html, /meta\+k/i);
});

test('native shell keeps desktop controls while optionally layering iOS affordances', () => {
  const html = readRepo('native/index.html');

  assert.match(html, /<span>iOS<\/span>/);
  assert.match(html, /data-native-action="pick-library"/);
  assert.match(html, /data-native-action="pick-folder"/);
  assert.match(html, /data-native-action="enqueue-download"/);

  if (/data-surface-only="ios"/.test(html)) {
    assert.match(html, /window\.Capacitor\?\.getPlatform\?\.\(\)/);
    assert.match(html, /<span[^>]*data-surface-only="desktop"[^>]*>desktop<\/span>/);
    assert.match(html, /data-surface-only="desktop"/);
    assert.match(html, /body\[data-surface="ios"\]/);
    assert.match(html, /id="iosApp"/);
    assert.match(html, /id="iosTactileHome"/);
    assert.match(html, /id="iosQuietNav"/);
    assert.match(html, /body\[data-surface="ios"] \.workbench \{\s*display: none;/);
    assert.match(html, /body\[data-surface="ios"] \.ios-app \{\s*padding-top: 0;/);
    assert.match(html, /drop audio/i);
    assert.match(html, /Stem Splitter/i);
    assert.match(html, /Stem Shuffle/i);
    assert.match(html, /data-native-action="pick-folder"[^>]*data-surface-only="desktop"/);
    assert.match(html, /data-native-action="enqueue-download"[^>]*data-surface-only="desktop"/);
    assert.doesNotMatch(html, /Split tracks on your phone/i);
    assert.doesNotMatch(html, /Keep stems on-device, move fast between splitting and shuffle/i);
  }
});

test('ios native shell keeps the original Stemacle circle and hides app chrome', () => {
  const html = readRepo('native/index.html');

  assert.match(html, /id="iosApp"/);
  assert.match(html, /id="iosTactileHome"/);
  assert.match(html, /id="iosQuietNav"/);
  assert.match(html, /class="device ios-device"/);
  assert.match(html, /data-ios-action="import-track"[^>]*>\s*<span>drop audio<\/span>/);
  assert.match(html, /data-ios-view="home"/);
  assert.match(html, /data-ios-view="projects"/);
  assert.match(html, /data-ios-view="library"/);
  assert.match(html, /data-ios-view="settings"/);
  assert.match(html, /data-ios-action="import-track"/);
  assert.match(html, /data-ios-action="try-sample"/);
  assert.match(html, /data-ios-action="new-project"/);
  assert.match(html, /id="iosProjectSheet"/);
  assert.match(html, /id="iosProjectDetail"/);
  assert.match(html, /id="iosRecentProjectStrip"/);
  assert.match(html, /id="iosProjectsList"/);
  assert.match(html, /id="iosProjectNotes"/);
  assert.match(html, /id="iosProjectName"/);
  assert.match(html, /Create and Open Splitter/);
  assert.match(html, /Create and Open Shuffle/);
  assert.doesNotMatch(html, /id="iosTabbar"/);
  assert.doesNotMatch(html, /id="iosOnboarding"/);
  assert.doesNotMatch(html, /Projects first, tools second/i);
  assert.doesNotMatch(html, /first run/i);
  assert.doesNotMatch(html, /New Project<\/button>\s*<\/div>\s*<div class="ios-metrics"/);
  assert.match(html, /data-tool="splitter"/);
  assert.match(html, /data-tool="shuffle"/);
  assert.match(html, /data-ios-filter="recent"/);
  assert.match(html, /data-ios-filter="needs-analysis"/);
  assert.match(html, /data-ios-filter="ready"/);
  assert.match(html, /data-ios-filter="archived"/);
  assert.match(html, /data-ios-action="share-project"/);
  assert.match(html, /data-ios-action="export-project"/);
  assert.match(html, /data-ios-action="duplicate-project"/);
  assert.match(html, /data-ios-action="archive-project"/);
  assert.match(html, /data-ios-action="delete-project"/);
  assert.match(html, /stemacle\.ios\.projects\.v1/);
  assert.doesNotMatch(html, /stemacle\.ios\.onboarding\.v1/);
  assert.match(html, /stemacle:activeProject/);
  assert.match(html, /function createProjectFromSource/);
  assert.match(html, /function openProjectTool/);
  assert.match(html, /function renderIOSApp/);
  assert.match(html, /function shareProject/);
  assert.match(html, /navigator\.share/);
});

test('ios project supports document intake and local file sharing declarations', () => {
  const info = readRepo('native/ios/App/App/Info.plist');

  assert.match(info, /LSSupportsOpeningDocumentsInPlace/);
  assert.match(info, /UIFileSharingEnabled/);
  assert.match(info, /CFBundleDocumentTypes/);
  assert.match(info, /public\.audio/);
  assert.match(info, /com\.apple\.m4a-audio/);
  assert.match(info, /public\.mp3/);
});

test('electron bridge exposes native desktop operations and menu handlers', () => {
  const preload = readRepo('native/electron/preload.cjs');
  const main = readRepo('native/electron/main.cjs');

  for (const api of [
    'getDesktopState',
    'pickAudioFiles',
    'pickAudioFolder',
    'addLibraryPaths',
    'rescanLibrary',
    'enqueueAnalysis',
    'enqueueDownload',
    'saveSession',
    'exportTrack',
    'readTrackFile',
    'revealPath',
    'clearDesktopState',
    'onStateChanged',
  ]) {
    assert.match(preload, new RegExp(`${api}:`));
  }

  for (const channel of [
    'stemacle:get-desktop-state',
    'stemacle:pick-audio-folder',
    'stemacle:add-library-paths',
    'stemacle:rescan-library',
    'stemacle:enqueue-analysis',
    'stemacle:enqueue-download',
    'stemacle:save-session',
    'stemacle:export-track',
    'stemacle:read-track-file',
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
  assert.match(doc, /cache/i);
  assert.match(doc, /Demucs/i);
  assert.match(doc, /same tactile splitter/i);
  assert.doesNotMatch(doc, /TBD|TODO/);
});
