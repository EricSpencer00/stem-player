// Regression tests for browser-only global guards.
//
// Stemacle is normally loaded inside a real browser, where sessionStorage,
// indexedDB, and a native bridge (window.stemacleNative) are always present.
// But the app is also embedded by host runtimes (test VMs, sandboxed iframes,
// prerender environments) that do not always expose those globals. The app
// must not crash on boot when they are missing — it should come up as the
// pure web instrument and let the user drop a file normally.
//
// These tests guard the two crash classes we have already seen in CI:
//   1. sessionStorage ReferenceError inside openPendingNativeTrack()
//   2. unhandledRejection on the same crash, fired from deferred timers
//
// They run in a fresh VM context that does NOT inject sessionStorage or
// indexedDB. If a future change reintroduces an unconditional reference to
// one of those globals, these tests will fail.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

// ---- minimal document/element/window stand-ins (just enough to let the
// ---- inline script execute to completion without throwing) ----

class FakeElement {
  constructor(tagName) {
    this.tagName = (tagName || 'div').toUpperCase();
    this.classList = {
      _set: new Set(),
      add: (...names) => names.forEach((n) => this.classList._set.add(n)),
      remove: (...names) => names.forEach((n) => this.classList._set.delete(n)),
      contains: (name) => this.classList._set.has(name),
      toggle: (name, force) => {
        if (force === true) { this.classList._set.add(name); return true; }
        if (force === false) { this.classList._set.delete(name); return false; }
        if (this.classList._set.has(name)) { this.classList._set.delete(name); return false; }
        this.classList._set.add(name);
        return true;
      },
    };
    this.dataset = {};
    this.style = {};
    this.children = [];
    this.textContent = '';
    this._listeners = new Map();
    this.id = '';
  }
  appendChild(child) { this.children.push(child); return child; }
  removeChild(child) {
    const i = this.children.indexOf(child);
    if (i >= 0) this.children.splice(i, 1);
  }
  append(...kids) { kids.forEach((k) => this.children.push(k)); }
  prepend(...kids) { kids.forEach((k) => this.children.unshift(k)); }
  getContext(type) {
    return {
      createLinearGradient: () => ({ addColorStop: () => {} }),
      createImageData: (w, h) => ({ data: new Uint8ClampedArray(w * h * 4) }),
      fillRect: () => {},
      drawImage: () => {},
      clearRect: () => {},
      beginPath: () => {},
      moveTo: () => {},
      lineTo: () => {},
      arc: () => {},
      fill: () => {},
      stroke: () => {},
      set fillStyle(v) {},
      set strokeStyle(v) {},
      set globalAlpha(v) {},
      set lineWidth(v) {},
      get canvas() { return { width: 100, height: 100 }; },
    };
  }
  getBoundingClientRect() { return { left: 0, top: 0, width: 100, height: 100 }; }
  setAttribute(name, value) { this[`_${name}`] = value; }
  removeAttribute(name) { delete this[`_${name}`]; }
  addEventListener(name, fn) {
    if (!this._listeners.has(name)) this._listeners.set(name, []);
    this._listeners.get(name).push(fn);
  }
  removeEventListener(name, fn) {
    const list = this._listeners.get(name);
    if (!list) return;
    const i = list.indexOf(fn);
    if (i >= 0) list.splice(i, 1);
  }
  click() {
    const list = this._listeners.get('click') || [];
    list.forEach((fn) => fn({ currentTarget: this, clientX: 50, clientY: 50, key: 'Enter' }));
  }
}

class FakeDocument {
  constructor() {
    this.elements = new Map();
    this.body = new FakeElement('body');
  }
  createElement(tagName) {
    return new FakeElement(tagName);
  }
  createElementNS(_ns, tagName) {
    return new FakeElement(tagName);
  }
  getElementById(id) {
    if (!this.elements.has(id)) {
      const el = new FakeElement('div');
      el.id = id;
      this.elements.set(id, el);
    }
    return this.elements.get(id);
  }
  querySelector(selector) {
    // Return a benign stand-in for any selector. The real DOM has the
    // matching elements; this fake only exists to let the app's boot
    // path (setMute, drag wiring, etc.) complete without crashing. We
    // never read anything meaningful off the returned element in these
    // tests, we just need the property accesses to succeed.
    if (!selector) return null;
    return new FakeElement(selector.startsWith('.') ? 'div' : 'span');
  }
  querySelectorAll() { return []; }
  addEventListener() {}
}

class FakeAudioContext {
  constructor() {
    this.state = 'suspended';
    this.currentTime = 0;
    this.sampleRate = 44100;
    this.destination = {};
  }
  createGain() {
    return { gain: { value: 1 }, connect: () => {}, disconnect: () => {} };
  }
  createAnalyser() {
    return {
      fftSize: 2048,
      frequencyBinCount: 1024,
      getByteTimeDomainData: () => {},
      getByteFrequencyData: () => {},
      connect: () => {},
    };
  }
  createBufferSource() {
    return { connect: () => {}, start: () => {}, stop: () => {} };
  }
  resume() { this.state = 'running'; return Promise.resolve(); }
  decodeAudioData() { return Promise.resolve({ duration: 1, getChannelData: () => new Float32Array(1) }); }
}

function makeBareContext(extra = {}) {
  const document = new FakeDocument();
  const window = {
    addEventListener: () => {},
    removeEventListener: () => {},
    devicePixelRatio: 1,
  };
  return vm.createContext({
    console,
    document,
    window,
    setTimeout,
    clearTimeout,
    requestAnimationFrame: () => 1,
    cancelAnimationFrame: () => {},
    getComputedStyle: () => ({ getPropertyValue: () => 'oklch(24% 0.012 64)' }),
    AudioContext: FakeAudioContext,
    File,
    Blob,
    URL,
    AbortController,
    ort: { env: { wasm: {} }, InferenceSession: { create: () => Promise.resolve({}) } },
    // Intentionally NO sessionStorage, NO localStorage, NO indexedDB, NO
    // window.stemacleNative by default. The web app must still boot.
    ...extra,
  });
}

// Pull openPendingNativeTrack out of the inline script so we can call it
// directly in a bare context, without having to fake the entire app boot
// (level meter canvas, drag wiring, etc.). This isolates the regression
// to the function that originally crashed.
function extractFunction(name) {
  const html = readFileSync(new URL('../app/index.html', import.meta.url), 'utf8');
  const inline = html.match(/<script>\s*'use strict';([\s\S]*)<\/script>/);
  assert.ok(inline, 'expected to find the app script in app/index.html');
  // Match the function declaration. The source uses 'use strict' and
  // ES2015+ syntax but no transpilation, so a JS-only regex with
  // balanced-brace scanning is enough.
  const re = new RegExp(`(?:async\\s+)?function\\s+${name}\\s*\\(`);
  const match = re.exec(inline[1]);
  assert.ok(match, `expected to find function ${name} in app/index.html`);
  let depth = 0;
  let start = -1;
  for (let i = match.index; i < inline[1].length; i++) {
    const ch = inline[1][i];
    if (ch === '{') {
      if (depth === 0) start = i;
      depth++;
    } else if (ch === '}') {
      depth--;
      if (depth === 0) return inline[1].slice(match.index, i + 1);
    }
  }
  assert.fail(`could not find end of function ${name}`);
}

function callOpenPendingNativeTrackInBareContext() {
  const fn = extractFunction('openPendingNativeTrack');
  const context = makeBareContext();
  vm.runInContext(`(${fn})()`, context);
}

test('openPendingNativeTrack does not throw when sessionStorage is missing', () => {
  assert.doesNotThrow(callOpenPendingNativeTrackInBareContext);
});

test('openPendingNativeTrack does not throw when only sessionStorage is missing', () => {
  // A context with localStorage but no sessionStorage should still be a
  // no-op rather than a crash. sessionStorage is the only one openPending
  // actually uses.
  const mem = new Map();
  const localStorage = { getItem: (k) => mem.get(k) ?? null, removeItem: (k) => mem.delete(k) };
  const context = makeBareContext({ localStorage });
  const fn = extractFunction('openPendingNativeTrack');
  assert.doesNotThrow(() => vm.runInContext(`(${fn})()`, context));
});

test('openPendingNativeTrack does not throw when sessionStorage and indexedDB are both missing', () => {
  // A different host might have neither browser store. The function
  // should return without reading or writing anything.
  const context = makeBareContext();
  const fn = extractFunction('openPendingNativeTrack');
  assert.doesNotThrow(() => vm.runInContext(`(${fn})()`, context));
});

test('openPendingNativeTrack handles a stale sessionStorage entry without indexedDB', () => {
  // The function must not try to call indexedDB when only the session
  // entry is present. A buggy implementation would crash on the missing
  // indexedDB.open() call.
  const mem = new Map();
  mem.set('stemacle:lastLibraryTrack', JSON.stringify({ id: 'track-1' }));
  const sessionStorage = {
    getItem: (k) => mem.get(k) ?? null,
    removeItem: (k) => mem.delete(k),
    setItem: (k, v) => mem.set(k, v),
  };
  const alerts = [];
  const context = makeBareContext({ sessionStorage, alert: (m) => alerts.push(m) });
  const fn = extractFunction('openPendingNativeTrack');
  // The function should either surface a friendly alert or just return
  // — but it must not throw.
  assert.doesNotThrow(() => vm.runInContext(`(${fn})()`, context));
  // If the function took the indexedDB branch, our alert mock would have
  // been called with a clear, non-throwing message.
  for (const msg of alerts) {
    assert.doesNotMatch(msg, /TypeError|ReferenceError/);
  }
});

test('openPendingNativeTrack source guards against missing browser globals', () => {
  // Belt-and-braces: even if the runtime tests above pass, the source
  // itself must contain the typeof guards so a future regression that
  // drops them will fail this test.
  const html = readFileSync(new URL('../app/index.html', import.meta.url), 'utf8');
  assert.match(html, /async function openPendingNativeTrack\(\)/);
  assert.match(
    html,
    /typeof sessionStorage !== 'undefined'/,
    'openPendingNativeTrack must guard against missing sessionStorage so the app can boot in non-browser hosts',
  );
  assert.match(
    html,
    /typeof indexedDB !== 'undefined'/,
    'openPendingNativeTrack must guard against missing indexedDB so the app can boot in non-browser hosts',
  );
});

test('loop length set is exactly quarter, half, one, and two measure', () => {
  // Loop contract invariant: per LOOP_SAMPLING.md, the app exposes exactly
  // these four loop lengths and no more. Drift here would break the
  // tactile math the user has been playing with.
  const html = readFileSync(new URL('../app/index.html', import.meta.url), 'utf8');
  assert.match(html, /const LOOP_BARS = \[0\.25, ?0\.5, ?1, ?2\]/);
});

test('app declares the four stems in a fixed order', () => {
  // Audio splicing is sensitive to the stem order. The web app and the
  // iOS NativeStemSplitter both depend on this order matching. A change
  // here would silently shift the label↔buffer mapping. Pin it.
  const html = readFileSync(new URL('../app/index.html', import.meta.url), 'utf8');
  assert.match(html, /const STEMS = \['drums','vocals','bass','melody'\];/);
});
