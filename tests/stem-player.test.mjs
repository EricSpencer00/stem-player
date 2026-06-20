import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const STEMS = ['drums', 'vocals', 'bass', 'melody'];
const LOOP_TARGETS = [...STEMS, 'all'];

function loadHtml() {
  return readFileSync(new URL('../index.html', import.meta.url), 'utf8');
}

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
      beginPath() {},
      moveTo() {},
      lineTo() {},
      arc() {},
      closePath() {},
      stroke() {},
      fill() {},
      fillText() {},
      save() {},
      restore() {},
      translate() {},
      rotate() {},
      scale() {},
      set fillStyle(_) {},
      set strokeStyle(_) {},
      set lineWidth(_) {},
      set font(_) {},
      set textAlign(_) {},
      set textBaseline(_) {},
      set globalAlpha(_) {},
      set globalCompositeOperation(_) {},
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
      'stems-panel', 'hint', 'viewStartTime', 'viewEndTime', 'viewWindowLabel',
      'btnMuteAll', 'loopAuditionMix', 'loopAuditionSolo', 'levelMeter',
      'overlayCancel',
    ].forEach((id) => this.register(id));

    STEMS.forEach((stem) => {
      this.register(`lbl-${stem}`);
      this.register(`pct-${stem}`).textContent = '80';
      this.register(`mm-${stem}`);
      this.register(`spec-${stem}`, 'canvas');
      this.register(`cursor-${stem}`);
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

    this.loopButtons.all = [0, 1, 2, 3].map((idx) => {
      const button = new FakeElement('button', this);
      button.dataset.loop = String(idx);
      button.dataset.stem = 'all';
      button.textContent = String(idx);
      return button;
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
    this.createdAnalysers = [];
    this.destination = {};
    this.state = 'running';
    this.sampleRate = 44100;
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

  createAnalyser() {
    const analyser = {
      fftSize: 2048,
      frequencyBinCount: 1024,
      smoothingTimeConstant: 0,
      connectedTo: null,
      timeData: null,
      frequencyData: null,
      connect(destination) {
        this.connectedTo = destination;
      },
      getByteTimeDomainData(target) {
        const source = this.timeData || new Uint8Array(target.length).fill(128);
        for (let i = 0; i < target.length; i++) target[i] = source[i % source.length];
      },
      getByteFrequencyData(target) {
        const source = this.frequencyData || new Uint8Array(target.length);
        for (let i = 0; i < target.length; i++) target[i] = source[i % source.length];
      },
    };
    this.createdAnalysers.push(analyser);
    return analyser;
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

  decodeAudioData() {
    return Promise.resolve({
      duration: 30,
      numberOfChannels: 1,
      sampleRate: 44100,
      getChannelData() {
        return new Float32Array(44100);
      },
    });
  }
}

function loadApp() {
  const html = loadHtml();
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
    AbortController,
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
  estimateTempo: typeof estimateTempo === 'function' ? estimateTempo : undefined,
  chooseTempoCandidate: typeof chooseTempoCandidate === 'function' ? chooseTempoCandidate : undefined,
  measureLength: typeof measureLength === 'function' ? measureLength : undefined,
  snapLoopStart: typeof snapLoopStart === 'function' ? snapLoopStart : undefined,
  snapLoopEnd: typeof snapLoopEnd === 'function' ? snapLoopEnd : undefined,
  audibleStemTime: typeof audibleStemTime === 'function' ? audibleStemTime : undefined,
  spectralWindowFor: typeof spectralWindowFor === 'function' ? spectralWindowFor : undefined,
  spectralGridMarkers: typeof spectralGridMarkers === 'function' ? spectralGridMarkers : undefined,
  timeToSpectralPercent: typeof timeToSpectralPercent === 'function' ? timeToSpectralPercent : undefined,
  spectralTimeFromClientX: typeof spectralTimeFromClientX === 'function' ? spectralTimeFromClientX : undefined,
  levelMeterBandsAt: typeof levelMeterBandsAt === 'function' ? levelMeterBandsAt : undefined,
  meterWavePoints: typeof meterWavePoints === 'function' ? meterWavePoints : undefined,
  setLoop,
  startPlayback,
  stopPlayback,
  currentTime,
  setVolume,
  setMute,
  toggleMute,
  resumeAudioContextForDecode: typeof resumeAudioContextForDecode === 'function' ? resumeAudioContextForDecode : undefined,
  decodeAudioDataWithTimeout: typeof decodeAudioDataWithTimeout === 'function' ? decodeAudioDataWithTimeout : undefined,
  downloadModelFile: typeof downloadModelFile === 'function' ? downloadModelFile : undefined,
  setHeadphones: typeof setHeadphones === 'function' ? setHeadphones : undefined,
  setAllMuted: typeof setAllMuted === 'function' ? setAllMuted : undefined,
  toggleAllMuted: typeof toggleAllMuted === 'function' ? toggleAllMuted : undefined,
  resetAllTracks: typeof resetAllTracks === 'function' ? resetAllTracks : undefined,
  hasMutedTracks: typeof hasMutedTracks === 'function' ? hasMutedTracks : undefined,
  areAllMuted: typeof areAllMuted === 'function' ? areAllMuted : undefined,
  clearAllLoops: typeof clearAllLoops === 'function' ? clearAllLoops : undefined,
  updateSampleRowsVisibility: typeof updateSampleRowsVisibility === 'function' ? updateSampleRowsVisibility : undefined,
  setLoopAuditionMode: typeof setLoopAuditionMode === 'function' ? setLoopAuditionMode : undefined,
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

function assertAlmostEqual(actual, expected, tolerance = 1e-9) {
  assert.ok(
    Math.abs(actual - expected) <= tolerance,
    `expected ${actual} to be within ${tolerance} of ${expected}`,
  );
}

function makePulseTrain({ bpm, offset = 0, duration = 12, sampleRate = 1000 }) {
  const signal = new Float32Array(Math.ceil(duration * sampleRate));
  const beat = 60 / bpm;
  for (let t = offset; t < duration; t += beat) {
    const center = Math.round(t * sampleRate);
    for (let i = 0; i < 24; i++) {
      const idx = center + i;
      if (idx < signal.length) signal[idx] += 1 - (i / 24);
    }
  }
  return { signal, sampleRate };
}

function makeFourFourPulseTrain({ bpm, beatOffset = 0, downbeatPhase = 0, duration = 16, sampleRate = 1000 }) {
  const signal = new Float32Array(Math.ceil(duration * sampleRate));
  const beat = 60 / bpm;
  for (let beatIndex = 0, t = beatOffset; t < duration; beatIndex++, t += beat) {
    const phase = ((beatIndex % 4) + 4) % 4;
    const amp = phase === downbeatPhase ? 1 : 0.32;
    const center = Math.round(t * sampleRate);
    for (let i = 0; i < 24; i++) {
      const idx = center + i;
      if (idx < signal.length) signal[idx] += amp * (1 - (i / 24));
    }
  }
  return { signal, sampleRate };
}

test('loop buttons represent quarter, half, one, and two measure lengths', () => {
  const { app } = loadApp();

  assert.deepEqual(Array.from(app.LOOP_BARS), [0.25, 0.5, 1, 2]);
});

test('stem rows contain row-level spectrogram canvases and play cursors', () => {
  const html = loadHtml();

  for (const stem of STEMS) {
    assert.match(html, new RegExp(`<canvas[^>]+class="stem-spectrum"[^>]+id="spec-${stem}"`));
    assert.match(html, new RegExp(`<div[^>]+class="stem-cursor"[^>]+id="cursor-${stem}"`));
  }
});

test('stem rows separate controls from dedicated spectrogram lanes', () => {
  const html = loadHtml();

  assert.match(html, /\.stem-control-strip\s*\{/);
  assert.match(html, /\.stem-spec-lane\s*\{/);
  assert.match(html, /\.stem-row\s*\{(?=[^}]*grid-template-areas:\s*"controls"\s*"spectrogram";)/s);
  assert.match(html, /\.stem-control-strip\s*\{(?=[^}]*grid-template-areas:\s*"name slider actions loops";)/s);
  assert.match(html, /\.stem-spec-lane\s*\{(?=[^}]*grid-area:\s*spectrogram;)(?=[^}]*cursor:\s*crosshair;)/s);

  for (const stem of STEMS) {
    assert.match(
      html,
      new RegExp(`<div class="stem-row" data-stem="${stem}"[\\s\\S]*?<div class="stem-control-strip">[\\s\\S]*?<div class="stem-action-group">[\\s\\S]*?</div>[\\s\\S]*?<div class="loop-row" data-stem="${stem}">[\\s\\S]*?</div>[\\s\\S]*?</div>\\s*<div class="stem-spec-lane" data-stem="${stem}"`),
    );
    assert.match(
      html,
      new RegExp(`<div class="stem-spec-lane" data-stem="${stem}"[^>]*>\\s*<canvas[^>]+class="stem-spectrum"[^>]+id="spec-${stem}"[\\s\\S]*?<div[^>]+class="stem-cursor"[^>]+id="cursor-${stem}"`),
    );
  }
});

test('stem panel is a full-width spectral stage instead of a narrow control stack', () => {
  const html = loadHtml();

  assert.match(html, /#stems-panel\s*\{(?=[^}]*width:\s*min\(1240px,\s*calc\(100vw - 32px\)\);)/s);
  assert.match(html, /\.spectral-ruler\s*\{/s);
  assert.match(html, /<div class="spectral-ruler"[^>]*>/);
});

test('global mute is exposed as one persistent toggle button', () => {
  const html = loadHtml();

  assert.match(html, /<button type="button" class="global-btn" id="btnMuteAll" disabled>mute all<\/button>/);
  assert.doesNotMatch(html, /id="btnUnmuteAll"/);
  assert.match(html, /\.stem-toolbar\s*\{(?=[^}]*grid-template-columns:\s*minmax\(180px,\s*280px\)\s+auto;)/s);
});

test('top circle is a passive level meter instead of quadrant controls', () => {
  const html = loadHtml();

  assert.match(html, /<canvas class="level-meter" id="levelMeter" aria-hidden="true"><\/canvas>/);
  assert.match(html, /\.level-meter\s*\{(?=[^}]*border-radius:\s*50%;)(?=[^}]*pointer-events:\s*none;)/s);
  assert.match(html, /\.quadrant,\s*\.q-label,\s*\.q-mute-mark\s*\{(?=[^}]*display:\s*none;)/s);
});

test('level meter renders a filled waveform ring with a double border', () => {
  const html = loadHtml();

  assert.match(html, /function meterWavePoints\(/);
  assert.match(html, /function drawMeterWaveBand\(/);
  assert.match(html, /ctx\.fill\(\);/);
  assert.match(html, /globalCompositeOperation\s*=\s*'destination-out'/);
  assert.doesNotMatch(html, /traceMeterWaveBand\(ctx,\s*wave\);\s*ctx\.strokeStyle/s);
  assert.doesNotMatch(html, /ctx\.moveTo\(0,\s*-inner\);\s*ctx\.lineTo\(0,\s*-outer\);/);
});

test('vocals headphones control gets a one-off pulse affordance', () => {
  const html = loadHtml();

  assert.match(html, /\.stem-headphones-btn\[data-stem="vocals"\]\s*\{(?=[^}]*position:\s*relative;)(?=[^}]*overflow:\s*visible;)/s);
  assert.match(html, /\.stem-headphones-btn\[data-stem="vocals"\]::after\s*\{(?=[^}]*animation:\s*vocalPhonesPulse\s+[^;]+;)(?=[^}]*border:\s*1px solid var\(--amber-glow\);)/s);
  assert.match(html, /@keyframes vocalPhonesPulse\s*\{/);
});

test('sample track titles fit inside responsive multi-line buttons', () => {
  const html = loadHtml();

  assert.match(html, /\.sample-rows\s*\{(?=[^}]*width:\s*min\(760px,\s*calc\(100vw - 32px\)\);)(?=[^}]*grid-template-columns:\s*repeat\(auto-fit,\s*minmax\(min\(220px,\s*100%\),\s*1fr\)\);)/s);
  assert.match(html, /\.sample-rows button\s*\{(?=[^}]*line-height:\s*1\.25;)(?=[^}]*white-space:\s*normal;)(?=[^}]*overflow-wrap:\s*anywhere;)/s);
  assert.match(html, /btn\.title\s*=\s*track\.name;/);
});

test('footer credits Eric Spencer without external UI inspiration copy', () => {
  const html = loadHtml();

  assert.match(html, /made by <a href="https:\/\/ericspencer\.us"[^>]*>ericspencer\.us<\/a>/i);
  assert.doesNotMatch(html, /UI inspired by/i);
  assert.doesNotMatch(html, /krystalgamer/i);
});

test('touch controls keep fixed hit areas when labels change', () => {
  const html = loadHtml();

  assert.match(html, /\.tbtn\s*\{(?=[^}]*width:\s*112px;)(?=[^}]*min-height:\s*48px;)/s);
  assert.match(html, /\.stem-mute-btn,\s*\.stem-headphones-btn\s*\{(?=[^}]*width:\s*52px;)(?=[^}]*min-height:\s*44px;)/s);
  assert.match(html, /\.global-btn,\s*\.mode-btn\s*\{(?=[^}]*min-height:\s*42px;)/s);
  assert.match(html, /\.loop-row\s*\{(?=[^}]*grid-template-columns:\s*repeat\(4,\s*minmax\(0,\s*1fr\)\);)/s);
  assert.match(html, /\.loop-btn\s*\{(?=[^}]*width:\s*100%;)(?=[^}]*min-height:\s*44px;)/s);
  assert.match(html, /\.timeline-wrap\s*\{(?=[^}]*height:\s*28px;)/s);
});

test('tempo estimator recovers beat tempo and beat-grid offset', () => {
  const { app } = loadApp();
  const { signal, sampleRate } = makePulseTrain({ bpm: 96, offset: 0.18 });

  assert.equal(typeof app.estimateTempo, 'function');
  const tempo = app.estimateTempo(signal, sampleRate);

  assert.ok(Math.abs(tempo.bpm - 96) <= 2, `expected bpm near 96, got ${tempo.bpm}`);
  assert.ok(tempo.confidence > 0.07, `expected usable confidence, got ${tempo.confidence}`);
  assert.ok(Math.abs(tempo.offset - 0.18) <= 0.04, `expected offset near 0.18, got ${tempo.offset}`);
});

test('tempo estimator prefers the 4/4 downbeat when one beat phase is accented', () => {
  const { app } = loadApp();
  const { signal, sampleRate } = makeFourFourPulseTrain({
    bpm: 120,
    beatOffset: 0.11,
    downbeatPhase: 2,
  });

  const tempo = app.estimateTempo(signal, sampleRate);

  assert.ok(Math.abs(tempo.bpm - 120) <= 2, `expected bpm near 120, got ${tempo.bpm}`);
  assert.ok(Math.abs(tempo.beatOffset - 0.11) <= 0.04, `expected beat offset near 0.11, got ${tempo.beatOffset}`);
  assert.ok(Math.abs(tempo.offset - 1.11) <= 0.05, `expected measure offset near 1.11, got ${tempo.offset}`);
});

test('tempo candidate selection avoids near-tie half-time loop grids', () => {
  const { app } = loadApp();

  assert.equal(typeof app.chooseTempoCandidate, 'function');
  const selected = app.chooseTempoCandidate([
    { bpm: 61, rawBpm: 61, score: 0.397, lag: 99 },
    { bpm: 91, rawBpm: 91, score: 0.348, lag: 66 },
    { bpm: 182, rawBpm: 182, score: 0.224, lag: 33 },
  ]);

  assert.equal(Math.round(selected.bpm), 91);
  assert.equal(selected.lag, 66);
});

test('loop end snaps to the next selected subdivision on the measured bar grid', () => {
  const { app } = loadApp();
  app.state.duration = 30;
  app.state.bpm = 100;
  app.state.measureOffset = 0.25;

  assert.equal(typeof app.snapLoopEnd, 'function');
  assertAlmostEqual(app.measureLength(), 2.4);
  assertAlmostEqual(app.snapLoopEnd(3.0, 0.6), 3.25);
  assertAlmostEqual(app.snapLoopEnd(2.651, 0.6), 2.65);
  assertAlmostEqual(app.snapLoopEnd(4.7), 5.05);
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

test('decode timeout rejects stalled audio decoding so processing can recover', async () => {
  const { app } = loadApp();
  const stalledContext = {
    decodeAudioData() {
      return new Promise(() => {});
    },
  };

  assert.equal(typeof app.decodeAudioDataWithTimeout, 'function');
  await assert.rejects(
    () => app.decodeAudioDataWithTimeout(stalledContext, new ArrayBuffer(8), 5),
    /timed out/i,
  );
});

test('model download timeout rejects stalled streams so processing can recover', async () => {
  const { app } = loadApp();
  let abortCalled = false;
  let cancelCalled = false;
  const stalledFetch = async (_url, options = {}) => {
    options.signal?.addEventListener('abort', () => {
      abortCalled = true;
    });
    return {
      ok: true,
      headers: {
        get(name) {
          return name.toLowerCase() === 'content-length' ? '100' : null;
        },
      },
      body: {
        getReader() {
          return {
            read() {
              return new Promise(() => {});
            },
            cancel() {
              cancelCalled = true;
              return Promise.resolve();
            },
          };
        },
      },
    };
  };

  assert.equal(typeof app.downloadModelFile, 'function');
  const started = Date.now();
  await assert.rejects(
    () => app.downloadModelFile('https://example.test/accompaniment.onnx', 52, 92, null, {
      fetchFn: stalledFetch,
      timeoutMs: 5,
    }),
    /stalled/i,
  );

  assert.ok(Date.now() - started < 100);
  assert.equal(abortCalled, true);
  assert.equal(cancelCalled, true);
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

test('enabling a loop uses the tempo grid and reschedules only that stem', () => {
  const { app } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.state.bpm = 90;
  app.startPlayback(0);
  const original = Object.fromEntries(STEMS.map((stem) => [stem, app.sources[stem]]));
  audioCtx.currentTime = 2.26;

  app.setLoop('drums', 0);

  assertAlmostEqual(app.state.loopStart.drums, 2);
  assertAlmostEqual(app.state.loopEnd.drums, 8 / 3);
  assert.notEqual(app.sources.drums, original.drums);
  assert.equal(original.drums.stopped, true);
  assert.equal(app.sources.vocals, original.vocals);
  assert.equal(app.sources.bass, original.bass);
  assert.equal(app.sources.melody, original.melody);
  assert.equal(app.sources.drums.loop, true);
  assertAlmostEqual(app.sources.drums.loopStart, 2);
  assertAlmostEqual(app.sources.drums.loopEnd, 8 / 3);
  assert.equal(app.sources.drums.starts.length, 1);
  assert.equal(app.sources.drums.starts.at(-1).offset, 2.26);
});

test('short loops snap to the next beat subdivision instead of the next bar', () => {
  const { app } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.state.bpm = 90;
  app.startPlayback(0);
  audioCtx.currentTime = 3.5;

  app.setLoop('drums', 0);

  assertAlmostEqual(app.state.loopStart.drums, 10 / 3);
  assertAlmostEqual(app.state.loopEnd.drums, 4);
  assert.equal(app.sources.drums.starts.at(-1).offset, 3.5);
});

test('changing a loop while playing only replaces the selected stem source', () => {
  const { app } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.state.bpm = 120;
  app.startPlayback(0);
  const original = Object.fromEntries(STEMS.map((stem) => [stem, app.sources[stem]]));
  const originalStartTime = app.state.startTime;
  audioCtx.currentTime = 3.1;

  app.setLoop('vocals', 1);

  assert.notEqual(app.sources.vocals, original.vocals);
  assert.equal(original.vocals.stopped, true);
  assert.equal(app.sources.vocals.loop, true);
  assert.equal(app.sources.vocals.loopStart, 3);
  assert.equal(app.sources.vocals.loopEnd, 4);
  assert.equal(app.sources.vocals.starts.length, 1);
  assert.equal(app.sources.vocals.starts.at(-1).offset, 3.1);
  assert.equal(app.sources.drums, original.drums);
  assert.equal(app.sources.bass, original.bass);
  assert.equal(app.sources.melody, original.melody);
  assert.equal(original.drums.stopped, false);
  assert.equal(original.bass.stopped, false);
  assert.equal(original.melody.stopped, false);
  assert.equal(app.state.startTime, originalStartTime);
});

test('disabling a loop while playing replaces that stem to rejoin linear playback', () => {
  const { app } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.state.bpm = 120;
  app.startPlayback(0);
  const original = Object.fromEntries(STEMS.map((stem) => [stem, app.sources[stem]]));

  audioCtx.currentTime = 2.2;
  app.setLoop('bass', 2);
  const loopedSource = app.sources.bass;
  audioCtx.currentTime = 6.4;
  app.setLoop('bass', -1);

  assert.notEqual(loopedSource, original.bass);
  assert.notEqual(app.sources.bass, loopedSource);
  assert.equal(loopedSource.stopped, true);
  assert.equal(app.sources.bass.loop, false);
  assert.equal(app.sources.bass.starts.length, 1);
  assert.equal(app.sources.bass.starts.at(-1).offset, 6.4);
  assert.equal(app.sources.drums, original.drums);
  assert.equal(app.sources.vocals, original.vocals);
  assert.equal(app.sources.melody, original.melody);
  assert.equal(original.drums.stopped, false);
  assert.equal(original.vocals.stopped, false);
  assert.equal(original.melody.stopped, false);
});

test('looped stem audible time wraps independently of transport time', () => {
  const { app } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.state.duration = 180;

  assert.equal(typeof app.audibleStemTime, 'function');
  app.state.loopDot.vocals = 0;
  app.state.loopStart.vocals = 60;
  app.state.loopEnd.vocals = 61;

  assertAlmostEqual(app.audibleStemTime('vocals', 59.5), 59.5);
  assertAlmostEqual(app.audibleStemTime('vocals', 60.25), 60.25);
  assertAlmostEqual(app.audibleStemTime('vocals', 116.4), 60.4);
  assertAlmostEqual(app.audibleStemTime('drums', 116.4), 116.4);
});

test('spectral window bounds earliest audible loop and current transport with padding', () => {
  const { app } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.state.duration = 180;
  app.state.loopDot.vocals = 0;
  app.state.loopStart.vocals = 60;
  app.state.loopEnd.vocals = 61;

  assert.equal(typeof app.spectralWindowFor, 'function');
  const window = app.spectralWindowFor(116);

  assertAlmostEqual(window.start, 58);
  assertAlmostEqual(window.end, 120);
  assert.equal(window.mode, 'expanded');
});

test('spectral window follows transport in a partial rolling view with cursor to the right', () => {
  const { app } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.state.duration = 180;

  const window = app.spectralWindowFor(90);
  const cursorRatio = (90 - window.start) / (window.end - window.start);

  assert.equal(window.end - window.start, 16);
  assert.ok(cursorRatio > 0.65, `expected cursor to sit right of center, got ${cursorRatio}`);
  assert.ok(window.start > 0);
  assert.ok(window.end < app.state.duration);
});

test('spectral click mapping seeks within the visible window', () => {
  const { app } = loadApp();

  assert.equal(typeof app.spectralTimeFromClientX, 'function');
  assertAlmostEqual(
    app.spectralTimeFromClientX(50, { left: 10, width: 80 }, { start: 58, end: 120 }),
    89,
  );
  assertAlmostEqual(
    app.spectralTimeFromClientX(-20, { left: 10, width: 80 }, { start: 58, end: 120 }),
    58,
  );
  assertAlmostEqual(
    app.spectralTimeFromClientX(200, { left: 10, width: 80 }, { start: 58, end: 120 }),
    120,
  );
});

test('spectral grid markers expose quarter, half, and measure positions', () => {
  const { app } = loadApp();
  app.state.duration = 30;
  app.state.bpm = 120;
  app.state.measureOffset = 0;

  assert.equal(typeof app.spectralGridMarkers, 'function');
  const markers = app.spectralGridMarkers({ start: 0, end: 2 });
  const labels = Array.from(markers, (marker) => marker.label);

  assert.deepEqual(labels.slice(0, 5), ['1', '1/4', '1/2', '1/4', '1']);
  assert.deepEqual(Array.from(markers.slice(0, 5), (marker) => marker.time), [0, 0.5, 1, 1.5, 2]);
});

test('level meter bands are derived from active stem buffers and volume', () => {
  const { app } = loadApp();
  app.state.ready = true;
  app.state.duration = 1;
  app.state.volume.bass = 0.5;
  app.state.volume.melody = 1;
  app.buffers.bass = {
    duration: 1,
    getChannelData() {
      return Float32Array.from([0, 1, 1, 1, 0, 0, 0, 0]);
    },
  };
  app.buffers.melody = {
    duration: 1,
    getChannelData() {
      return Float32Array.from([0, 0, 0, 0, 1, 1, 1, 1]);
    },
  };

  assert.equal(typeof app.levelMeterBandsAt, 'function');
  const early = app.levelMeterBandsAt(0.25);
  const late = app.levelMeterBandsAt(0.75);

  assert.ok(early.bass > early.treble, `expected early bass dominance, got ${JSON.stringify(early)}`);
  assert.ok(late.treble > late.bass, `expected late treble dominance, got ${JSON.stringify(late)}`);
});

test('level meter uses a live Web Audio analyser during playback', () => {
  const { app } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);

  app.startPlayback(0);

  assert.equal(audioCtx.createdAnalysers.length, 1);
  const analyser = audioCtx.createdAnalysers[0];
  assert.equal(analyser.connectedTo, audioCtx.destination);
  audioCtx.createdGains.forEach((gain) => {
    assert.equal(gain.connectedTo, analyser);
  });

  const timeData = new Uint8Array(analyser.fftSize).fill(128);
  for (let i = 0; i < timeData.length; i += 2) timeData[i] = 232;
  const frequencyData = new Uint8Array(analyser.frequencyBinCount);
  frequencyData.fill(212, 0, 14);
  frequencyData.fill(36, 64);
  analyser.timeData = timeData;
  analyser.frequencyData = frequencyData;

  const bands = app.levelMeterBandsAt(0.25);

  assert.ok(bands.wave > 0.2, `expected waveform energy from analyser, got ${JSON.stringify(bands)}`);
  assert.ok(bands.bass > bands.treble, `expected analyser bass dominance, got ${JSON.stringify(bands)}`);
});

test('level meter waveform geometry stays compact and continuous', () => {
  const { app } = loadApp();
  const waveform = new Uint8Array(128);
  for (let i = 0; i < waveform.length; i++) {
    waveform[i] = Math.round(128 + Math.sin((i / waveform.length) * Math.PI * 4) * 96);
  }

  assert.equal(typeof app.meterWavePoints, 'function');
  const wave = app.meterWavePoints({ bass: 1, treble: 1, wave: 1, waveform }, 480, 64);
  const maxOuter = Math.max(...wave.outer.map((point) => point.r));
  const minOuter = Math.min(...wave.outer.map((point) => point.r));
  const maxInner = Math.max(...wave.inner.map((point) => point.r));

  assert.equal(wave.outer.length, 65);
  assert.equal(wave.inner.length, 65);
  assert.equal(wave.mid.length, 65);
  assert.deepEqual(wave.outer.at(-1), wave.outer[0]);
  assert.deepEqual(wave.inner.at(-1), wave.inner[0]);
  assert.deepEqual(wave.mid.at(-1), wave.mid[0]);
  assert.ok(maxOuter - wave.base <= 62, `expected compact wave displacement, got ${maxOuter - wave.base}`);
  assert.ok(maxOuter - minOuter > 8, 'expected visible waveform variation around the ring');
  assert.ok(maxInner < minOuter, 'expected a filled ring band with inner and outer contours');
});

test('rejecting a loop that extends past the track clears stale loop state', () => {
  const { app, document, context } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.state.bpm = 120;
  app.startPlayback(0);

  audioCtx.currentTime = 2.26;
  app.setLoop('melody', 0);
  const loopedSource = app.sources.melody;
  assert.equal(loopedSource.loop, true);

  app.state.measureOffset = 1;
  audioCtx.currentTime = 29.2;
  app.setLoop('melody', 3);

  assert.equal(context.__alerts.length, 1);
  assert.equal(app.state.loopDot.melody, -1);
  assert.equal(app.state.loopStart.melody, 0);
  assert.equal(app.state.loopEnd.melody, 0);
  assert.equal(document.getElementById('varc-melody').classList.contains('looping'), false);
  assert.deepEqual(document.loopButtons.melody.map((button) => button.classList.contains('on')), [false, false, false, false]);
  assert.notEqual(app.sources.melody, loopedSource);
  assert.equal(loopedSource.stopped, true);
  assert.equal(app.sources.melody.loop, false);
  assert.equal(app.sources.melody.starts.length, 1);
  assert.equal(app.sources.melody.starts.at(-1).offset, 29.2);
});

test('loop reset clears loop state and UI for every stem', () => {
  const { app, document } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.state.bpm = 120;
  app.state.pauseOffset = 2.26;

  assert.equal(typeof app.clearAllLoops, 'function');
  STEMS.forEach((stem, idx) => app.setLoop(stem, idx % app.LOOP_BARS.length));
  app.clearAllLoops();

  for (const stem of STEMS) {
    assert.equal(app.state.loopDot[stem], -1);
    assert.equal(app.state.loopStart[stem], 0);
    assert.equal(app.state.loopEnd[stem], 0);
    assert.equal(document.getElementById(`varc-${stem}`).classList.contains('looping'), false);
    assert.deepEqual(document.loopButtons[stem].map((button) => button.classList.contains('on')), [false, false, false, false]);
  }
});

test('all loop row applies one quantized loop across every stem', () => {
  const { app, document } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.state.bpm = 120;
  app.startPlayback(0);
  const original = Object.fromEntries(STEMS.map((stem) => [stem, app.sources[stem]]));
  audioCtx.currentTime = 3.1;

  app.setLoop('all', 1);

  assert.equal(app.state.loopDot.all, 1);
  assert.deepEqual(document.loopButtons.all.map((button) => button.classList.contains('on')), [false, true, false, false]);
  for (const stem of STEMS) {
    assert.equal(app.state.loopDot[stem], 1);
    assert.equal(app.state.loopStart[stem], 3);
    assert.equal(app.state.loopEnd[stem], 4);
    assert.notEqual(app.sources[stem], original[stem]);
    assert.equal(original[stem].stopped, true);
    assert.equal(app.sources[stem].loop, true);
    assert.equal(app.sources[stem].loopStart, 3);
    assert.equal(app.sources[stem].loopEnd, 4);
  }
});

test('solo loop monitor uses headphones without mutating mute state', () => {
  const { app } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.startPlayback(0);
  app.setMute('drums', true);

  assert.equal(typeof app.setLoopAuditionMode, 'function');
  app.setLoopAuditionMode('solo');
  app.setLoop('bass', 0);

  assert.equal(app.state.headphonesStem, 'bass');
  assert.equal(app.state.muted.drums, true);
  assert.equal(app.state.muted.vocals, false);
  assert.equal(app.gains.bass.gain.value, 0.8);
  assert.equal(app.gains.drums.gain.value, 0);
  assert.equal(app.gains.vocals.gain.value, 0);
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

test('mute all toggle switches between mute and unmute states', () => {
  const { app, document } = loadApp();
  const audioCtx = new FakeAudioContext();
  preparePlayback(app, audioCtx);
  app.startPlayback(0);
  app.setVolume('bass', 0.25);
  app.setHeadphones('vocals', true);
  const button = document.getElementById('btnMuteAll');

  assert.equal(typeof app.setAllMuted, 'function');
  assert.equal(typeof app.toggleAllMuted, 'function');
  assert.equal(typeof app.areAllMuted, 'function');
  assert.equal(button.disabled, false);
  assert.equal(button.textContent, 'mute all');
  assert.equal(button.getAttribute('aria-label'), 'Mute all stems');

  app.toggleAllMuted();
  assert.equal(app.areAllMuted(), true);
  assert.equal(app.state.volume.bass, 0.25);
  assert.equal(app.state.headphonesStem, null);
  assert.equal(button.disabled, false);
  assert.equal(button.textContent, 'unmute all');
  assert.equal(button.getAttribute('aria-label'), 'Unmute all stems');
  assert.equal(button.getAttribute('aria-pressed'), 'true');
  for (const stem of STEMS) assert.equal(app.state.muted[stem], true);

  app.toggleAllMuted();
  assert.equal(app.areAllMuted(), false);
  assert.equal(button.disabled, false);
  assert.equal(button.textContent, 'mute all');
  assert.equal(button.getAttribute('aria-label'), 'Mute all stems');
  assert.equal(button.getAttribute('aria-pressed'), 'false');
  for (const stem of STEMS) assert.equal(app.state.muted[stem], false);
});

test('sample rows hide while processing or when audio is ready', () => {
  const { app, document } = loadApp();

  assert.equal(typeof app.updateSampleRowsVisibility, 'function');
  app.state.ready = false;
  app.state.processing = false;
  app.updateSampleRowsVisibility();
  assert.equal(document.getElementById('sampleRows').classList.contains('hidden'), false);

  app.state.processing = true;
  app.updateSampleRowsVisibility();
  assert.equal(document.getElementById('sampleRows').classList.contains('hidden'), true);

  app.state.processing = false;
  app.state.ready = true;
  app.updateSampleRowsVisibility();
  assert.equal(document.getElementById('sampleRows').classList.contains('hidden'), true);
});

test('reset all tracks clears mutes, headphones, and restores default volume', () => {
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
