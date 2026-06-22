// Unit tests for native/electron/desktop-tools.cjs.
//
// This module is the workhorse of the Electron desktop shell. It owns the
// audio extension allowlist, the model quality catalog, the Demucs /
// yt-dlp / ffmpeg adapter fall-throughs, and the stable-id derivation
// for tracks and roots. It was previously only covered end-to-end via
// native-desktop.test.mjs, which tested the public desktop module surface.
// These unit tests pin the individual helpers so a future refactor of the
// module cannot silently change behavior without these tests flagging it.

import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import tools from '../native/electron/desktop-tools.cjs';

const {
  AUDIO_EXTENSIONS,
  EXPORT_KINDS,
  EXPORT_FORMATS,
  MODEL_QUALITY_CATALOG,
  TOOL_DEFINITIONS,
  createModelRows,
  detectMimeType,
  detectToolState,
  isAudioPath,
  listAudioFiles,
  normalizeMetadata,
  readJson,
  readMetadata,
  runDemucsSeparation,
  runDownload,
  convertAudio,
  scanAudioPaths,
  stableRootId,
  stableTrackId,
  writeJson,
} = tools;

// ---- isAudioPath ----

test('isAudioPath accepts every documented audio extension case-insensitively', () => {
  for (const ext of ['.mp3', '.wav', '.m4a', '.aac', '.ogg', '.flac', '.opus', '.aiff', '.aif']) {
    assert.equal(isAudioPath(`track${ext}`), true, `expected ${ext} to be accepted`);
    assert.equal(isAudioPath(`track${ext.toUpperCase()}`), true, `expected ${ext.toUpperCase()} to be accepted`);
  }
});

test('isAudioPath rejects non-audio extensions', () => {
  for (const ext of ['.txt', '.mp4', '.mov', '.png', '', '.docx']) {
    assert.equal(isAudioPath(`track${ext}`), false, `expected ${ext || '(none)'} to be rejected`);
  }
});

// ---- detectMimeType ----

test('detectMimeType maps each extension to the documented mime type', () => {
  const cases = [
    ['/tmp/a.mp3', 'audio/mpeg'],
    ['/tmp/a.wav', 'audio/wav'],
    ['/tmp/a.m4a', 'audio/mp4'],
    ['/tmp/a.aac', 'audio/aac'],
    ['/tmp/a.ogg', 'audio/ogg'],
    ['/tmp/a.flac', 'audio/flac'],
    ['/tmp/a.opus', 'audio/ogg'],
    ['/tmp/a.aiff', 'audio/aiff'],
    ['/tmp/a.aif', 'audio/aiff'],
    ['/tmp/a.unknown', 'application/octet-stream'],
  ];
  for (const [input, expected] of cases) {
    assert.equal(detectMimeType(input), expected);
  }
});

// ---- normalizeMetadata ----

test('normalizeMetadata coerces non-finite values to null', () => {
  const result = normalizeMetadata({
    duration: NaN,
    sampleRate: Infinity,
    channels: 'two',
    bpm: undefined,
    key: '',
  });
  assert.equal(result.duration, null);
  assert.equal(result.sampleRate, null);
  assert.equal(result.channels, null);
  assert.equal(result.bpm, null);
  assert.equal(result.key, null);
});

test('normalizeMetadata preserves finite numeric values and non-empty strings', () => {
  const result = normalizeMetadata({
    duration: 12.5,
    sampleRate: 44100,
    channels: 2,
    bpm: 120,
    key: 'C major',
  });
  assert.deepEqual(result, {
    duration: 12.5,
    sampleRate: 44100,
    channels: 2,
    bpm: 120,
    key: 'C major',
  });
});

// ---- stable ids ----

test('stableTrackId is deterministic for the same path + size + mtime', () => {
  const fakeStats = { size: 1234, mtimeMs: 1700000000000 };
  const id1 = stableTrackId('/tmp/song.mp3', fakeStats);
  const id2 = stableTrackId('/tmp/song.mp3', fakeStats);
  assert.equal(id1, id2);
  assert.equal(id1.length, 18, 'id should be 18 chars from sha256 prefix');
});

test('stableTrackId changes when any of path, size, or mtime changes', () => {
  const base = { size: 1234, mtimeMs: 1700000000000 };
  assert.notEqual(stableTrackId('/tmp/a.mp3', base), stableTrackId('/tmp/b.mp3', base), 'path change');
  assert.notEqual(stableTrackId('/tmp/a.mp3', base), stableTrackId('/tmp/a.mp3', { ...base, size: 9999 }), 'size change');
  assert.notEqual(stableTrackId('/tmp/a.mp3', base), stableTrackId('/tmp/a.mp3', { ...base, mtimeMs: base.mtimeMs + 1 }), 'mtime change');
});

test('stableRootId is deterministic per absolute path and 12 chars long', () => {
  const a = stableRootId('/Users/me/Music');
  const b = stableRootId('/Users/me/Music');
  const c = stableRootId('/Users/me/Other');
  assert.equal(a, b);
  assert.notEqual(a, c);
  assert.equal(a.length, 12);
});

// ---- readJson / writeJson ----

test('readJson returns the fallback when the file is missing', () => {
  const root = mkdtempSync(join(tmpdir(), 'stemacle-tools-'));
  try {
    const fallback = { ok: false };
    assert.deepEqual(readJson(join(root, 'no-such.json'), fallback), fallback);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('readJson returns the parsed content when the file is valid JSON', () => {
  const root = mkdtempSync(join(tmpdir(), 'stemacle-tools-'));
  try {
    const file = join(root, 'nested', 'state.json');
    writeJson(file, { library: ['a', 'b'], count: 2 });
    assert.deepEqual(readJson(file, null), { library: ['a', 'b'], count: 2 });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('readJson returns the fallback when the file is not valid JSON', () => {
  const root = mkdtempSync(join(tmpdir(), 'stemacle-tools-'));
  try {
    const file = join(root, 'broken.json');
    writeFileSync(file, 'not json');
    assert.equal(readJson(file, 'fallback'), 'fallback');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// ---- MODEL_QUALITY_CATALOG ----

test('MODEL_QUALITY_CATALOG declares all four expected tiers in the documented order', () => {
  assert.deepEqual(
    MODEL_QUALITY_CATALOG.map((m) => m.id),
    ['fast-preview', 'demucs-4stem', 'demucs-6stem', 'mdx-extra-q'],
  );
});

test('every catalog entry has the required fields', () => {
  for (const model of MODEL_QUALITY_CATALOG) {
    assert.equal(typeof model.id, 'string');
    assert.equal(typeof model.label, 'string');
    assert.equal(typeof model.engine, 'string');
    assert.ok(Number.isInteger(model.stems) && model.stems >= 1);
    assert.equal(typeof model.description, 'string');
  }
});

test('catalog is ordered from fastest to highest quality', () => {
  // fast-preview must come first, then the demucs tiers, and the
  // optional / experimental models come last. The desktop UI uses this
  // ordering to drive the model-quality card.
  assert.equal(MODEL_QUALITY_CATALOG[0].engine, 'browser-dsp-onnx');
  for (let i = 1; i < MODEL_QUALITY_CATALOG.length; i++) {
    assert.equal(MODEL_QUALITY_CATALOG[i].engine, 'demucs');
  }
});

// ---- createModelRows ----

test('createModelRows marks every row with a cachePath rooted at modelCacheRoot', () => {
  const rows = createModelRows('/var/cache/stemacle', { demucs: { available: true } });
  for (const row of rows) {
    assert.equal(row.cachePath, join('/var/cache/stemacle', row.id));
  }
});

test('createModelRows disables demucs rows when demucs is unavailable', () => {
  const rows = createModelRows('/var/cache/stemacle', { demucs: { available: false } });
  for (const row of rows) {
    if (row.engine === 'demucs') {
      assert.equal(row.available, false);
      assert.match(row.status, /install/i);
    } else {
      // browser-dsp-onnx rows are always available.
      assert.equal(row.available, true);
      assert.equal(row.status, 'ready');
    }
  }
});

test('createModelRows enables all rows when demucs is available', () => {
  const rows = createModelRows('/var/cache/stemacle', { demucs: { available: true } });
  for (const row of rows) {
    assert.equal(row.available, true);
    assert.equal(row.status, 'ready');
  }
});

// ---- detectToolState (with overrides, no actual exec) ----

test('detectToolState respects overrides and does not exec when fully overridden', () => {
  const state = detectToolState({
    toolState: {
      ffmpeg: { available: true, command: '/opt/ffmpeg' },
      ffprobe: { available: true, command: '/opt/ffprobe' },
      demucs: { available: false, command: null },
      ytDlp: { available: true, command: '/opt/yt-dlp' },
    },
  });
  assert.deepEqual(state, {
    ffmpeg: { label: 'ffmpeg', command: '/opt/ffmpeg', available: true },
    ffprobe: { label: 'ffprobe', command: '/opt/ffprobe', available: true },
    demucs: { label: 'Demucs', command: null, available: false },
    ytDlp: { label: 'yt-dlp', command: '/opt/yt-dlp', available: true },
  });
});

test('TOOL_DEFINITIONS declares the four documented tools', () => {
  assert.deepEqual(Object.keys(TOOL_DEFINITIONS).sort(), ['demucs', 'ffmpeg', 'ffprobe', 'ytDlp']);
});

// ---- scanAudioPaths / listAudioFiles ----

test('scanAudioPaths descends into subdirectories and skips non-audio files', () => {
  const root = mkdtempSync(join(tmpdir(), 'stemacle-scan-'));
  try {
    mkdirSync(join(root, 'sub', 'deep'), { recursive: true });
    writeFileSync(join(root, 'a.mp3'), 'a');
    writeFileSync(join(root, 'b.txt'), 'b');
    writeFileSync(join(root, 'sub', 'c.wav'), 'c');
    writeFileSync(join(root, 'sub', 'deep', 'd.flac'), 'd');
    writeFileSync(join(root, 'sub', 'e.jpg'), 'e');

    const files = scanAudioPaths([root]);
    assert.equal(files.length, 3);
    for (const file of files) {
      assert.ok(['.mp3', '.wav', '.flac'].includes(file.slice(file.lastIndexOf('.'))));
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('scanAudioPaths returns an empty array for a non-existent root', () => {
  const files = scanAudioPaths(['/tmp/this-path-should-not-exist-12345']);
  assert.deepEqual(files, []);
});

test('listAudioFiles returns audio files relative to the root, recursing into directories', () => {
  const root = mkdtempSync(join(tmpdir(), 'stemacle-list-'));
  try {
    mkdirSync(join(root, 'inner'), { recursive: true });
    writeFileSync(join(root, 'top.mp3'), 't');
    writeFileSync(join(root, 'inner', 'nested.aiff'), 'n');
    writeFileSync(join(root, 'inner', 'ignored.txt'), 'x');
    const files = listAudioFiles(root);
    assert.equal(files.length, 2);
    assert.ok(files.every((f) => f.endsWith('.mp3') || f.endsWith('.aiff')));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// ---- Adapter fall-through (readMetadata, runDemucs, runDownload, convertAudio) ----

test('readMetadata delegates to adapters.readMetadata when provided', async () => {
  const result = await readMetadata('/tmp/a.mp3', {
    adapters: {
      readMetadata: async () => ({ duration: 9.5, sampleRate: 48000, channels: 2, bpm: 128, key: 'A min' }),
    },
  });
  assert.deepEqual(result, {
    duration: 9.5,
    sampleRate: 48000,
    channels: 2,
    bpm: 128,
    key: 'A min',
  });
});

test('readMetadata returns an empty payload when ffprobe is unavailable', async () => {
  const result = await readMetadata('/tmp/a.mp3', {
    toolState: { ffprobe: { available: false, command: null } },
  });
  assert.deepEqual(result, { duration: null, sampleRate: null, channels: null, bpm: null, key: null });
});

test('runDemucsSeparation throws a clear error when demucs is unavailable', async () => {
  await assert.rejects(
    () => runDemucsSeparation({ inputPath: '/tmp/a.mp3', outputDir: '/tmp/out', model: 'htdemucs' }, {
      toolState: { demucs: { available: false, command: null } },
    }),
    /Demucs is not installed/,
  );
});

test('runDemucsSeparation delegates to adapters.runDemucs when provided', async () => {
  let called = false;
  const result = await runDemucsSeparation(
    { inputPath: '/tmp/a.mp3', outputDir: '/tmp/out', model: 'htdemucs_ft' },
    { adapters: { runDemucs: async (options) => { called = true; return { stemFiles: { vocals: '/tmp/out/vocals.wav' }, options }; } },
    },
  );
  assert.equal(called, true);
  assert.equal(result.stemFiles.vocals, '/tmp/out/vocals.wav');
});

test('runDownload throws a clear error when yt-dlp is unavailable', async () => {
  await assert.rejects(
    () => runDownload({ url: 'https://example.test/v', outputDir: '/tmp/out' }, {
      toolState: { ytDlp: { available: false, command: null } },
    }),
    /yt-dlp is not installed/,
  );
});

test('runDownload delegates to adapters.runDownload when provided', async () => {
  const result = await runDownload(
    { url: 'https://example.test/v', outputDir: '/tmp/out' },
    { adapters: { runDownload: async () => ({ filePath: '/tmp/out/song.mp3', title: 'song' }) } },
  );
  assert.equal(result.filePath, '/tmp/out/song.mp3');
  assert.equal(result.title, 'song');
});

test('convertAudio short-circuits when the input and output extensions match', async () => {
  const root = mkdtempSync(join(tmpdir(), 'stemacle-conv-'));
  try {
    const input = join(root, 'a.wav');
    const output = join(root, 'b.wav');
    writeFileSync(input, 'fake audio bytes');
    const result = await convertAudio({ inputPath: input, outputPath: output });
    assert.equal(result.outputPath, output);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('convertAudio throws a clear error when ffmpeg is unavailable and conversion is needed', async () => {
  await assert.rejects(
    () => convertAudio({ inputPath: '/tmp/a.wav', outputPath: '/tmp/b.mp3' }, {
      toolState: { ffmpeg: { available: false, command: null } },
    }),
    /ffmpeg is not installed/,
  );
});

test('convertAudio delegates to adapters.convertAudio when provided', async () => {
  let called = false;
  const result = await convertAudio(
    { inputPath: '/tmp/a.wav', outputPath: '/tmp/b.mp3' },
    { adapters: { convertAudio: async (options) => { called = true; return { outputPath: options.outputPath, options }; } },
    },
  );
  assert.equal(called, true);
  assert.equal(result.outputPath, '/tmp/b.mp3');
});

// ---- EXPORT enums ----

test('EXPORT_KINDS declares the five documented kinds', () => {
  assert.deepEqual([...EXPORT_KINDS].sort(), [
    'current-loop',
    'deck-transition',
    'full-mixdown',
    'individual-stems',
    'stem-pack',
  ]);
});

test('EXPORT_FORMATS declares wav, flac, mp3', () => {
  assert.deepEqual([...EXPORT_FORMATS].sort(), ['flac', 'mp3', 'wav']);
});

test('AUDIO_EXTENSIONS is a Set with the nine documented extensions', () => {
  assert.ok(AUDIO_EXTENSIONS instanceof Set);
  assert.equal(AUDIO_EXTENSIONS.size, 9);
});
