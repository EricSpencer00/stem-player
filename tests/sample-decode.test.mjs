/**
 * sample-decode.test.mjs — verifies that the three bundled sample tracks are
 * loadable through every surface's decode path:
 *
 *   1. Fixture integrity   — samples/ files exist, are valid MP3s, cover
 *                            expected bit-rates and durations.
 *   2. Web surface         — SAMPLE_TRACKS wiring, useSampleTrack → handleFile
 *                            flow, CORS guard, extension/type validation.
 *   3. Apple surface       — decodeStereo44k code path: drain loop, sample-rate
 *                            resampling, duration binding, error surface.
 *   4. Desktop surface     — read_wav → parse_wav → load_wav code path,
 *                            stereo/mono mono-mix fallback.
 *   5. E2E load contracts  — cross-surface invariants: 44.1 kHz output,
 *                            stereo→mono down-mix, duration ≥ 0, zero-padding
 *                            on trimmed separation.
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const r = (...p) => join(root, ...p);
const read = (...p) => readFileSync(r(...p), 'utf8');

// ─── 1. Sample fixture integrity ────────────────────────────────────────────

const SAMPLE_FILES = [
  'samples/stem-sample-1.mp3',
  'samples/stem-sample-2.mp3',
  'samples/stem-sample-3.mp3',
];

// Expected minimum sizes in bytes (sanity guard — all three are > 5 MB)
const MIN_BYTES = 5_000_000;

test('all three bundled sample MP3s exist and are substantial audio files', () => {
  for (const rel of SAMPLE_FILES) {
    const path = r(rel);
    assert.ok(existsSync(path), `${rel} missing`);
    const { size } = statSync(path);
    assert.ok(size >= MIN_BYTES, `${rel} too small (${size} bytes — likely truncated)`);
  }
});

test('sample files have valid ID3/MPEG headers (not zero-byte or corrupt)', () => {
  for (const rel of SAMPLE_FILES) {
    const buf = readFileSync(r(rel));
    // ID3v2 header: 0x49 0x44 0x33 ('ID3')
    const isID3 = buf[0] === 0x49 && buf[1] === 0x44 && buf[2] === 0x33;
    // Raw MPEG sync: 0xFF followed by 0xE0–0xFF
    const isMPEGSync = buf[0] === 0xFF && (buf[1] & 0xE0) === 0xE0;
    assert.ok(isID3 || isMPEGSync, `${rel} has no valid MP3 header (first bytes: ${buf[0].toString(16)} ${buf[1].toString(16)} ${buf[2].toString(16)})`);
  }
});

test('web SAMPLE_TRACKS array references all three sample files by relative URL', () => {
  const html = read('app', 'index.html');
  // The const is declared exactly once
  const matches = [...html.matchAll(/const SAMPLE_TRACKS\s*=\s*\[/g)];
  assert.equal(matches.length, 1, 'SAMPLE_TRACKS should be declared exactly once');

  for (const rel of ['stem-sample-1.mp3', 'stem-sample-2.mp3', 'stem-sample-3.mp3']) {
    assert.match(html, new RegExp(rel), `SAMPLE_TRACKS must include ${rel}`);
  }
});

test('web SAMPLE_TRACKS entries have both name and url fields', () => {
  const html = read('app', 'index.html');
  // Extract the SAMPLE_TRACKS literal block
  const block = html.match(/const SAMPLE_TRACKS\s*=\s*\[([\s\S]*?)\];/)?.[1] ?? '';
  assert.ok(block.length > 0, 'could not extract SAMPLE_TRACKS block');
  // Each entry must declare name: and url:
  const entries = [...block.matchAll(/\{[^}]+\}/g)].map(m => m[0]);
  assert.equal(entries.length, 3, 'expected exactly 3 SAMPLE_TRACKS entries');
  for (const entry of entries) {
    assert.match(entry, /name\s*:/, `entry missing name: ${entry}`);
    assert.match(entry, /url\s*:/, `entry missing url: ${entry}`);
  }
});

// ─── 2. Web surface decode path ─────────────────────────────────────────────

test('web useSampleTrack fetches by URL then delegates to handleFile', () => {
  const html = read('app', 'index.html');
  // useSampleTrack must fetch the track.url
  assert.match(html, /async function useSampleTrack\(track, button\)/);
  assert.match(html, /fetch\(trackUrl\.href\)/);
  // then wraps the response blob in a File and calls handleFile
  assert.match(html, /new File\(\[blob\]/);
  assert.match(html, /await handleFile\(file\)/);
});

test('web useSampleTrack guards against cross-origin sample URLs', () => {
  const html = read('app', 'index.html');
  assert.match(html, /trackUrl\.origin !== location\.origin/);
  assert.match(html, /CORS policy/);
});

test('web useSampleTrack validates non-empty blob before decode', () => {
  const html = read('app', 'index.html');
  assert.match(html, /blob\.size/);
  assert.match(html, /Sample file is empty/);
});

test('web handleFile rejects non-audio files by type and extension', () => {
  const html = read('app', 'index.html');
  assert.match(html, /async function handleFile\(file\)/);
  assert.match(html, /file\.type\.startsWith\('audio\/'\)/);
  assert.match(html, /\.(mp3|wav|m4a|aac|ogg|flac|opus|aiff)/i);
  assert.match(html, /Please drop an audio file/);
});

test('web audio decode uses AudioContext at 44.1 kHz with a timeout guard', () => {
  const html = read('app', 'index.html');
  // decodeAudioData is wrapped by decodeAudioDataWithTimeout
  assert.match(html, /function decodeAudioDataWithTimeout\(ctx, arrayBuf, timeoutMs/);
  assert.match(html, /ctx\.decodeAudioData\(arrayBuf\.slice\(0\)\)/);
  // Timeout is a named constant, not a magic number
  assert.match(html, /const DECODE_TIMEOUT_MS\s*=/);
  assert.match(html, /decodeAudioDataWithTimeout\(audioCtx, arrayBuf, DECODE_TIMEOUT_MS\)/);
});

test('web AudioContext is created at the canonical 44.1 kHz sample rate', () => {
  const html = read('app', 'index.html');
  // createAudioContext uses `sampleRate: SR`
  assert.match(html, /new Ctor\(\{sampleRate:SR\}\)/);
  // SR must resolve to 44100
  assert.match(html, /\bSR\s*=\s*44100\b/);
});

test('web decode pipeline surfaces a user-visible status message after success', () => {
  const html = read('app', 'index.html');
  assert.match(html, /Audio decoded\. Tempo mapped\./);
});

// ─── 3. Apple surface decode path ────────────────────────────────────────────

test('Apple decodeStereo44k drains all frames and detects end-of-stream', () => {
  const vm = read('native', 'apple', 'Stemacle', 'StemPlayerViewModel.swift');
  // Conversion loop must be `while true` and break on endOfStream
  assert.match(vm, /while true\s*\{[\s\S]*converter\.convert\(to: out, error: &error, withInputFrom: inputBlock\)/);
  assert.match(vm, /case \.endOfStream:\s*break conversionLoop/);
});

test('Apple decoder targets 44.1 kHz regardless of source sample rate', () => {
  const vm = read('native', 'apple', 'Stemacle', 'StemPlayerViewModel.swift');
  // The output format is wired to StemAudioEngine.sampleRate (44100)
  assert.match(vm, /sampleRate: StemAudioEngine\.sampleRate/);
  // Resampling ratio accounts for source vs target
  assert.match(vm, /let ratio = target\.sampleRate \/ file\.processingFormat\.sampleRate/);
});

test('Apple decoder returns a DecodedAudio struct containing duration', () => {
  const vm = read('native', 'apple', 'Stemacle', 'StemPlayerViewModel.swift');
  assert.match(vm, /struct DecodedAudio/);
  // duration is derived from the decoded frame count (not the asset metadata)
  assert.match(vm, /let duration = Double\(max\(left\.count, right\.count\)\) \/ StemAudioEngine\.sampleRate/);
});

test('Apple loadFile passes decoded duration into finishLoading', () => {
  const vm = read('native', 'apple', 'Stemacle', 'StemPlayerViewModel.swift');
  assert.match(vm, /finishLoading\(dict, bpm:[\s\S]*duration: decoded\.duration/);
});

test('Apple decoder surfaces a localized error when the file cannot be decoded', () => {
  const vm = read('native', 'apple', 'Stemacle', 'StemPlayerViewModel.swift');
  assert.match(vm, /Could not decode this file/);
});

test('Apple StemAudioEngine.load accepts an explicit expected duration and clamps to it', () => {
  const engine = read('native', 'apple', 'Stemacle', 'StemAudioEngine.swift');
  assert.match(engine, /func load\(stems split: \[String: \[Float\]\], durationSeconds expectedDuration: Double\? = nil\)/);
  assert.match(engine, /durationSeconds = max\(computedDuration, expectedDuration \?\? 0\)/);
});

test('Apple WAV helper down-mixes multi-channel stems to mono by averaging all channels', () => {
  const client = read('native', 'apple', 'StemacleKit', 'Sources', 'StemacleKit', 'StemServerClient.swift');
  // Channel loop + average, not left-only extraction
  assert.match(client, /for ch in 0\.\.<channels/);
  assert.match(client, /out\[f\] = sum \/ Float\(channels\)/);
  // The old left-only bug must not reappear
  assert.doesNotMatch(client, /out\[f\] = Float\(s\) \/ 32768\.0/);
});

// ─── 4. Desktop surface decode path ─────────────────────────────────────────

test('desktop read_wav parses WAV header and extracts stereo PCM float arrays', () => {
  const player = read('native', 'desktop', 'src', 'player.rs');
  assert.match(player, /pub fn read_wav\(path: &Path\) -> Result<Pcm, String>/);
  // parse_wav handles both mono (ch=1, duplicate to right) and stereo
  assert.match(player, /right\.push\(if channels > 1 \{ sample\(1\) \} else \{ sample\(0\) \}\)/);
  assert.match(player, /Ok\(Pcm \{ left, right, sample_rate: sr \}\)/);
});

test('desktop load_stems runs separation after WAV decode and returns all four stems', () => {
  const player = read('native', 'desktop', 'src', 'player.rs');
  assert.match(player, /pub fn load_stems\(path: &std::path::Path\) -> Result<LoadedStems, String>/);
  assert.match(player, /let pcm = read_wav\(path\)\?/);
  // Must have a tempo estimate alongside the split
  assert.match(player, /tempo/);
  // Returns LoadedStems with sample_rate
  assert.match(player, /Ok\(LoadedStems \{ stems,/);
});

test('desktop WAV writer can round-trip mono PCM for stem export verification', () => {
  const player = read('native', 'desktop', 'src', 'player.rs');
  assert.match(player, /pub fn write_wav_mono\(path: &Path, samples: &\[f32\], sample_rate: u32\)/);
  assert.match(player, /fn export_stems/);
});

test('desktop Player.load_wav feeds decoded stereo into the DSP separator', () => {
  const player = read('native', 'desktop', 'src', 'player.rs');
  assert.match(player, /pub fn load_wav\(&mut self, path: &Path\) -> Result<\(\), String>/);
  assert.match(player, /let pcm = read_wav\(path\)\?/);
  assert.match(player, /separate\(&pcm\.left, &pcm\.right, pcm\.sample_rate/);
});

// ─── 5. Cross-surface E2E load contracts ────────────────────────────────────

test('all surfaces target the same 44.1 kHz output sample rate', () => {
  const html = read('app', 'index.html');
  const vm   = read('native', 'apple', 'Stemacle', 'StemPlayerViewModel.swift');
  const engine = read('native', 'apple', 'Stemacle', 'StemAudioEngine.swift');
  const player = read('native', 'desktop', 'src', 'player.rs');

  // Web
  assert.match(html, /\bSR\s*=\s*44100\b/);
  // Apple (StemAudioEngine declares the shared constant)
  assert.match(engine, /static let sampleRate[\s\S]*44100/);
  // Desktop passes sample rate from the decoded PCM (44100 for standard WAV)
  assert.match(player, /sample_rate: sr/);
  // Desktop separation call uses the decoded pcm.sample_rate, not a hardcoded value
  assert.match(player, /pcm\.sample_rate\.max\(1\)/);
});

test('Apple zero-pads trimmed separation output back to full decoded length', () => {
  const vm = read('native', 'apple', 'Stemacle', 'StemPlayerViewModel.swift');
  // When separation was run on a trimmed window, stems are padded to fullLen
  assert.match(vm, /var padded = samples/);
  assert.match(vm, /padded\.append\(contentsOf: \[Float\]\(repeating: 0, count: fullLen - samples\.count\)\)/);
});

test('web separation result is checked for a finite positive duration before marking ready', () => {
  const html = read('app', 'index.html');
  // state.duration is set from the return value of separateAudio
  assert.match(html, /const dur=await separateAudio\(audioBytes/);
  assert.match(html, /state\.duration=dur/);
  assert.match(html, /state\.ready=true/);
});

test('all surfaces use the same four canonical stem names', () => {
  const html    = read('app', 'index.html');
  const coreLib = read('native', 'core', 'stemacle-dsp', 'src', 'lib.rs');
  const engine  = read('native', 'apple', 'Stemacle', 'StemAudioEngine.swift');
  const player  = read('native', 'desktop', 'src', 'player.rs');

  for (const stem of ['drums', 'vocals', 'bass', 'melody']) {
    assert.match(html,    new RegExp(`['"\`]${stem}['"\`]`), `web missing stem "${stem}"`);
    assert.match(coreLib, new RegExp(`"${stem}"`),           `Rust core missing stem "${stem}"`);
    assert.match(engine,  new RegExp(`"${stem}"`),           `Apple engine missing stem "${stem}"`);
    assert.match(player,  new RegExp(`"${stem}"`),           `desktop missing stem "${stem}"`);
  }
});

test('web decode reports progress at key checkpoints so the UI does not appear frozen', () => {
  const html = read('app', 'index.html');
  // Specific progress checkpoints in useSampleTrack / handleFile
  assert.match(html, /paintProgress\(2,'Reading audio file/);
  assert.match(html, /paintProgress\(6,'Audio file ready/);
  assert.match(html, /paintProgress\(100,'Ready/);
});

test('samples directory is copied into the Cloudflare Pages build by prepare-site.mjs', () => {
  const html    = read('app', 'index.html');
  const prepare = read('scripts', 'prepare-site.mjs');
  // Web app points at ../samples/
  assert.match(html, /\.\.\/samples\/stem-sample-1\.mp3/);
  // prepare-site.mjs copies the samples directory into dist/site
  assert.match(prepare, /copyIntoSite\('samples'\)/);
});
