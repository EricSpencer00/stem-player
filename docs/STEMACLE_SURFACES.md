# Stemacle Product Surfaces

Stemacle has one identity and three product surfaces. The circle, warm matte interface, stem controls, loop contract, and local-first privacy model stay consistent. The differences are about what each platform can own responsibly.

## Web App

The web app is the instant surface at `/app/`. It preserves the same tactile splitter: four stems, mute and headphones isolation, volume, spectrogram lanes, loop buttons, all-stem loop row, tempo-grid snapping, file-load reset behavior, sample tracks, and browser-only processing. It uses ONNX Runtime Web with browser DSP fallback and model download timeout recovery. It does not claim ownership over folders, OS-level background work, Finder integration, or persistent desktop cache directories.

Best for:

- trying Stemacle immediately from `https://stemacle.com/app/`
- splitting one local file without installing anything
- using the current browser model and fallback path
- sharing the exact same visual and interaction contract as the native apps

## Desktop App

The desktop app is the local workbench. It wraps the existing Stem Splitter and Stem Shuffle instruments, then adds native responsibilities that a browser should not pretend to handle: file and folder intake, persistent library records, recent projects, OS dialogs, background queue records, reveal-in-Finder actions, saved sessions, export plans, and explicit cache roots.

Desktop adds:

- persistent music library with file path, size, modification time, analysis status, and cache paths
- persistent indexed folder roots and rescans
- direct handoff from the library into the Stem Splitter route without reopening a file manually
- offline model cache manifest for fast preview, Demucs high quality four-stem, and optional Demucs six-stem
- optional Demucs `mdx_extra_q` model row for alternate four-stem work
- stable per-track stem cache and analysis cache paths so playback and shuffle do not reprocess the same track every time
- background analysis queue records with selectable separation quality
- desktop download queue for URL-based intake when `yt-dlp` is installed
- export queue for stem packs and future mixdown-oriented desktop exports
- ffprobe and ffmpeg capability detection for metadata and conversion work
- command palette, menu commands, keyboard shortcuts, OS file and folder dialogs, and desktop notifications
- Stem Shuffle as a first-class route for compatibility-aware pair picking, deck rate matching, crossfader, lead A/B, blend, flip, queue, and history

The high-quality model path is local Demucs. Fast preview stays available without extra setup. When Demucs is installed on the machine, the desktop cache is ready for `htdemucs_ft` four-stem jobs, the optional `htdemucs_6s` six-stem path, and the optional `mdx_extra_q` alternate four-stem path. When Demucs is not installed, the app still keeps the library, metadata cache, queue records, sessions, downloads, and exports usable.

## iOS App

The iOS app uses the Capacitor bundle. It keeps the same native shell and tactile splitter identity, then narrows the responsibilities to what makes sense on mobile: touch-first file intake, local app storage, the same web splitter, Stem Shuffle access, and a smaller version of the library surface. It does not expose the full desktop worker pipeline, Finder reveal actions, or unrestricted folder scanning.

iOS keeps:

- same tactile Stem Splitter experience
- same Stem Shuffle route
- same visual identity and restrained Stemacle surface
- local-first session and library concepts
- app-packaged static assets for offline launch after install

iOS differs:

- no desktop Demucs worker pipeline
- no OS folder recursion
- no reveal in Finder
- export behavior depends on iOS share sheet and sandbox rules

## Release Contract

Every release should verify all three surfaces:

- web bundle: `npm run site:prepare`
- desktop bundle: `npm run native:prepare` and `npm run desktop:pack`
- iOS bundle: `npm run ios:sync`
- regression suite: `npm test`

Stemacle.com points at the Cloudflare Pages output in `dist/site`. Desktop and iOS builds come from the same repo and preserve the current web app at `/app/`.
