# Stem Shuffle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a separate dual-deck stem mixer app that reuses the existing browser stem-separation work, supports a local/sample playlist now, and leaves a clean source adapter seam for future YouTube ingestion.

**Architecture:** Add a new standalone app under `apps/stem-shuffle/` with plain browser modules for library state, audio analysis/playback, and UI orchestration. Keep the original root app untouched and cover the new logic with a dedicated VM-based test file.

**Tech Stack:** Static HTML, CSS, JavaScript modules, Web Audio API, ONNX Runtime Web, Node `node:test`

## Global Constraints

- Keep the new app separate from `/Users/eric/GitHub/stem-player/index.html`.
- Reuse ideas from the existing stem separation pipeline without destabilizing the first app.
- Ship local file import and bundled sample playback now.
- Parse YouTube playlist URLs now, but leave direct YouTube audio ingestion behind a pending adapter state.
- Cover compatibility scoring, shuffle, and source parsing with automated tests.

---

### Task 1: Define the second app shell and test harness

**Files:**
- Create: `apps/stem-shuffle/index.html`
- Create: `apps/stem-shuffle/styles.css`
- Test: `tests/stem-shuffle.test.mjs`

**Interfaces:**
- Consumes: none
- Produces:
  - `index.html` app shell loading `./app.js`
  - DOM ids for library, pair stage, transport, and source inputs

- [ ] **Step 1: Write the failing test**

```js
test('stem shuffle app exists as a separate standalone entrypoint', () => {
  const html = readFileSync(new URL('../apps/stem-shuffle/index.html', import.meta.url), 'utf8');
  assert.match(html, /<title>Stem Shuffle<\/title>/);
  assert.match(html, /<script type="module" src="\.\/app\.js"><\/script>/);
  assert.match(html, /id="libraryList"/);
  assert.match(html, /id="crossfader"/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test tests/stem-shuffle.test.mjs`
Expected: FAIL because `apps/stem-shuffle/index.html` does not exist yet

- [ ] **Step 3: Write minimal implementation**

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Stem Shuffle</title>
  <link rel="stylesheet" href="./styles.css">
</head>
<body>
  <main id="app">
    <section id="libraryList"></section>
    <input id="crossfader" type="range" min="0" max="100" value="50">
  </main>
  <script type="module" src="./app.js"></script>
</body>
</html>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test tests/stem-shuffle.test.mjs`
Expected: PASS for the new entrypoint structure assertion

- [ ] **Step 5: Commit**

```bash
git add apps/stem-shuffle/index.html apps/stem-shuffle/styles.css tests/stem-shuffle.test.mjs
git commit -m "feat: add stem shuffle app shell"
```

### Task 2: Add library state, source parsing, and compatibility scoring

**Files:**
- Create: `apps/stem-shuffle/library.js`
- Modify: `apps/stem-shuffle/app.js`
- Test: `tests/stem-shuffle.test.mjs`

**Interfaces:**
- Consumes:
  - `createInitialLibraryState(): LibraryState`
- Produces:
  - `parseYouTubePlaylistUrl(url: string): { playlistId: string | null, canonicalUrl: string | null }`
  - `scoreCompatibility(a: TrackAnalysis, b: TrackAnalysis): number`
  - `pickCompatiblePair(tracks: TrackAnalysis[]): { left: TrackAnalysis, right: TrackAnalysis } | null`

- [ ] **Step 1: Write the failing test**

```js
test('compatibility scoring prefers tracks with closer tempo and key', async () => {
  const mod = await importModule('../apps/stem-shuffle/library.js');
  const near = mod.scoreCompatibility(
    { tempo: 120, keyClass: 0, analysisStatus: 'ready' },
    { tempo: 122, keyClass: 1, analysisStatus: 'ready' },
  );
  const far = mod.scoreCompatibility(
    { tempo: 120, keyClass: 0, analysisStatus: 'ready' },
    { tempo: 90, keyClass: 8, analysisStatus: 'ready' },
  );
  assert.ok(near > far);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test tests/stem-shuffle.test.mjs`
Expected: FAIL because `library.js` and scoring exports do not exist

- [ ] **Step 3: Write minimal implementation**

```js
export function parseYouTubePlaylistUrl(value) {
  const url = new URL(value);
  const playlistId = url.searchParams.get('list');
  return playlistId ? {
    playlistId,
    canonicalUrl: `https://www.youtube.com/playlist?list=${playlistId}`,
  } : { playlistId: null, canonicalUrl: null };
}

export function scoreCompatibility(a, b) {
  if (a.analysisStatus !== 'ready' || b.analysisStatus !== 'ready') return -Infinity;
  const tempoPenalty = Math.abs((a.tempo || 0) - (b.tempo || 0));
  const keyDelta = Math.abs((a.keyClass || 0) - (b.keyClass || 0));
  const wrappedKeyDelta = Math.min(keyDelta, 12 - keyDelta);
  return 100 - (tempoPenalty * 2) - (wrappedKeyDelta * 8);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test tests/stem-shuffle.test.mjs`
Expected: PASS for compatibility and playlist URL parsing tests

- [ ] **Step 5: Commit**

```bash
git add apps/stem-shuffle/library.js apps/stem-shuffle/app.js tests/stem-shuffle.test.mjs
git commit -m "feat: add playlist parsing and compatibility scoring"
```

### Task 3: Port the track analysis pipeline for the new app

**Files:**
- Create: `apps/stem-shuffle/audio-core.js`
- Modify: `apps/stem-shuffle/app.js`
- Test: `tests/stem-shuffle.test.mjs`

**Interfaces:**
- Consumes:
  - `File | SampleTrack`
- Produces:
  - `analyzeTrack(source: TrackSource, onProgress?: ProgressFn): Promise<TrackAnalysis>`
  - `estimateTempo(signal: Float32Array, sampleRate: number): TempoAnalysis`
  - `estimateKeyClass(signal: Float32Array, sampleRate: number): number`

- [ ] **Step 1: Write the failing test**

```js
test('youtube playlist imports are marked pending while local/sample sources are analyzable', async () => {
  const mod = await importModule('../apps/stem-shuffle/library.js');
  const adapter = mod.createPendingYouTubeAdapter('https://www.youtube.com/playlist?list=PL123');
  assert.equal(adapter.status, 'pending');
  assert.equal(adapter.kind, 'youtube');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test tests/stem-shuffle.test.mjs`
Expected: FAIL because the adapter creation helper does not exist

- [ ] **Step 3: Write minimal implementation**

```js
export async function analyzeTrack(source, onProgress) {
  const analysis = await separateAndMeasure(source, onProgress);
  return {
    ...source,
    analysisStatus: 'ready',
    stemBuffers: analysis.stemBuffers,
    tempo: analysis.tempo,
    keyClass: analysis.keyClass,
    duration: analysis.duration,
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test tests/stem-shuffle.test.mjs`
Expected: PASS for pending adapter state and analysis-oriented interfaces

- [ ] **Step 5: Commit**

```bash
git add apps/stem-shuffle/audio-core.js apps/stem-shuffle/app.js apps/stem-shuffle/library.js tests/stem-shuffle.test.mjs
git commit -m "feat: port analysis pipeline for stem shuffle"
```

### Task 4: Add synchronized dual-deck playback and transition controls

**Files:**
- Modify: `apps/stem-shuffle/audio-core.js`
- Modify: `apps/stem-shuffle/app.js`
- Modify: `apps/stem-shuffle/index.html`
- Modify: `apps/stem-shuffle/styles.css`
- Test: `tests/stem-shuffle.test.mjs`

**Interfaces:**
- Consumes:
  - `TrackAnalysis`
  - `pickCompatiblePair(...)`
- Produces:
  - `createDeckEngine(): DeckEngine`
  - `computeDeckMixGains(crossfade: number, emphasis: 'left' | 'right' | 'blend'): { left: number, right: number }`
  - `loadPair(pair): Promise<void>`
  - `playPair(): Promise<void>`

- [ ] **Step 1: Write the failing test**

```js
test('crossfade math leans left at 0, center at 0.5, and right at 1', async () => {
  const mod = await importModule('../apps/stem-shuffle/audio-core.js');
  assert.deepEqual(mod.computeDeckMixGains(0), { left: 1, right: 0 });
  assert.deepEqual(mod.computeDeckMixGains(0.5), { left: 0.5, right: 0.5 });
  assert.deepEqual(mod.computeDeckMixGains(1), { left: 0, right: 1 });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test tests/stem-shuffle.test.mjs`
Expected: FAIL because the deck gain math does not exist

- [ ] **Step 3: Write minimal implementation**

```js
export function computeDeckMixGains(value) {
  const crossfade = Math.max(0, Math.min(1, value));
  return {
    left: 1 - crossfade,
    right: crossfade,
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test tests/stem-shuffle.test.mjs`
Expected: PASS for crossfade math and pair playback surface

- [ ] **Step 5: Commit**

```bash
git add apps/stem-shuffle/audio-core.js apps/stem-shuffle/app.js apps/stem-shuffle/index.html apps/stem-shuffle/styles.css tests/stem-shuffle.test.mjs
git commit -m "feat: add dual deck playback controls"
```

### Task 5: Wire shuffle, sample/local imports, and deferred YouTube messaging

**Files:**
- Modify: `apps/stem-shuffle/app.js`
- Modify: `apps/stem-shuffle/index.html`
- Modify: `apps/stem-shuffle/styles.css`
- Test: `tests/stem-shuffle.test.mjs`

**Interfaces:**
- Consumes:
  - `parseYouTubePlaylistUrl`
  - `pickCompatiblePair`
  - `createDeckEngine`
- Produces:
  - Library UI actions for sample load, local file load, playlist URL capture, and shuffle

- [ ] **Step 1: Write the failing test**

```js
test('youtube playlist parsing captures the playlist id and marks the source pending', async () => {
  const mod = await importModule('../apps/stem-shuffle/library.js');
  const parsed = mod.parseYouTubePlaylistUrl('https://www.youtube.com/playlist?list=PLabc123');
  assert.equal(parsed.playlistId, 'PLabc123');
  const pending = mod.createPendingYouTubeAdapter(parsed.canonicalUrl);
  assert.equal(pending.status, 'pending');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test tests/stem-shuffle.test.mjs`
Expected: FAIL because the pending source helper or UI wiring does not exist yet

- [ ] **Step 3: Write minimal implementation**

```js
function importYouTubePlaylist(url) {
  const parsed = parseYouTubePlaylistUrl(url);
  if (!parsed.playlistId) return { ok: false };
  addSourceAdapter(createPendingYouTubeAdapter(parsed.canonicalUrl));
  renderStatus('YouTube playlist captured. Resolver not configured in-browser yet.');
  return { ok: true };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test tests/stem-shuffle.test.mjs`
Expected: PASS for pending YouTube source behavior and library wiring

- [ ] **Step 5: Commit**

```bash
git add apps/stem-shuffle/app.js apps/stem-shuffle/index.html apps/stem-shuffle/styles.css tests/stem-shuffle.test.mjs
git commit -m "feat: wire shuffle flow and deferred youtube adapter"
```
