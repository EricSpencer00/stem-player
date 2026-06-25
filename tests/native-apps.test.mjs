import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// Structural guards for the native-rewrite architecture: a shared Rust core
// with native UI shells per platform (Apple SwiftUI, Win/Linux Slint) and a
// per-OS model pipeline. Replaces the old WKWebView/Capacitor/Electron shell
// tests, which asserted code removed in the native rewrite.

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const r = (...p) => join(root, ...p);
const read = (...p) => readFileSync(r(...p), 'utf8');

test('shared Rust core workspace has the DSP + FFI crates', () => {
  const ws = read('native', 'core', 'Cargo.toml');
  assert.match(ws, /stemacle-dsp/);
  assert.match(ws, /stemacle-ffi/);
  for (const f of ['fft.rs', 'stft.rs', 'hpss.rs', 'tempo.rs', 'loops.rs', 'lib.rs']) {
    assert.ok(existsSync(r('native', 'core', 'stemacle-dsp', 'src', f)), `dsp/${f}`);
  }
  // The Separator seam exists so neural models can be injected per platform.
  assert.match(read('native', 'core', 'stemacle-dsp', 'src', 'lib.rs'), /trait Separator/);
});

test('C ABI header mirrors the FFI surface', () => {
  const h = read('native', 'core', 'stemacle-ffi', 'include', 'stemacle.h');
  const rs = read('native', 'core', 'stemacle-ffi', 'src', 'lib.rs');
  for (const sym of [
    'stemacle_separate',
    'stemacle_stems_free',
    'stemacle_snap_loop_end',
    'stemacle_loop_range',
    'stemacle_measure_length',
    'stemacle_audible_stem_time',
  ]) {
    assert.match(h, new RegExp(sym), `header declares ${sym}`);
    assert.match(rs, new RegExp(`extern "C" fn ${sym}`), `ffi defines ${sym}`);
  }
});

test('Apple apps are native SwiftUI over StemacleKit, not a webview shell', () => {
  const project = read('native', 'apple', 'project.yml');
  assert.match(project, /StemacleMac:/);
  assert.match(project, /StemacleiOS:/);
  assert.match(project, /platform: macOS/);
  assert.match(project, /platform: iOS/);
  assert.match(project, /package: StemacleKit/);

  const app = read('native', 'apple', 'Stemacle', 'StemacleApp.swift');
  assert.match(app, /import SwiftUI/);
  assert.doesNotMatch(app, /WKWebView|WebKit/);

  // StemacleKit binds the shared Rust core via the XCFramework.
  const pkg = read('native', 'apple', 'StemacleKit', 'Package.swift');
  assert.match(pkg, /StemacleCore\.xcframework/);
  assert.match(read('native', 'apple', 'StemacleKit', 'Sources', 'StemacleKit', 'StemacleKit.swift'),
    /stemacle_separate/);

  // Proper asset catalog with an AppIcon + brand accent.
  assert.ok(existsSync(r('native', 'apple', 'Stemacle', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset', 'Contents.json')));
  assert.ok(existsSync(r('native', 'apple', 'Stemacle', 'Resources', 'Assets.xcassets', 'AccentColor.colorset', 'Contents.json')));
});

test('Windows/Linux app is a Slint shell over the shared core', () => {
  const cargo = read('native', 'desktop', 'Cargo.toml');
  assert.match(cargo, /slint/);
  assert.match(cargo, /stemacle-dsp/);
  assert.doesNotMatch(cargo, /electron/);
  assert.ok(existsSync(r('native', 'desktop', 'ui', 'stemacle.slint')));
  assert.match(read('native', 'desktop', 'src', 'player.rs'), /fn export_stems/);
});

test('model pipeline targets CoreML + ONNX from Demucs', () => {
  const py = read('models', 'convert_demucs.py');
  assert.match(py, /htdemucs/);
  assert.match(py, /coreml/i);
  assert.match(py, /onnx/i);
  // other -> melody stem mapping is explicit
  assert.match(py, /STEMACLE_STEMS/);
});
