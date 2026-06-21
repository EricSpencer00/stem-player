# Stemacle Desktop Workbench Design

Status: superseded as the desktop product direction. Keep this document only as historical context for compatibility web workbench behavior. Current desktop work is SwiftUI parity-plus: match the perfect web app at `https://stemacle.com/app/` first, recognize that `https://ericspencer.us/stem-player` points to it, then add native desktop capabilities above and beyond.

## Goal

Historical goal: turn the Electron desktop app from a static wrapper into a real local workbench that owns library indexing, cache manifests, native analysis/download/export jobs, model/tool detection, and handoff into the Stem Splitter surface.

Current goal: use SwiftUI for the desktop app. Any Electron/web workbench code should be treated as compatibility infrastructure and should not override the SwiftUI desktop direction.

## Approaches Considered

### 1. Recommended: native desktop service with a thin renderer

Keep the browser instruments at `/app/` and `/apps/stem-shuffle/`, but move desktop-only responsibilities into a persistent Electron-side store and job runner. The renderer becomes a control room for library state, queue state, downloads, exports, cache roots, and launch actions.

Why this wins:

- matches `docs/STEMACLE_SURFACES.md`
- keeps the web routes stable
- adds real native behavior without re-architecting the browser splitter
- lets Demucs, ffmpeg, ffprobe, and yt-dlp remain optional local capabilities

### 2. Make the renderer do everything with localStorage and ad hoc IPC

This is close to the current state. It is fast to patch, but it keeps desktop responsibilities spread across inline UI code and one large persistence file. Queue execution, downloads, and exports become fragile quickly.

Why not:

- repeats logic between renderer preview mode and native mode
- hard to test background work
- encourages a fake queue instead of a real worker

### 3. Build a separate local backend daemon now

Run a dedicated Node or Python service for all desktop jobs and keep Electron as a client shell.

Why not:

- too much extra surface for this pass
- adds packaging and lifecycle complexity before the product needs it
- delays user-visible improvements

## Chosen Direction

Historical choice: implement approach 1, a native desktop service with a thin renderer.

Current choice: SwiftUI owns desktop product shape. The service ideas below may still inform native capabilities, but the visible desktop app must preserve web-app parity before adding them.

## Desktop Responsibilities

The desktop app will own:

- recursive file and folder indexing
- persistent library roots and recent items
- metadata extraction from local files
- stable cache paths per track
- model and tool capability detection
- background analysis, download, and export jobs
- saved session records
- reveal-in-Finder actions
- native opening of library tracks inside the Stem Splitter route

The browser routes remain responsible for:

- waveform and transport UI
- ONNX/browser DSP preview separation
- Stem Shuffle deck behavior

## Architecture

### Native service

Create a richer desktop store in `native/electron/stemacle-desktop.cjs`, supported by focused helper modules:

- `desktop-tools.cjs`
  - executable detection
  - ffprobe metadata extraction
  - demucs / yt-dlp / ffmpeg process launching
- `desktop-jobs.cjs`
  - queue runner
  - progress/state transitions
  - cancellation-safe process cleanup

The store persists one JSON state file under the Electron user-data root and emits state-change events to the renderer after every meaningful mutation.

### Renderer

Keep `native/index.html` as the desktop workbench shell, but upgrade it to:

- subscribe to native state updates
- render real tool/model availability
- add URL download intake
- show library roots, track metadata, queue progress, exports, sessions, and cache paths
- launch a selected track directly into `/app/`

### Splitter handoff

Expose a native API that returns file bytes for a library track. The desktop shell stores a pending track id before navigating to `/app/`. The splitter route checks for that pending id, reads the file from the native bridge, and loads it as though the user had picked a local file manually.

## Data Model

### Track record

Each library track should persist:

- `id`
- `name`
- `path`
- `sourceKind`
- `size`
- `lastModified`
- `addedAt`
- `updatedAt`
- `analysisStatus`
- `duration`
- `bpm`
- `key`
- `sampleRate`
- `channels`
- `stemAvailability`
- `cache`
- `download`
- `errors`

### Library roots

Persist indexed folder roots so the user can rescan later without re-choosing folders.

### Job record

Queue jobs should support:

- `analysis`
- `download`
- `export`

Each job persists:

- `id`
- `kind`
- `status`
- `progress`
- `message`
- `createdAt`
- `startedAt`
- `finishedAt`
- `trackId` or `url`
- `quality` or `format`
- `outputPath`
- `error`

### Tool and model state

Persist live capability snapshots for:

- `ffmpeg`
- `ffprobe`
- `demucs`
- `yt-dlp`

Model rows derive from that capability state, including:

- fast preview
- Demucs `htdemucs_ft`
- Demucs `htdemucs_6s`
- optional Demucs `mdx_extra_q`

## Job Behavior

### Analysis jobs

- `fast-preview`
  - extract metadata
  - write analysis cache JSON
  - mark preview cache ready
- `demucs-*`
  - require `demucs`
  - write stems into the stable per-track cache directory
  - refresh `stemAvailability`
  - write analysis manifest with generated files

### Download jobs

- require `yt-dlp`
- download audio into a stable downloads directory
- index the resulting file automatically into the library

### Export jobs

- prefer cached stems when available
- copy or transcode stems into a per-track export directory
- use `ffmpeg` when format conversion is needed
- fail with a clear message when cached stems do not exist yet

## Error Handling

- Missing native tools should never break the app shell.
- Queue jobs should fail per job, not corrupt the library.
- State writes stay atomic enough for this pass by rewriting the JSON file after mutations.
- Renderer actions should show the latest native error text instead of silently doing nothing.

## Testing

Add backend-first tests that verify:

- recursive indexing stores metadata and roots
- tool detection and model availability are reflected in state
- analysis jobs advance from queued to completed or failed
- download and export jobs use injected/fake executables in tests
- native bridge exposes the new APIs
- desktop shell HTML renders the new controls and status panels
- `/app/` can consume a pending native desktop track

## Success Criteria

This pass succeeds when:

- the desktop app persists a real library and roots
- queue rows correspond to actual native jobs
- tool/model availability is real, not placeholder text
- downloads and exports are first-class desktop actions
- opening a library track in Stem Splitter works inside Electron
- the desktop app still degrades cleanly when Demucs or yt-dlp are not installed
