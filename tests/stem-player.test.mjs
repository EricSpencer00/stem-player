import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const STEMS = ['drums', 'vocals', 'bass', 'melody'];

class FakeClassList {
  constructor() {
    this.names = new Set();
  }

  add(...names) {
    names.forEach((name) => this.names.add(name));
  }

  remove(...names) {
    names.forEach((name) => this.names.delete(name));
  }

  toggle(name, force) {
    const shouldAdd = force === undefined ? !this.names.has(name) : Boolean(force);
    if (shouldAdd) this.names.add(name);
    else this.names.delete(name);
    return shouldAdd;
  }

  contains(name) {
    return this.names.has(name);
  }
}

class FakeElement {
  constructor(tagName, ownerDocument, id = '') {
    this.tagName = tagName;
    this.ownerDocument = ownerDocument;
    this.id = id;
    this.children = [];
    this.attributes = new Map();
    this.classList = new FakeClassList();
    this.dataset = {};
    this.style = {};
    this.value = '';
    this.disabled = false;
    this.textContent = '';
    this.innerHTML = '';
    this.listeners = new Map();
  }

  appendChild(child) {
    this.children.push(child);
    return child;
  }

  setAttribute(name, value) {
    const stringValue = String(value);
    this.attributes.set(name, stringValue);
    if (name === 'id') {
      this.id = stringValue;
      this.ownerDocument.elements.set(stringValue, this);
    }
    if (name.startsWith('data-')) {
      const key = name
        .slice(5)
        .replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
      this.dataset[key] = stringValue;
    }
  }

  getAttribute(name) {
    return this.attributes.get(name) ?? null;
  }

  addEventListener(type, handler) {
    const handlers = this.listeners.get(type) ?? [];
    handlers.push(handler);
    this.listeners.set(type, handlers);
  }

  setPointerCapture() {}

  releasePointerCapture() {}

  getBoundingClientRect() {
    return { left: 0, width: 100 };
  }

  getContext() {
    return {
      clearRect() {},
      fillRect() {},
      scale() {},
      set fillStyle(_) {},
    };
  }
}

class FakeDocument {
  constructor() {
    this.elements = new Map();
    this.loopButtons = {};
    this.muteButtons = {};
    this.headphonesButtons = {};
    this.quadrants = {};
    this.volumeInputs = {};
    this.body = new FakeElement('body', this, 'body');
    this.registerStaticElements();
  }

  register(id, tagName = 'div') {
    const element = new FakeElement(tagName, this, id);
    this.elements.set(id, element);
    return element;
  }

  registerStaticElements() {
    [
      'volArcs', 'center', 'centerGlyph', 'centerHint', 'btnPlay', 'btnRestart',
      'btnStop', 'timeline', 'timelineFill', 'timelineHead', 'ringFill',
      'timeCur', 'timeTot', 'fileInput', 'device', 'overlay', 'ovTitle',
      'progWrap', 'progFill', 'ovMsg', 'sampleRows', 'filename', 'playbar',
      'stems-panel', 'waveRow', 'hint', 'wDrums', 'wBass', 'wVocals', 'wMelody',
    ].forEach((id) => this.register(id));

    STEMS.forEach((stem) => {
      this.register(`lbl-${stem}`);
      this.register(`pct-${stem}`).textContent = '80';
      this.register(`mm-${stem}`);
      const input = this.register(`vol-${stem}`, 'input');
      input.classList.add('vol');
      input.dataset.stem = stem;
      input.value = '80';
      this.volumeInputs[stem] = input;

      const quadrant = new FakeElement('button', this);
      quadrant.dataset.stem = stem;
      this.quadrants[stem] = quadrant;

      const mute = new FakeElement('button', this);
      mute.dataset.stem = stem;
      mute.textContent = 'mute';
      this.muteButtons[stem] = mute;

      const headphones = new FakeElement('button', this);
      headphones.dataset.stem = stem;
      headphones.textContent = 'phones';
      this.headphonesButtons[stem] = headphones;

      this.loopButtons[stem] = [0, 1, 2, 3].map((idx) => {
        const button = new FakeElement('button', this);
        button.dataset.loop = String(idx);
        button.dataset.stem = stem;
        button.textContent = String(idx);
        return button;
      });
    });
  }

  createElement(tagName) {
    return new FakeElement(tagName, this);
  }

  createElementNS(_namespace, tagName) {
    return new FakeElement(tagName, this);
  }

  getElementById(id) {
    if (!this.elements.has(id)) this.register(id);
    return this.elements.get(id);
  }

  querySelector(selector) {
    const single = this.querySelectorAll(selector);
    return single[0] ?? null;
  }

  querySelectorAll(selector) {
    const stemMatch = selector.match(/data-stem="([^"]+)"/);
    const stem = stemMatch?.[1];

    if (selector === 'input.vol') return Object.values(this.volumeInputs);
    if (selector === '.stem-mute-btn') return Object.values(this.muteButtons);
    if (selector === '.stem-headphones-btn') return Object.values(this.headphonesButtons);
    if (selector === '.loop-btn') return Object.values(this.loopButtons).flat();
    if (selector.includes('.loop-row') && selector.includes('.loop-btn') && stem) {
      return this.loopButtons[stem];
    }
    if (selector.startsWith('.quadrant') && stem) return [this.quadrants[stem]];
    if (selector.startsWith('.stem-mute-btn') && stem) return [this.muteButtons[stem]];
    if (selector.startsWith('.stem-headphones-btn') && stem) return [this.headphonesButtons[stem]];
    return [];
  }
}

class FakeAudioContext {
  constructor() {
    this.currentTime = 0;
    this.createdSources = [];
    this.createdGains = [];
    this.destination = {};
    this.state = 'running';
  }

  createGain() {
    const gain = {
      gain: { value: 1 },
      connectedTo: null,
      disconnected: false,
      connect(destination) {
        this.connectedTo = destination;
      },
      disconnect() {
        this.disconnected = true;
      },
    };
    this.createdGains.push(gain);
    return gain;
  }

  createBufferSource() {
    const source = {
      buffer: null,
      connectedTo: null,
      loop: false,
      loopStart: 0,
      loopEnd: 0,
      starts: [],
      stopped: false,
      connect(destination) {
        this.connectedTo = destination;
      },
      start(when, offset) {
        this.starts.push({ when, offset });
      },
      stop() {
        this.stopped = true;
      },
    };
    this.createdSources.push(source);
    return source;
  }

  resume() {
    return Promise.resolve();
  }
}

function loadApp() {
  const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  const inlineScript = html.match(/<script>\s*'use strict';([\s\S]*)<\/script>/);
  assert.ok(inlineScript, 'expected to find app script in index.html');

  const document = new FakeDocument();
  const window = {
    addEventListener() {},
    devicePixelRatio: 1,
  };
  const context = vm.createContext({
    console,
    document,
    window,
    alert(message) {
      context.__alerts.push(message);
    },
    requestAnimationFrame() {
      return 1;
    },
    cancelAnimationFrame() {},
    setTimeout,
    clearTimeout,
    getComputedStyle() {
      return { getPropertyValue: () => 'oklch(24% 0.012 64)' };
    },
    AudioContext: FakeAudioContext,
    File,
    Blob,
    URL,
    ort: { env: { wasm: {} } },
    __alerts: [],
  });
  context.globalThis = context;

  const exportApp = `
globalThis.__app = {
  STEMS,
  LOOP_BARS,
  state,
  sources,
  gains,
  buffers,
  setLoop,
  startPlayback,
  stopPlayback,
  currentTime,
  setVolume,
  setMute,
  toggleMute,
  resumeAudioContextForDecode: typeof resumeAudioContextForDecode === 'function' ? resumeAudioContextForDecode : undefined,
  setHeadphones: typeof setHeadphones === 'function' ? setHeadphones : undefined,
  resetAllTracks: typeof resetAllTracks === 'function' ? resetAllTracks : undefined,
  hasMutedTracks: typeof hasMutedTracks === 'function' ? hasMutedTracks : undefined,
  setAudioContext(ctx) { audioCtx = ctx; },
  getAudioContext() { return audioCtx; }
};`;

  vm.runInContext(`'use strict';${inlineScript[1]}\n${exportApp}`, context);
  return { app: context.__app, document, context };
}

function preparePlayback(app, audioCtx, offset = 0) {
  app.setAudioContext(audioCtx);
  app.state.ready = true;
  app.state.duration = 30;
  app.state.pauseOffset = offset;
  STEMS.forEach((stem) => {
    app.buffers[stem] = { duration: 30 };
  });
}

test('loop buttons represent quarter, half, one, and two measure lengths', () => {
  const { app } = loadApp();

  assert.deepEqual(Array.from(app.LOOP_BARS), [0.25, 0.5, 1, 2]);
});

test('decode setup does not wait forever when Safari keeps AudioContext suspended', async () => {
  const { app } = loadApp();
  let resumeCalled = false;
  const safariLikeContext = {
    state: 'suspended',
    resume() {
      resumeCalled = true;
      return new Promise(() => {});
    },
  };

  assert.equal(typeof app.resumeAudioContextForDecode, 'function');
  const started = Date.now();
  await app.resumeAudioContextForDecode(safariLikeContext, 5);

  assert.equal(resumeCalled, true);
  assert.ok(Date.now() - started < 100);
});

test('play waits for a suspended AudioContext to resume before starting sources', async () => {
  const { app, document } = loadApp();
  const audioCtx = new FakeAudioContext();
  const startStates = [];
  const originalCreateBufferSource = audioCtx.createBufferSource.bind(audioCtx);

  audioCtx.state = 'suspended';
  audioCtx.resume = function resume() {
    return new Promise((resolve) => {
      setTimeout(() => {
        this.state = 'running';
        resolve();
      }, 5);
    });
  };
  audioCtx.createBufferSource = function createBufferSource() {
    const source = originalCreateBufferSource();
    const originalStart = source.start.bind(source);
    source.start = (when, offset) => {
      startStates.push(audioCtx.state);
      originalStart(when, offset);
    };
    return source;
  };

  preparePlayback(app, audioCtx);

  const playHandler = document.getElementById('btnPlay').listeners.get('click')?.[0];
  assert.equal(typeof playHandler, 'function');
  await playHandler();

  assert.deepEqual(startStates, ['running', 'running', 'running', 'running']);
  assert.equal(app.state.playing, true);
});

test('play attempts to resume an interrupted AudioContext before starting playback', async () => {
  const { app, document } = loadApp();
  const audioCtx = new FakeAudioContext();
  let resumeCalled = false;

  audioCtx.state = 'interrupted';
  audioCtx.resume = function resume() {
    resumeCalled = true;
    this.state = 'running';
    return Promise.resolve();
  };

  preparePlayback(app, audioCtx);

  const playHandler = document.getElementById('btnPlay').listeners.get('click')?.[0];
  assert.equal(typeof playHandler, 'function');
  await playHandler();

  assert.equal(resumeCalled, true);
  assert.equal(app.state.playing, true);
});

test('enabling a loop captures the current beat partition and keeps playing from the current offset', () => {
  const { app } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.state.bpm = 120;
  app.startPlayback(0);
  const originalSource = app.sources.drums;
  audioCtx.currentTime = 2.26;

  app.setLoop('drums', 0);

  assert.equal(app.state.loopStart.drums, 2);
  assert.equal(app.state.loopEnd.drums, 2.5);
  assert.equal(app.sources.drums, originalSource);
  assert.equal(app.sources.drums.loop, true);
  assert.equal(app.sources.drums.loopStart, 2);
  assert.equal(app.sources.drums.loopEnd, 2.5);
  assert.equal(app.sources.drums.starts.length, 1);
});

test('changing a loop while playing keeps the current stem source and only updates its loop points', () => {
  const { app } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.state.bpm = 120;
  app.startPlayback(0);
  const original = Object.fromEntries(STEMS.map((stem) => [stem, app.sources[stem]]));
  const originalStartTime = app.state.startTime;
  audioCtx.currentTime = 3.1;

  app.setLoop('vocals', 1);

  assert.equal(app.sources.vocals, original.vocals);
  assert.equal(original.vocals.stopped, false);
  assert.equal(app.sources.vocals.loop, true);
  assert.equal(app.sources.vocals.loopStart, 3);
  assert.equal(app.sources.vocals.loopEnd, 4);
  assert.equal(app.sources.vocals.starts.length, 1);
  assert.equal(app.sources.drums, original.drums);
  assert.equal(app.sources.bass, original.bass);
  assert.equal(app.sources.melody, original.melody);
  assert.equal(original.drums.stopped, false);
  assert.equal(original.bass.stopped, false);
  assert.equal(original.melody.stopped, false);
  assert.equal(app.state.startTime, originalStartTime);
});

test('disabling a loop while playing leaves the current stem source running in time', () => {
  const { app } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.state.bpm = 120;
  app.startPlayback(0);
  const originalSource = app.sources.bass;

  app.setLoop('bass', 2);
  app.setLoop('bass', -1);

  assert.equal(app.sources.bass, originalSource);
  assert.equal(app.sources.bass.loop, false);
  assert.equal(app.sources.bass.starts.length, 1);
  assert.equal(originalSource.stopped, false);
});

test('headphones isolate one stem without changing mute or volume state', () => {
  const { app } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.startPlayback(0);
  app.setMute('drums', true);
  app.setVolume('bass', 0.35);

  assert.equal(typeof app.setHeadphones, 'function');
  app.setHeadphones('bass', true);

  assert.equal(app.state.muted.drums, true);
  assert.equal(app.state.volume.bass, 0.35);
  assert.equal(app.gains.bass.gain.value, 0.35);
  assert.equal(app.gains.drums.gain.value, 0);
  assert.equal(app.gains.vocals.gain.value, 0);
  assert.equal(app.gains.melody.gain.value, 0);

  app.setHeadphones('bass', false);
  assert.equal(app.gains.drums.gain.value, 0);
  assert.equal(app.gains.bass.gain.value, 0.35);
  assert.equal(app.gains.vocals.gain.value, 0.8);
});

test('unsilence reset clears mutes, headphones, and restores default volume', () => {
  const { app } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.startPlayback(0);

  assert.equal(typeof app.resetAllTracks, 'function');
  app.setMute('drums', true);
  app.setVolume('bass', 0.25);
  app.setHeadphones('vocals', true);
  app.resetAllTracks();

  for (const stem of STEMS) {
    assert.equal(app.state.muted[stem], false);
    assert.equal(app.state.volume[stem], 0.8);
    assert.equal(app.gains[stem].gain.value, 0.8);
  }
  assert.equal(app.state.headphonesStem, null);
});
