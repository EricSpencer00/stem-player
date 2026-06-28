import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const coreManifest = join(root, 'native', 'core', 'Cargo.toml');

function hasCargo() {
  const probe = spawnSync('cargo', ['--version'], { encoding: 'utf8' });
  return probe.status === 0;
}

test('shared Rust DSP core workspace exists', () => {
  assert.ok(existsSync(coreManifest), 'native/core/Cargo.toml should exist');
  for (const f of ['fft.rs', 'stft.rs', 'hpss.rs', 'tempo.rs', 'loops.rs', 'lib.rs']) {
    assert.ok(
      existsSync(join(root, 'native', 'core', 'stemacle-dsp', 'src', f)),
      `stemacle-dsp/src/${f} should exist`,
    );
  }
});

test('Rust DSP core golden/reconstruction tests pass', { timeout: 600000 }, (t) => {
  if (!hasCargo()) {
    t.skip('cargo not installed on this host');
    return;
  }
  const result = spawnSync('cargo', ['test', '--manifest-path', coreManifest], {
    cwd: root,
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, `cargo test failed:\n${result.stdout}\n${result.stderr}`);
  // Sanity: the suite reports the DSP + loop-contract tests we expect.
  assert.match(result.stdout, /test result: ok/);
});
