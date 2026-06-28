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

test('empty Library gives first-time users a full-size import button with a UI-test hook', () => {
  const i = app.indexOf('"Add a song"');
  assert.notEqual(i, -1, 'empty-library Add a song button exists');
  const block = app.slice(app.lastIndexOf('Button(action: onImport)', i), app.indexOf('Spacer()', i));
  assert.match(block, /Text\("Add a song"\)/, 'precondition: primary empty-state import CTA');
  assert.match(block, /Stem\.minimumHitTarget/,
    'empty-library import button must reserve a >= 44pt target');
  assert.match(block, /\.contentShape\(Rectangle\(\)\)/,
    'empty-library import button must make its whole target tappable');
  assert.match(block, /\.accessibilityIdentifier\("library\.empty\.add"\)/,
    'empty-library import needs a stable UI automation hook');
});

test('Library project rows have unique automation hooks and whole-card tap areas', () => {
  const list = slice(app, 'ForEach(library.projects)', 'ScrollView {');
  assert.match(list, /Button \{ onOpen\(project\) \} label: \{ ProjectRow\(project: project\) \}/,
    'precondition: tapping a project reopens it');
  assert.match(list, /\.accessibilityIdentifier\("project\.row\.\\\(project\.id\.uuidString\)"\)/,
    'project rows need per-project identifiers so UI tests can open a specific cached song');

  const row = slice(app, 'struct ProjectRow', 'private func clock');
  assert.match(row, /Spacer\(\)/, 'precondition: ProjectRow has a transparent gap before the play icon');
  assert.match(row, /\.contentShape\(Rectangle\(\)\)/,
    'the whole visual card, including the Spacer gap, should reopen the project');
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

test('idle splitter exposes first-run load and sample actions as full-size tappable controls', () => {
  const device = slice(app, 'struct DeviceCircleView', 'struct LoopControlBar');

  const load = device.slice(device.indexOf('Button(action: onLoad)'), device.indexOf('Text(model.status)'));
  assert.match(load, /Image\(systemName: "plus\.circle"\)/, 'precondition: center load control exists');
  assert.match(load, /\.frame\(width: Stem\.minimumHitTarget, height: Stem\.minimumHitTarget\)/,
    'center load control needs a real 44pt hit box, not only a large glyph');
  assert.match(load, /\.contentShape\(Rectangle\(\)\)/,
    'center load control should make the full hit box tappable');
  assert.match(load, /\.accessibilityIdentifier\("splitter\.load"\)/,
    'center load control needs a stable UI automation hook');

  const sample = device.slice(device.indexOf('Button("try a sample")'), device.indexOf('.padding(40)'));
  assert.match(sample, /Button\("try a sample"\)/, 'precondition: sample action exists');
  assert.match(sample, /Stem\.minimumHitTarget/,
    'sample action needs a 44pt-height tap target');
  assert.match(sample, /\.contentShape\(Rectangle\(\)\)/,
    'sample action should make its full tap target live');
  assert.match(sample, /\.accessibilityIdentifier\("splitter\.sample"\)/,
    'sample action needs a stable UI automation hook');
});

test('splitter progress and status are observable while a song is processing', () => {
  const device = slice(app, 'struct DeviceCircleView', 'struct LoopControlBar');
  assert.match(device, /if model\.isProcessing/);
  assert.match(device, /ProgressView\(\)/);
  assert.match(device, /model\.splitProgress/);
  assert.match(device, /\.accessibilityIdentifier\("splitter\.progress"\)/,
    'processing progress needs a stable UI automation hook');
  assert.match(device, /Text\(model\.status\)[\s\S]*\.accessibilityIdentifier\("splitter\.status"\)/,
    'processing and error status text needs a stable UI automation hook');
});

test('loop controls use 44pt tap targets and stable identifiers for post-load walkthroughs', () => {
  const loop = slice(app, 'struct LoopControlBar', 'struct TransportView');
  assert.match(loop, /Button\(label\) \{ model\.setAllLoop/,
    'precondition: All loop length buttons exist');
  assert.match(loop, /Button\(text, action: action\)/,
    'precondition: Mute all / Mix-Solo pills exist');
  assert.match(loop, /\.frame\(minHeight: Stem\.minimumHitTarget\)/,
    'loop controls should not rely on small caption-height tap boxes');
  assert.match(loop, /\.contentShape\(Rectangle\(\)\)/,
    'loop controls need their full pill/button area tappable');
  assert.match(loop, /\.accessibilityIdentifier\("loop\./,
    'loop controls need stable UI automation identifiers');
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
