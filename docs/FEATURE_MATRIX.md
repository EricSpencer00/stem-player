# Stemacle Native Feature Matrix

Status of every feature across the native surfaces, plus proposed features and
how we'd build them. This is a planning document, not a contract.

**Surfaces**
- **iOS** — SwiftUI app (`native/apple`, target `StemacleiOS`)
- **macOS** — SwiftUI app (shares the iOS codebase; target `StemacleMac`)
- **Win/Linux** — Slint app (`native/desktop`, Rust)

All three sit on the shared Rust core (`native/core/stemacle-dsp` via the
`stemacle-ffi` C ABI). The web app at `stemacle.com/app/` stays the gold master.

**Legend:** ✅ shipped · ◐ partial · ○ planned · — not applicable
**Effort:** S (<1d) · M (2–4d) · L (1–2wk) · XL (multi-week)

---

## Part 1 — Implemented features

| Feature | iOS | macOS | Win/Linux | How it's built |
|---|:--:|:--:|:--:|---|
| Import audio file | ✅ | ✅ | ◐ | iOS/macOS: `fileImporter` + AVFoundation decode (any format). Slint: `rfd` picker, **WAV only** (hand-rolled reader) — needs `symphonia` for mp3/flac (◐). |
| Bundled demo / "try a sample" | ✅ | ✅ | ○ | `Resources/demo.wav` + button. Slint has no bundled sample yet. |
| On-device separation (DSP) | ✅ | ✅ | ✅ | Shared Rust core: STFT → coherence vocal mask → HPSS → bass/melody low-pass. "Preview" quality. |
| High-quality separation (htdemucs) | ◐ | ✅ | ✅ | Desktop shells out to `models/separate.py` (`demucs.rs`). iOS uses the **server queue** (`server/app.py`) — only when a server URL is set (◐). |
| Background splitting + progress | ✅ | ✅ | ○ | Server reports time-based % → polled by `StemServerClient` → amber progress ring. Slint runs on a worker thread but shows no %. |
| Graceful fallback (server→DSP) | ✅ | ✅ | ✅ | If the server is unreachable, separate on-device instead of failing. |
| Four stems (drums/vocals/bass/melody) | ✅ | ✅ | ✅ | Canonical order in the core; htdemucs "other" → melody. |
| Transport: play/pause/stop/restart/seek | ✅ | ✅ | ◐ | `StemAudioEngine` (AVAudioEngine). Slint has play/pause/stop via cpal, **no scrub seek / restart** (◐). |
| Elapsed / total / BPM readout | ✅ | ✅ | ○ | From engine `currentTime` + core tempo. |
| Per-stem volume / mute / headphones-solo | ✅ | ✅ | ✅ | Per-stem player nodes; persistent-volume mixing. |
| Persistent global mute | ✅ | ✅ | ○ | Doesn't reset per-stem volumes. |
| Functional loops (¼ ½ 1 2, per stem) | ✅ | ✅ | ○ | AVAudioPlayerNode `.loops` over a snapped `[start,end)` window. |
| All-row linked loop | ✅ | ✅ | ○ | One window applied to every stem. |
| Mix / Solo loop monitoring | ✅ | ✅ | ○ | Solo cues only looped stems without mutating mute. |
| Tempo detect + 4/4 grid snapping | ✅ | ✅ | ◐ | Core `estimate_tempo`; loops snap via `LoopGrid`. Slint computes tempo but doesn't use it for loops. |
| Loop-past-end rejection | ✅ | ✅ | — | `LoopGrid.loop_fits`. |
| Per-stem spectrogram lanes + tap-seek | ✅ | ✅ | ○ | `viz::spectrogram` → `CGImage`; played tint, measure grid markers, moving playhead. |
| Master spectrogram in player | ✅ | ✅ | ○ | Mix spectrogram lane. |
| Spinning disc + radial spectrum | ✅ | ✅ | ○ | Warm matte disc + amber recessed-LED ring (on-brand). |
| Mobile collapsing header | ✅ | — | — | `ScrollOffsetKey` → `scaleEffect`. |
| Export stems to disk | ○ | ○ | ✅ | Slint writes 4 WAVs. **iOS/macOS share-sheet export not built yet** (○). |
| Settings (separation server URL) | ✅ | ✅ | — | `UserDefaults` `stemacle.serverURL`. Slint uses env vars. |

**Biggest current asymmetry:** the Slint (Win/Linux) app is ~1 generation behind
— no loops, spectrograms, visualizer, seek, or progress UI. Bringing it to parity
is its own work item (reuse the core; rebuild the views in Slint).

---

## Part 2 — Proposed features (your vision first)

### A. Song Library

A browsable local catalog of imported/split songs.

| Capability | iOS | macOS | Win/Linux | How we get it done | Effort |
|---|:--:|:--:|:--:|---|:--:|
| Local song catalog | ○ | ○ | ○ | Persist a `Project` record per song (title, artist, path, BPM, key, art, date). Store: **SwiftData/Core Data** on Apple; **SQLite via `rusqlite`** in a new `stemacle-store` crate for Slint (and optionally Apple via FFI for one source of truth). | L |
| Browse / search / sort (artist, BPM, key) | ○ | ○ | ○ | List + search over the store; needs **key detection** (see Foundations). | M |
| Album art + metadata | ○ | ○ | ○ | Read ID3/MP4 tags (AVFoundation `AVMetadataItem` on Apple; `lofty`/`symphonia` tags on Slint). | M |
| Smart playlists ("120 BPM uplifting") | ○ | ○ | ○ | Query predicates over the store once BPM/key are indexed. | M |
| Watch-folder auto-import (desktop) | — | ○ | ○ | Filesystem watcher (`FSEvents` mac, `notify` crate Slint); auto-enqueue new files to split. | M |

### B. Instant re-open (split once, never re-split)

Open a previously-split song and play immediately — no separation wait.

| Capability | iOS | macOS | Win/Linux | How we get it done | Effort |
|---|:--:|:--:|:--:|---|:--:|
| Stem cache keyed by audio hash | ○ | ○ | ○ | Hash decoded PCM (or file + model name) → cache dir of 4 stem WAVs + a sidecar JSON (tempo/key/loops). Core helper `stem_cache_key()`. | M |
| Instant load from cache | ○ | ○ | ○ | On open, if the key hits, load stems directly and skip `separate`/`load_stems`. | S |
| Project state (loops, mix, view) | ○ | ○ | ○ | Persist per-project UI state in the sidecar; restore on open. | M |
| Cache management / size limits | ○ | ○ | ○ | LRU eviction + a Settings control (durable cache paths already in PRODUCT vision). | S |

### C. Download / export stems

Get stems out of the app.

| Capability | iOS | macOS | Win/Linux | How we get it done | Effort |
|---|:--:|:--:|:--:|---|:--:|
| Export stems (WAV) | ○ | ✅(core) | ✅ | iOS: **share sheet** (`UIActivityViewController`) of the 4 WAVs we already hold. macOS: `NSSavePanel` to a folder. Slint already does this. | S |
| Export formats (MP3/M4A/FLAC) | ○ | ○ | ○ | Encode via AVAudioFile (Apple) / `symphonia`+encoder (Slint). | M |
| Export bundle (zip: stems+mix+meta) | ○ | ○ | ○ | Zip the stem dir + a metadata JSON; the **server already produces stems** and could return a zip. | S |
| AirDrop / iCloud Files | ✅(via share) | ✅ | — | Falls out of the iOS share sheet + Files provider. | S |
| Drag stems into a DAW | — | ○ | ○ | macOS: `NSItemProvider` drag from each stem lane. Slint: native drag-source. | M |

### D. Stem Mixer / cross-song mashup  ← the headline vision

Load two split songs, match tempo + key, and interchange stems (e.g. song A's
drums + bass under song B's vocals).

| Capability | iOS | macOS | Win/Linux | How we get it done | Effort |
|---|:--:|:--:|:--:|---|:--:|
| Load 2 projects into a mixer deck | ○ | ○ | ○ | New "Mixer" surface: two source slots, each a split project (from the Library/cache so there's no wait). | L |
| Per-source stem routing / swap | ○ | ○ | ○ | An 4×2 routing grid: pick which source feeds each output stem (A.drums + A.bass + B.vocals + B.melody). Engine plays the 4 chosen buffers synced to a master clock. | M |
| **Tempo match** (time-stretch) | ○ | ○ | ○ | Pick a master BPM; time-stretch each source to it. **Apple:** `AVAudioUnitTimePitch` (native, free). **Slint:** a Rust phase-vocoder (port the STFT we have to a stretch, or bind `signalsmith-stretch`). | L |
| **Key match** (pitch-shift) | ○ | ○ | ○ | Detect each song's key (Foundations), compute semitone delta, pitch-shift. Apple: `AVAudioUnitTimePitch.pitch`. Slint: phase-vocoder pitch-shift. | L |
| Beat/downbeat alignment | ○ | ○ | ○ | Align using the core's `measureOffset`; quantize loop start to the grid (we already snap loops). | M |
| Crossfade / A-B blend | ○ | ○ | ○ | Equal-power crossfade between the two sources' shared stem (the wishlist "Stem Shuffle" lead A/B). | M |
| Save mashup as audio | ○ | ○ | ○ | Offline-render the routed graph to a WAV (AVAudioEngine manual-render / cpal offline). | M |

This is the most ambitious item. It needs two **Foundations** below (key detection,
time-stretch/pitch-shift) before the mixer UI is worth building.

### E. Acquisition (get songs in faster)

| Capability | iOS | macOS | Win/Linux | How we get it done | Effort |
|---|:--:|:--:|:--:|---|:--:|
| Apple Music import | ○ | ○ | — | **MusicKit**: play/library access. Note: DRM means we can separate only what the OS lets us render/export (user-owned files), not arbitrary catalog audio. | L |
| Spotify search + 30s preview | ○ | ○ | ○ | Spotify Web API gives metadata + **30s preview URLs only** (no full tracks — DRM). Good for "preview → find → split your own copy", not for splitting catalog tracks. | M |
| YouTube / URL import (desktop) | — | ○ | ○ | `yt-dlp` subprocess on desktop (legal gray area; user-supplied URLs only). Not viable in the iOS sandbox. | M |
| Files / Music app picker | ✅ | ✅ | ✅ | Already have file import; extend to the Music app document types. | S |

> **Honest constraint:** streaming services are DRM-locked. We can integrate
> search/preview/metadata, but full-track separation legally requires audio the
> user owns. Lead with "split files you own" + preview-driven discovery.

### F. Creation (record + transform)

| Capability | iOS | macOS | Win/Linux | How we get it done | Effort |
|---|:--:|:--:|:--:|---|:--:|
| Record vocal/instrument over stems | ○ | ○ | ○ | Mic input: `AVAudioEngine.inputNode` (Apple) / `cpal` input (Slint), monitored against playing stems; save as a 5th track. | L |
| Per-stem effects (EQ/reverb/delay) | ○ | ○ | ○ | Apple: `AVAudioUnitEQ`/`Reverb`/`Delay` inserts per player node. Slint: DSP in the Rust core. | L |
| Stem ducking (vocals lower bass) | ○ | ○ | ○ | Sidechain envelope follower in the engine/core. | M |
| MIDI from melody / acapella isolate | ○ | ○ | ○ | MIDI: pitch-tracking (e.g. CREPE/pYIN) → notes. Acapella: it's just the vocals stem exported clean. | XL / S |

### G. Sync, sharing, ecosystem

| Capability | iOS | macOS | Win/Linux | How we get it done | Effort |
|---|:--:|:--:|:--:|---|:--:|
| iCloud project sync | ○ | ○ | — | CloudKit mirrors the project store + stems. Apple-only. | L |
| Stem Shuffle surface | ○ | ○ | ○ | The wishlist's pair-picker (crossfade, lead A/B, blend) — a lighter cousin of the Stem Mixer; can ship first as a stepping stone. | M |
| Share / collaborate (send stems) | ◐ | ◐ | ◐ | Share sheet today; later a project file format (stems + metadata) others can open. | M |
| Creator profiles / marketplace | ○ | ○ | ○ | Requires the optional backend in NATIVE_WISHLIST (discovery, accounts). Far future. | XL |

---

## Part 3 — Foundations (cross-cutting; unblock the above)

These are shared building blocks several proposed features depend on. Build once
in the Rust core where possible so all three surfaces benefit.

| Foundation | Where | How | Unblocks |
|---|---|---|---|
| **Key detection** | `stemacle-dsp` (`key.rs`) + FFI | Chromagram from the STFT we already compute → Krumhansl-Schmuckler key profile correlation → key + mode. | Library sort, Stem Mixer key-match, smart playlists |
| **Time-stretch** | Apple native + Rust crate | Apple `AVAudioUnitTimePitch`; Slint a phase-vocoder (reuse our STFT/ISTFT) or `signalsmith-stretch`. | Tempo match, mashup |
| **Pitch-shift** | same as above | Same units, pitch parameter. | Key match, mashup, creative FX |
| **Project store** | `stemacle-store` crate (`rusqlite`) + SwiftData | One schema: projects, stems, loops, mix state, tags. FFI for Slint; SwiftData mirror or FFI on Apple. | Library, instant re-open, sync |
| **Stem cache** | core + per-OS cache dirs | Audio-hash keyed dir of stem WAVs + sidecar JSON. | Instant re-open, mixer (no re-split) |
| **Audio metadata** | per-OS | AVFoundation tags (Apple), `lofty` (Slint). | Library art/metadata |
| **Slint parity** | `native/desktop` | Rebuild loops/spectrogram/visualizer/seek/progress over the existing core (the data is already exposed via FFI). | Brings Win/Linux up to the Apple apps |

---

## Suggested sequencing

1. **Slint parity** + **iOS/macOS share-sheet export** — close current gaps; small/medium.
2. ~~**Stem cache + Instant re-open**~~ ✅ shipped (iOS/macOS) — `LibraryStore` writes per-project stem WAVs; reopen skips separation.
3. ~~**Project store + Song Library**~~ ✅ shipped (iOS/macOS) — TabView shell `Library | Splitter | Settings` per the verified `specs/Navigation.tla`.
4. **Key detection** (core) — small, unblocks library sort/search and the mixer.
5. **Time-stretch / pitch-shift** then the **Stem Mixer** — the marquee feature, built on 2–4.
6. Acquisition (preview/MusicKit), Recording, Effects, Sync — as the roadmap allows.

> Updated 2026-06-25: items 2–3 are live on Apple (iOS/macOS). Library/cache for
> the Slint desktop and the Mixer tab are next.
