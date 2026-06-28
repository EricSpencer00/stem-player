import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// UI/UX hit-target + overlap contracts for the Apple SwiftUI app. These catch
// the "stupid stuff": a button whose tappable box is smaller than it looks (you
// have to click exactly on the text/icon), and chrome that can overlap.
//
// SwiftUI gotcha these encode: a `.buttonStyle(.plain)` label that contains a
// `Spacer()` or only a small glyph inside a larger `.frame` is hit-tested ONLY
// on its drawn content unless it declares a `.contentShape(...)` or an opaque
// `.background(...)`. The transparent padding/Spacer is dead to touch. Every
// interactive control below must make its whole visual area tappable.

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const r = (...p) => join(root, ...p);
const read = (...p) => readFileSync(r(...p), 'utf8');

const app = read('native', 'apple', 'Stemacle', 'StemacleApp.swift');
const tokens = read('native', 'apple', 'Stemacle', 'DesignTokens.swift');

/** Return the source of `struct/func name … ` up to `endMarker` (exclusive). */
const slice = (src, startMarker, endMarker) => {
  const i = src.indexOf(startMarker);
  assert.notEqual(i, -1, `expected to find ${startMarker}`);
  const j = endMarker ? src.indexOf(endMarker, i + startMarker.length) : src.length;
  return src.slice(i, j === -1 ? src.length : j);
};

test('design system pins a 44pt minimum hit target (Apple HIG)', () => {
  assert.match(tokens, /static let minimumHitTarget: CGFloat = 44/);
});

// --- Settings rows: the dead-Spacer-gap bug ---------------------------------

test('SettingsRow is tappable across the whole row, not just the text', () => {
  const row = slice(app, 'struct SettingsRow', 'struct SettingsLinkRow');
  // Precondition: there is a Spacer pushing the chevron to the trailing edge,
  // which leaves a transparent middle gap.
  assert.match(row, /Spacer\(\)/, 'precondition: SettingsRow has a Spacer gap');
  assert.match(row, /\.frame\(minHeight: Stem\.minimumHitTarget\)/, 'row is at least 44pt tall');
  // The fix: a contentShape so the gap + full height are hittable.
  assert.match(row, /\.contentShape\(Rectangle\(\)\)/,
    'SettingsRow needs .contentShape(Rectangle()) or the Spacer gap is dead to taps');
});

test('SettingsLinkRow is tappable across the whole row, not just the text', () => {
  const row = slice(app, 'struct SettingsLinkRow', 'struct SettingsView');
  assert.match(row, /Spacer\(\)/, 'precondition: SettingsLinkRow has a Spacer gap');
  assert.match(row, /\.frame\(minHeight: Stem\.minimumHitTarget\)/);
  assert.match(row, /\.contentShape\(Rectangle\(\)\)/,
    'SettingsLinkRow needs .contentShape(Rectangle()) so the whole row opens the link');
});

// --- Library "Add" button: tiny text-only target ----------------------------

test('Library Add button has a 44pt hit target, not just the label glyphs', () => {
  // Window from the Add label to just past its accessibility id.
  const i = app.indexOf('"library.add"');
  assert.notEqual(i, -1, 'library.add button exists');
  const block = app.slice(app.lastIndexOf('Button(action: onImport)', i), i + 20);
  assert.match(block, /Label\("Add", systemImage: "plus"\)/, 'precondition: bare Label button');
  assert.match(block, /Stem\.minimumHitTarget/,
    'Library Add button must reserve a >= 44pt hit target');
  assert.match(block, /\.contentShape\(Rectangle\(\)\)/,
    'Library Add button must make its whole target tappable, not just the text');
});

// --- Icon-only buttons: dead corners around a centered glyph -----------------

test('transport buttons make their full 44pt frame tappable, not just the glyph', () => {
  const fn = slice(app, 'private func transportButton', 'private func');
  assert.match(fn, /\.frame\(width: Stem\.minimumHitTarget, height: Stem\.minimumHitTarget\)/,
    'precondition: 44pt frame around a ~20pt glyph');
  assert.match(fn, /\.contentShape\(Rectangle\(\)\)/,
    'transport button needs .contentShape so the padding around the glyph is tappable');
});

test('stem mute/solo icon toggles are tappable across the whole 44pt circle', () => {
  const fn = slice(app, 'private func iconToggle', 'struct SettingsView');
  assert.match(fn, /\.frame\(width: Stem\.minimumHitTarget, height: Stem\.minimumHitTarget\)/);
  // When toggled off the background is .clear, so without a contentShape only
  // the 14pt glyph is hittable.
  assert.match(fn, /\.contentShape\(Circle\(\)\)/,
    'iconToggle needs .contentShape(Circle()) so the off-state corners are tappable');
});

test('splitter change-song (+) button is fully tappable, not just the plus glyph', () => {
  const i = app.indexOf('"splitter.add"');
  assert.notEqual(i, -1, 'splitter.add button exists');
  const block = app.slice(app.lastIndexOf('Button(action: onImport)', i), i + 20);
  assert.match(block, /Image\(systemName: "plus\.circle"\)/, 'precondition: plus icon button');
  assert.match(block, /\.frame\(width: Stem\.minimumHitTarget, height: Stem\.minimumHitTarget\)/);
  assert.match(block, /\.contentShape\(Rectangle\(\)\)/,
    'change-song button needs .contentShape so the whole 44pt frame is tappable');
});

// --- Overlap contracts ------------------------------------------------------

test('splitter title cannot overlap the change-song button (length-bounded)', () => {
  // A long song title must shrink/elide instead of growing under the trailing +.
  const header = slice(app, 'Text(model.isReady && !model.songTitle.isEmpty', 'TransportView');
  assert.match(header, /\.lineLimit\(1\)/, 'title is single-line');
  assert.match(header, /\.minimumScaleFactor\(0\.75\)/, 'title scales down before clipping');
  assert.match(header, /\.layoutPriority\(1\)/, 'title yields width to the trailing button');
  assert.match(header, /Spacer\(\)/, 'a Spacer separates title from the + button');
});

test('Mixer route rows keep stem name and A/B picker in fixed lanes (no overlap)', () => {
  const mixer = read('native', 'apple', 'Stemacle', 'Mixer.swift');
  const row = slice(mixer, 'private func routeRow', 'struct ');
  assert.match(row, /Text\(stem\.capitalized\)[\s\S]*\.frame\(width: 80, alignment: \.leading\)/,
    'stem name has a fixed-width lane');
  assert.match(row, /\.pickerStyle\(\.segmented\)[\s\S]*\.frame\(width: 120\)/,
    'A/B picker has a fixed-width lane');
  assert.match(row, /Spacer\(\)/, 'a Spacer keeps the two lanes apart');
});
