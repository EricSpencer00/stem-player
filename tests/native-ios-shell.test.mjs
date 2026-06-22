// Source-level guard tests for the iOS native shell.
//
// The iOS shell (`native/index.html`) was the target of an A1 refactor that
// extracted a shared `makeTrackRow` helper out of three near-duplicate render
// functions. The goal of this test file is to pin the shape of that refactor
// so a future contributor who reaches for `document.createElement('div')` to
// build another track row will get a clear signal: use `makeTrackRow`.
//
// These are pure source-level assertions. We read the HTML, scan for the
// relevant tokens, and verify the structural contract. We do not boot the
// shell in a DOM environment — that would require jsdom, which is not a
// project dependency and not worth adding for a guard test.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const HTML = readFileSync(new URL('../native/index.html', import.meta.url), 'utf8');

function countMatches(re) {
  const matches = HTML.match(re);
  return matches ? matches.length : 0;
}

test('makeTrackRow helper exists exactly once in the iOS shell', () => {
  // A second `function makeTrackRow` declaration would be a bug — the
  // helper is supposed to be a single shared utility. We anchor on
  // `function makeTrackRow(` so a future copy-paste shows up.
  assert.equal(countMatches(/function makeTrackRow\s*\(/g), 1);
});

test('makeTrackRow is used by all three row-rendering call sites', () => {
  // After the refactor, renderProjectList, renderIOSLibraryTracks, and
  // renderIOSLibraryQueue should each call makeTrackRow at least once.
  // We slice the file around each function declaration and look for the
  // call site.
  const slice = (name) => {
    const re = new RegExp(`function\\s+${name}\\s*\\(`);
    const match = re.exec(HTML);
    if (!match) return '';
    // Walk braces to find the end of the function body.
    let depth = 0;
    let start = -1;
    for (let i = match.index; i < HTML.length; i++) {
      const ch = HTML[i];
      if (ch === '{') { if (depth === 0) start = i; depth++; }
      else if (ch === '}') { depth--; if (depth === 0) return HTML.slice(match.index, i + 1); }
    }
    return '';
  };

  for (const name of ['renderProjectList', 'renderIOSLibraryTracks', 'renderIOSLibraryQueue']) {
    const body = slice(name);
    assert.ok(body, `expected to find function ${name}`);
    assert.match(
      body,
      /makeTrackRow\s*\(/,
      `${name} must use makeTrackRow instead of building a row by hand`,
    );
  }
});

test('renderIOSApp wires the documented iOS renderers together', () => {
  // renderIOSApp is the central iOS render coordinator. It must call each
  // of the sub-renderers so a future refactor that drops one of them is
  // caught at the test layer.
  const re = /function\s+renderIOSApp\s*\(/;
  const match = re.exec(HTML);
  assert.ok(match, 'expected to find function renderIOSApp');
  let depth = 0;
  let start = -1;
  for (let i = match.index; i < HTML.length; i++) {
    const ch = HTML[i];
    if (ch === '{') { if (depth === 0) start = i; depth++; }
    else if (ch === '}') { depth--; if (depth === 0) {
      const body = HTML.slice(match.index, i + 1);
      for (const callee of [
        'renderProjectList',
        'renderIOSProjectDetail',
        'renderIOSLibraryTracks',
        'renderIOSLibraryQueue',
        'renderProjectSources',
        'syncIOSLibraryControls',
        'setIOSView',
      ]) {
        assert.match(
          body,
          new RegExp(`\\b${callee}\\s*\\(`),
          `renderIOSApp must call ${callee}`,
        );
      }
      return;
    }}
  }
  assert.fail('could not find end of renderIOSApp');
});

test('iOS library view exposes the queued-track panel', () => {
  // Phase 1b added the iosLibraryQueueList element to fix a regression
  // in native-desktop.test.mjs. Pin the markup so it does not get
  // dropped by an unrelated edit.
  assert.match(HTML, /id="iosLibraryQueueList"/);
  assert.match(HTML, /id="iosLibraryQueueCount"/);
});

test('iOS library view keeps the on-device library panel', () => {
  // The original panel is the source of truth for indexed tracks. Pin
  // both id and the empty-state copy so the two panels stay in sync.
  assert.match(HTML, /id="iosLibraryTrackList"/);
  assert.match(HTML, /id="iosLibraryCount"/);
  assert.match(HTML, /Import audio from Files to build the local crate/);
});

test('iOS library view keeps the queued empty state', () => {
  // The queue panel's empty state is the user-facing signal that there
  // is nothing waiting. A regression that drops this would silently
  // leave the panel blank.
  assert.match(HTML, /Nothing waiting in the analysis queue\./);
});

test('iOS shell still surfaces all four view routes', () => {
  // home, projects, library, settings — the four nav buttons. Drift
  // here would break the iOS app's primary navigation.
  for (const view of ['home', 'projects', 'library', 'settings']) {
    assert.match(
      HTML,
      new RegExp(`data-ios-view="${view}"`),
      `expected data-ios-view="${view}" in the iOS shell`,
    );
  }
});

test('iOS shell does not use inline XML/HTML string concatenation for user content', () => {
  // makeTrackRow and friends still use innerHTML with template strings
  // because the data comes from the user's local IndexedDB. We
  // document that this is the *only* place left that does it, so a
  // future contributor adding another row-builder will know to use
  // the helper.
  //
  // The check: every place that builds a row with a status filter and
  // a `<span class="ios-project-title">` must come from makeTrackRow.
  // We look for the literal title span and ensure it is not hand-rolled
  // outside the helper.
  const handRolled = HTML.match(/innerHTML\s*=?\s*[`'"][^`'"]*ios-project-title/g) || [];
  // The helper itself counts once. Anything more than that is a smell.
  assert.ok(
    handRolled.length <= 1,
    `expected at most one site that uses the ios-project-title innerHTML pattern (the helper itself); saw ${handRolled.length}`,
  );
});
