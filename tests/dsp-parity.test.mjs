import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// Web ↔ Rust core DSP parity guards. The web app (app/index.html) is the gold
// master; native/core/stemacle-dsp is a faithful port. STFT/Hann/tempo/loops are
// covered by golden vectors (native/core/.../tests/golden_parity.rs). These guards
// pin the two pieces NOT in the golden set — the bass/melody soft crossover and
// the BPM NaN guard — so they cannot drift on one surface without the other.

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (...p) => readFileSync(join(root, ...p), 'utf8');

const web = read('app', 'index.html');
const coreLib = read('native', 'core', 'stemacle-dsp', 'src', 'lib.rs');
const coreHpss = read('native', 'core', 'stemacle-dsp', 'src', 'hpss.rs');
const coreLoops = read('native', 'core', 'stemacle-dsp', 'src', 'loops.rs');
const coreTempo = read('native', 'core', 'stemacle-dsp', 'src', 'tempo.rs');

test('bass/melody soft crossover uses the same 220/380 Hz band on web and core', () => {
  // Web calls softLowPass(..., 220, 380) on the harmonic spectrum.
  assert.match(web, /softLowPass\([^)]*,\s*220\s*,\s*380\s*\)/);
  // Core calls soft_low_pass(..., 220.0, 380.0).
  assert.match(coreLib, /soft_low_pass\([^)]*,\s*220\.0\s*,\s*380\.0\s*\)/);
});

test('soft crossover weight is the same cosine crossfade on web and core', () => {
  // Web: lowWeight = 0.5 + 0.5 * Math.cos(Math.PI * t)
  assert.match(web, /0\.5\s*\+\s*0\.5\s*\*\s*Math\.cos\(Math\.PI\s*\*\s*t\)/);
  // Core: 0.5 + 0.5 * (std::f32::consts::PI * t).cos()
  assert.match(coreHpss, /0\.5\s*\+\s*0\.5\s*\*\s*\(std::f32::consts::PI\s*\*\s*t\)\.cos\(\)/);
});

test('measure length falls back to a finite grid on non-finite BPM, identically', () => {
  // Web: Number.isFinite(state.bpm) ? clamp(...) : BPM_FALLBACK
  assert.match(web, /Number\.isFinite\(state\.bpm\)\s*\?\s*clamp\(state\.bpm,\s*BPM_MIN,\s*BPM_MAX\)\s*:\s*BPM_FALLBACK/);
  // Core: self.bpm.is_finite() { clamp(...) } else { BPM_FALLBACK }
  assert.match(coreLoops, /self\.bpm\.is_finite\(\)[\s\S]{0,80}clamp\(self\.bpm,\s*BPM_MIN,\s*BPM_MAX\)[\s\S]{0,40}BPM_FALLBACK/);
});

test('the BPM fallback constant is 120 on both surfaces', () => {
  assert.match(web, /const BPM_FALLBACK\s*=\s*120\b/);
  assert.match(coreTempo, /pub const BPM_FALLBACK:\s*f32\s*=\s*120\.0/);
});

test('measure length is (60/bpm) * beats-per-measure on both surfaces', () => {
  // Web: (60 / bpm) * BEATS_PER_MEASURE
  assert.match(web, /\(60\s*\/\s*bpm\)\s*\*\s*BEATS_PER_MEASURE/);
  // Core: (60.0 / bpm) * BEATS_PER_MEASURE as f32
  assert.match(coreLoops, /\(60\.0\s*\/\s*bpm\)\s*\*\s*BEATS_PER_MEASURE\s*as\s*f32/);
});
