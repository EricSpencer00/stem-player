# Stem Shuffle Design

## Goal

Build a second app in this repo for two synchronized songs, each split into vocals, melody, bass, and drums, with compatibility-aware pairing, easy flip/blend transitions, and playlist-style shuffling. Keep it separate from the existing single-track Stemacle surface.

## Context

The current repo already contains a browser-only stem separation pipeline in [`/Users/eric/GitHub/stem-player/index.html`](/Users/eric/GitHub/stem-player/index.html), including:

- ONNX Runtime Web model loading with browser DSP fallback
- tempo and downbeat estimation
- per-stem gain control and Web Audio playback
- tests that execute inline app logic in a VM

The fastest safe path is to create a second standalone app that reuses those ideas without destabilizing the first app.

## Approaches Considered

### 1. Recommended: separate static app with a source adapter seam

Create a new app under `apps/stem-shuffle/` with its own HTML, CSS, and JavaScript. Reuse the stem separation and transport concepts from the existing app, but reshape them around:

- a track pool instead of one loaded file
- two synchronized decks
- compatibility scoring for shuffle
- a crossfader / flip transport model
- a source adapter interface for future YouTube ingestion

Trade-offs:

- Fastest path to a working second product
- Keeps the current app stable
- Honest about YouTube: the interface is ready now, but direct YouTube ingestion remains a follow-up integration problem

### 2. Retrofit the existing root app into two modes

Add a “single-track” mode and a “shuffle mixer” mode into the current `index.html`.

Trade-offs:

- Shares code immediately
- Highest risk of breaking the current app
- Harder to test and reason about because the root file is already large

### 3. Build a full multi-page app with a backend requirement now

Design around direct YouTube ingestion immediately, assuming a local or remote worker that resolves playlist items and audio streams.

Trade-offs:

- Best long-term source story
- Not honestly shippable right now in this repo without adding a service layer
- Delays the core mixing experience

## Recommended Architecture

Create a new app at `apps/stem-shuffle/index.html` with a small set of plain browser modules:

- `apps/stem-shuffle/index.html`
  - App shell and controls
- `apps/stem-shuffle/app.js`
  - bootstraps state, wires UI, owns event flow
- `apps/stem-shuffle/audio-core.js`
  - stem separation, tempo/key detection, synchronized playback, crossfade logic
- `apps/stem-shuffle/library.js`
  - playlist state, shuffle, compatibility scoring, source adapter contracts
- `apps/stem-shuffle/styles.css`
  - separate visual language from the original app

This second app remains fully static and browser-run. It does not mutate or replace the existing root app.

## Source Model

The new app should support three source states:

### Shipped now

- local file import
- bundled sample tracks from `/Users/eric/GitHub/stem-player/samples`

### Scaffolded now

- pasted YouTube playlist URL parsing
- playlist adapter object with `kind`, `label`, `status`, and `tracks`
- UI messaging that a remote resolver is not configured yet

### Deferred

- actual YouTube playlist expansion into track audio
- direct YouTube audio ingestion / signed fetch / worker-backed extraction

This keeps the architecture honest while still building the rest of the product now.

## Core User Flow

1. Open the separate app.
2. Load several tracks from samples or local files.
3. Optionally paste a YouTube playlist URL, which is captured as a pending adapter source.
4. Analyze tracks for tempo, rough key, and available stems.
5. Shuffle a compatible pair.
6. Start synchronized playback from a shared transport origin.
7. Flip toward deck A or deck B with a crossfader or quick lead buttons.
8. Adjust stem emphasis per deck during playback.
9. Shuffle again to pick a new compatible pair from the library.

## Audio Design

Each track becomes an analyzed library item with:

- `id`
- `name`
- `sourceKind`
- `audioFile` or sample URL
- `tempo`
- `keyClass`
- `duration`
- `analysisStatus`
- `stemBuffers`

Two analyzed items can become a pair if both have stem buffers and analysis metadata.

The playback engine should:

- start both decks on the same transport clock
- time-stretch logically through rate alignment metadata, even if immediate playback remains at native rate in v1
- expose a normalized crossfade value from `0` to `1`
- compute per-deck, per-stem gains from:
  - deck focus
  - quick lead mode
  - local stem mute/boost settings

For this first pass, “matched” means:

- pick tracks with near tempo agreement and compatible estimated key classes
- start both from aligned transport zero
- let the user flip or blend between them smoothly

This is deliberately simpler than a full production DJ transition planner.

## Compatibility Scoring

Compatibility score should combine:

- BPM distance
- key-class distance on a 12-step circle
- duration sanity
- successful stem analysis on both tracks

The shuffle algorithm should prefer the highest-scoring unused candidates, then fall back gracefully.

## UI Design

The new app should not look like the original physical-device clone.

It should feel like an intentional newer product:

- wide landscape layout
- centered dual-deck stage
- playlist/library rail
- clear pair card showing tempo and key match
- visible crossfader
- per-deck stem chips or sliders
- one-tap actions for `shuffle`, `lead A`, `lead B`, `flip`, and `blend`

## Error Handling

- Local track decode errors show inline row status
- failed analysis does not poison the whole library
- YouTube playlist URL import shows “captured but not resolvable in-browser yet”
- playback controls remain disabled until a valid pair exists

## Testing

Add a second test file for the new app that verifies:

- separate app files exist and are structurally isolated from the first app
- compatibility scoring prefers closer tempo/key pairs
- shuffle returns analyzable pairs
- YouTube playlist parsing captures playlist IDs and marks the adapter pending
- crossfade math produces expected deck weighting

## Non-Goals For This Pass

- direct YouTube audio extraction in-browser
- beat-perfect phase vocoding or time-stretching
- backend ingestion workers
- account/session persistence
- full Stem.FM queue/session/timeline cloning

## Success Criteria

This pass succeeds if the repo contains a clearly separate second app that:

- loads a track pool
- separates stems for loaded tracks
- shuffles and ranks compatible pairs
- plays two stem-separated decks together
- lets the user flip between songs smoothly
- includes a clean future seam for real YouTube ingestion
