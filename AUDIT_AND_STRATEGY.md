# Stemacle: Rigorous Multi-Surface Audit & Strategic Planning

**Date:** 2026-06-29  
**Scope:** Web (gold master), Apple native (iOS/macOS SwiftUI), Desktop (Slint)  
**Cannot test:** Windows (Desktop), Android

---

## Part 1: 50-Item UX/UI Audit

A comprehensive scan of all three surfaces for inconsistencies, behavioral gaps, and critical issues. Organized by severity and impact.

### TIER 1: CRITICAL (Blocks Shipping)

#### Playback & Transport Issues

**1. Loop State Loss on Pause/Resume (Apple native)**  
**Surfaces:** iOS, macOS  
**Issue:** When playback is paused mid-loop, then resumed, `audibleStemTime` calculation doesn't account for playback offset correctly if `startDate` is nil during pause.  
**Code:** `StemAudioEngine.swift:120-126`  
**Impact:** User resumes in wrong position within a loop, breaks loop semantics contract.  
**Fix priority:** High — loop timing is a core product invariant.

**2. Seek During Loop Doesn't Snap to Grid (Web)**  
**Surfaces:** Web app only  
**Issue:** Clicking a spectrogram to seek doesn't snap to the measure grid when a loop is active. Loop window remains fixed while transport jumps.  
**Code:** `app/index.html:~1375-1379` (spectralTimeFromClientX)  
**Impact:** Loop boundaries become misaligned; violates loop contract.  
**Fix priority:** High.

**3. All-Loop Clear Not Clearing Per-Stem Loop UI (Apple native)**  
**Surfaces:** iOS, macOS  
**Issue:** `setAllLoop(bars: nil)` clears state but the per-stem `loopBars` dictionary may diverge from the 4 stems; some buttons remain visually "on" while audio has no loop.  
**Code:** `StemPlayerViewModel.swift:440-455`  
**Impact:** State mismatch: UI shows "on" but audio doesn't loop.  
**Fix priority:** High — data integrity issue.

**4. Desktop Slint Loop Buttons Missing (Feature Gap)**  
**Surfaces:** Desktop (Slint)  
**Issue:** The entire loop feature (1/4, 1/2, 1, 2 measure) is absent from desktop UI.  
**Code:** `native/desktop/ui/stemacle.slint:97-129`  
**Impact:** Desktop cannot set loops; violates parity-plus contract.  
**Fix priority:** Critical — blocks feature parity.

#### File Intake & State Persistence

**5. Web: No Drag-Drop Feedback Until File Appears (UX)**  
**Surfaces:** Web app  
**Issue:** `device.drag-active` class only applied while dragging, removed on leave; no sustained visual feedback.  
**Code:** `app/index.html:~156`  
**Impact:** User unsure if drag worked until processing begins (2-3s later).  
**Fix priority:** Medium.

**6. Apple: No Visual Drag-Drop Feedback (Missing)**  
**Surfaces:** iOS, macOS SwiftUI  
**Issue:** `.onDrop()` modifier sets `dropTargeted` only on macOS. iOS uses `fileImporter` (document picker) with no visual feedback.  
**Code:** `StemacleApp.swift:304-306` (macOS only), `StemacleApp.swift:60` (iOS fileImporter)  
**Impact:** iOS user has no affordance or feedback for file intake.  
**Fix priority:** Medium — iOS handles file intake differently than macOS; may be intentional design.

**7. Desktop: No Sample Tracks (Feature Gap)**  
**Surfaces:** Desktop (Slint)  
**Issue:** Web bundles three MP3s in `samples/`; desktop has no sample loader button.  
**Code:** `stemacle.slint:133-141`  
**Impact:** Desktop users must find their own audio file; onboarding friction.  
**Fix priority:** Medium.

#### Visualization & Feedback

**8. iOS Waveform Envelope Doesn't Scroll (Regression vs. Web)**  
**Surfaces:** iOS  
**Issue:** iOS uses peak waveform envelopes (O(cols) compressed) to avoid OOM, but renders them as time-scrolling lanes. Envelope is static; scrolling cursor misaligns with visual peaks.  
**Code:** `StemPlayerViewModel.swift:154-158` (peak envelopes), `VisualizerViews.swift:95-114`  
**Impact:** Seeking by tapping envelope doesn't land on visual peak; breaks tactile trust.  
**Fix priority:** High — iOS primary surface.

**9. Desktop: No Spectrogram, No Loop Grid (Major Feature Gap)**  
**Surfaces:** Desktop (Slint)  
**Issue:** Zero visualization — no spectrograms, no measure grid, no play cursor. Only stem controls exist.  
**Code:** `stemacle.slint:97-129`  
**Impact:** Users cannot see playback position, cannot visualize loop regions, cannot confirm state. Breaks design principle ("circle is the product").  
**Fix priority:** Critical — desktop is non-functional for visual feedback.

#### Loop Monitoring Modes

**10. Web: No UI State for Solo-Mode Loop Monitoring (Hidden Feature)**  
**Surfaces:** Web app  
**Issue:** `loopAuditionMode` buttons are always enabled, but Solo mode is a no-op without a loop. UI doesn't disable/differentiate buttons based on loop state.  
**Code:** `app/index.html:890-891` (mode buttons), `app/index.html:1513-1514` (Solo mode only inside loop code)  
**Impact:** User toggles Solo mode, sees button change, hears nothing; assumes feature is broken.  
**Fix priority:** High.

**11. Apple: Missing Loop Monitoring UI Button (Feature Regression)**  
**Surfaces:** iOS, macOS  
**Issue:** `LoopControlBar` calls `setLoopMonitoring(solo:)` but doesn't enforce that Solo requires a loop. Button state changes but playback doesn't; no visual feedback.  
**Code:** `LoopControlBar:418-419`  
**Impact:** Confusing UX; button works but has no audible effect without a loop.  
**Fix priority:** High.

---

### TIER 2: HIGH (UX Polish, Reliability)

#### State Synchronization & Edge Cases

**12. Web: Loop Alert Uses `alert()` (Breaks Immersion)**  
**Surfaces:** Web app  
**Issue:** Browser alert box pops for "loop too long" error (jarring, breaks aesthetic).  
**Code:** `app/index.html:1504`  
**Impact:** Breaks warm, minimal design.  
**Fix priority:** Medium — replace with toast/in-UI message.

**13. Apple: Loop Too-Long Error Silently Fails (UX)**  
**Surfaces:** iOS, macOS  
**Issue:** `setLoop()` sets status message but status only displays during idle/processing, not ready playback.  
**Code:** `StemPlayerViewModel.swift:430-433` (status set), `lines 385-390` (status display conditions)  
**Impact:** User taps loop button, sees nothing happen, no error message.  
**Fix priority:** High.

**14. Desktop: No Error/Status Messages at All (Feature Gap)**  
**Surfaces:** Desktop (Slint)  
**Issue:** `status` property exists but never updates beyond "Drop or choose a track."  
**Code:** `stemacle.slint:22` (status in-property), `lines 68-75` (display)  
**Impact:** User has zero feedback on errors or state changes.  
**Fix priority:** High.

**15. iOS: Long-Track Separation Silently Truncates to 90s (Undiscoverable Limitation)**  
**Surfaces:** iOS only  
**Issue:** Separation capped at 90s to avoid OOM. Status message only surfaces if `wasTrimmed`, buried in loading flow. After split, "on-device (90s)" label shown but users may not realize rest of track is silence/padding.  
**Code:** `StemPlayerViewModel.swift:272-282` (truncation), `line 302` (quality label)  
**Impact:** iOS user loads 5-min song, gets stems only for first 90s, discovers this too late.  
**Fix priority:** High — data integrity / expectation-setting.

**16. Web: No Visual Indication of Tempo Fallback (Detection Failure Hidden)**  
**Surfaces:** Web app  
**Issue:** Tempo detection falls back to 120 BPM silently if confidence is too low. No indication to user that grid might be wrong.  
**Code:** `app/index.html:1020` (TEMPO_MIN_CONFIDENCE = 0.04); fallback is silent  
**Impact:** User sets loop on song with bad tempo detection, loop window is 20% too long.  
**Fix priority:** Medium.

#### Visual Inconsistencies

**17. Desktop: Purple/Amber Colors Don't Match Web or Apple (Design Regression)**  
**Surfaces:** Desktop (Slint)  
**Issue:** Slint uses `#6b578f` (hex), Web uses oklch lab values, Apple uses SwiftUI RGB. Hex values don't match; desktop purple is more saturated.  
**Code:** `stemacle.slint:~64`, `app/index.html:25`, `DesignTokens.swift:11`  
**Impact:** Brand inconsistency.  
**Fix priority:** Medium.

**18. iOS/macOS: Loop Button Active State Color (Amber vs. Purple)**  
**Surfaces:** iOS, macOS, Desktop  
**Issue:** Web shows amber glow, native shows amber background, Slint shows purple. Three different affordances for "active loop."  
**Code:** `app/index.html:736`, `StemacleApp.swift:430`, `stemacle.slint:120`  
**Impact:** Users switching between surfaces don't recognize same affordances.  
**Fix priority:** Medium.

**19. Web: Vocal Headphones Icon Has Animated Pulse (Only on Web)**  
**Surfaces:** Web app  
**Issue:** Decorative animation on vocal headphones button only on web; missing on Apple/desktop.  
**Code:** `app/index.html:677-715`  
**Impact:** Inconsistent polish.  
**Fix priority:** Low.

#### Accessibility

**20. Desktop: No Keyboard Navigation (Accessibility Gap)**  
**Surfaces:** Desktop (Slint)  
**Issue:** No TabIndex, keyboard shortcuts, or focus management. Keyboard-only users cannot use app.  
**Code:** `stemacle.slint` — no `:focus`, no keyboard handlers  
**Impact:** App unusable for keyboard-only users.  
**Fix priority:** High.

**21. Web: No ARIA Live Region for Tempo/Loop Messages (Accessibility)**  
**Surfaces:** Web app  
**Issue:** Loop success is not announced to screen readers; only `aria-pressed` state updates on buttons.  
**Code:** `app/index.html:991-995` (overlay is live region, but loop success not announced)  
**Impact:** Screen reader users don't get feedback.  
**Fix priority:** Medium.

**22. Apple: Stem Order Not Accessible Via VoiceOver (Accessibility)**  
**Surfaces:** iOS, macOS  
**Issue:** Stem rows lack accessibility labels for sequencing; VoiceOver users lose spatial awareness.  
**Code:** `StemacleApp.swift:258` (ForEach loop, no sequencing label)  
**Impact:** VoiceOver users lose context.  
**Fix priority:** Medium.

#### Performance & Memory

**23. Web: STFT Spectrogram OOM on Long Tracks (Potential Crash)**  
**Surfaces:** Web app  
**Issue:** No cap on track length for spectrogram allocation. 30-minute track → ~200 MB spectrogram that could exhaust browser memory.  
**Code:** `app/index.html:1559-1570` (stft function, no length check)  
**Impact:** Browser crash on long tracks.  
**Fix priority:** High.

**24. Apple macOS: Full Spectrogram on Every Track (Battery/Thermal)**  
**Surfaces:** macOS only  
**Issue:** Full spectrogram computed for every track on every load; 10+ seconds on 30-min files.  
**Code:** `StemPlayerViewModel.swift:169-171`  
**Impact:** macOS app feels slow on long files.  
**Fix priority:** Medium.

#### Data Handling

**25. Web: Mute State Not Persistent Across Sessions (Expected, But Confusing)**  
**Surfaces:** Web app  
**Issue:** No localStorage for mute/volume state. Browser close = lost state. No disclaimer on load.  
**Code:** `app/index.html` — no sessionStorage  
**Impact:** User must re-set mix every refresh.  
**Fix priority:** Low (by design, but could add sessionStorage).

**26. Apple: Library Stem Cache Corruption on Dual-Engine Split (Data Integrity)**  
**Surfaces:** iOS, macOS  
**Issue:** When macOS subprocess Demucs finishes and browser DSP finishes in parallel, race condition can save partial stems.  
**Code:** `StemPlayerViewModel.swift:245-262` (race between analysisTask and subprocStems)  
**Impact:** Cached stems could be incomplete.  
**Fix priority:** High — data integrity.

---

### TIER 3: POLISH (Nice-to-Have Consistency)

**27. Web: Play/Pause Button Text Doesn't Update During Dragging (Minor UX)**  
Button says "play" during seeking, updates after drag completes. Brief visual lag.  
**Fix priority:** Low.

**28. Apple: Stop Button Position Display Lags (Minor)**  
~33ms delay before position display updates after stop.  
**Fix priority:** Low.

**29. Desktop: No Visual Feedback on Button Hover (Minor Polish)**  
Buttons look same on hover; missing affordance cue.  
**Code:** `stemacle.slint:84-94` (no hover styling)  
**Fix priority:** Low.

**30. Apple iOS: No Prominent "Import" Button in Splitter Tab (Navigation)**  
"+" button in top-right not visually prominent on first load; new users may not discover it.  
**Code:** `StemacleApp.swift:281-288`  
**Fix priority:** Low.

**31. Web: Quadrant Volume Controls Hidden Until Ready (Discoverability)**  
Quadrant volume UI completely hidden until file loads; users don't know it exists.  
**Code:** `app/index.html:215` (display: none)  
**Fix priority:** Low.

**32. Desktop: No File Format Validation Feedback (UX)**  
File picker doesn't validate format before processing; error appears after user waits.  
**Code:** `stemacle.slint:134` (load-clicked doesn't check extension)  
**Fix priority:** Low.

**33. Web: Playbar Layout Breaks on Very Small Screens (Responsive)**  
Transport buttons overflow on phones under 320px.  
**Code:** `app/index.html:749-780` (media query)  
**Fix priority:** Low.

**34. iOS: Long Song Titles Overflow Loop Row (Responsive)**  
Layout shift when title scales; loop bar doesn't reserve space.  
**Code:** `StemacleApp.swift:273-278`  
**Fix priority:** Low.

**35. Web: Failed Model Download Doesn't Show Retry UI (Error Recovery)**  
ONNX download timeout falls back to DSP silently; no "Retry" button.  
**Code:** `app/index.html:1694-1698` (timeout catch)  
**Fix priority:** Medium — user must manually refresh.

**36. Apple: Subprocess Demucs Failure Cascade (Error Recovery)**  
If subprocess Demucs fails, on-device fallback runs synchronously, freezing UI for 10+ seconds.  
**Code:** `StemPlayerViewModel.swift:260-263` (catch block)  
**Fix priority:** High.

**37. Web: Loop Dot Cleared When Seeking Outside Loop Range (Silent Behavior)**  
Loop cleared silently when seeking past loop end; buttons remain visually "on."  
**Code:** `app/index.html` (spectrogram seeking logic)  
**Impact:** Loop appears set while inactive.  
**Fix priority:** Medium.

**38. Desktop: Per-Stem Volume But No Per-Stem Loop (Feature Parity Regression)**  
Can solo a stem but not loop just that stem; asymmetric feature set.  
**Code:** `stemacle.slint:112-120` (mute/solo only)  
**Fix priority:** High — breaks parity.

**39. Apple: Global Mute Doesn't Show Visual Indicator on Stem Icons (UI Clarity)**  
Tapping "Mute all" doesn't visually update stem icons; unclear that all stems are muted.  
**Code:** `StemacleApp.swift:493` (stem mute icon shows only individual state)  
**Fix priority:** Low.

**40. Web: Playbar Filename Truncates Silently (UX)**  
Long filenames truncated with no hover tooltip to see full name.  
**Code:** `app/index.html:408`  
**Fix priority:** Low.

**41. iOS: Settings Links Open in External Browser (Navigation)**  
SettingsView opens privacy/terms in Safari, disrupting user flow.  
**Code:** `StemacleApp.swift:572-576` (openURL)  
**Fix priority:** Low.

**42. Desktop: No Persistent Project Save (Feature Gap)**  
No library equivalent; every split is temporary. No "recent projects" or saved mix state.  
**Code:** `stemacle.slint` (no library UI)  
**Fix priority:** Medium — power user feature.

**43. Web: Focus Outline Color Doesn't Contrast (WCAG)**  
Focus outline may not meet WCAG AA contrast on cream background.  
**Code:** `app/index.html:740-741`  
**Fix priority:** Low.

**44. Apple: No Text Scaling in Loop Bar (Accessibility)**  
Loop button labels (¼, ½, 1, 2) don't scale with accessibility text size.  
**Code:** `StemacleApp.swift:412, 425` (`.font(.caption)`)  
**Fix priority:** Low.

**45. Web: Sample Track Buttons Don't Show Loading Indicator (UX Polish)**  
Button doesn't change to "Loading…" on click; no spinner.  
**Code:** `app/index.html` (sample button behavior)  
**Fix priority:** Low.

**46. Apple: MixerView Hint Text Not Updated When Sources Attached (UI)**  
Hint says "Pick two songs…" even after selection; should update to "Ready to mix."  
**Code:** `Mixer.swift:20` (@Published hint is static)  
**Fix priority:** Low.

**47. Desktop: Button Disabled State Not Visually Distinct (Accessibility)**  
Disabled buttons only use `opacity: 0.5`; hard to distinguish from enabled.  
**Code:** `stemacle.slint:86-87`  
**Fix priority:** Low.

**48. Web: Double-Click Play Button During Playback (Edge Case)**  
First click pauses, second resumes immediately; button state flickers.  
**Code:** `app/index.html:881` (no debounce)  
**Fix priority:** Low.

**49. Apple: Rapid Loop Toggle Can Miss State Update (Race)**  
Rapidly tapping two loop buttons before engine finishes can diverge state from audio.  
**Code:** `StemPlayerViewModel.swift:422-437` (no lock/queue)  
**Fix priority:** Medium.

**50. Desktop: No Volume Ceiling (Potential Audio Clipping)**  
Volume slider goes to 1.0 with no output limiter; can distort if all stems at max.  
**Code:** `stemacle.slint:123-127` (Slider to 1.0, no ceiling)  
**Fix priority:** Medium.

---

## Part 2: Strategic Porting Guide for Windows & Android

### Windows (Desktop) — Already Exists, Untested

**Current state:** Slint is cross-platform. `native/desktop/` code compiles on Windows but is never tested on Windows machines. **The problem:** no Windows CI/testing, no validation of Windows-specific audio codecs, font rendering, file paths, model precision.

#### Phase 1: CI Foundation (Required Before Ship)
- Add GitHub Actions `windows-latest` runner to build/test `native/desktop/`
- Validate Slint's Windows backend (font rendering, DPI scaling, input method)
- Test audio codec detection on Windows (MP3, WAV, FLAC; verify against web baseline)
- Test file path handling (Windows backslashes, UNC paths, special characters)
- Verify ONNX Runtime precision on Windows ≤ 1-2% vs. Linux/web

**Timeline:** 1 week  
**Complexity:** Medium (mostly CI setup + codec validation)

#### Phase 2: Platform Hardening (2–3 weeks)
- Native Windows file picker (replace generic Slint picker if needed)
- Audio format validation layer (ensure MP3/WAV/M4A supported; fallback to DSP)
- Model precision validation (run test MP3s through ONNX on Windows, diff outputs)
- Slint UI scaling on high-DPI displays (1080p, 1440p, 4K validation)
- Global hotkey registration (if desktop hotkeys planned; requires `winapi` crate)

#### Phase 3: Distribution (1–2 weeks)
- Code signing (Windows `.exe` with code-signing certificate; prevents SmartScreen)
- NSIS/WiX installer (`.msi` or `.exe` installer; Start Menu shortcuts, uninstall)
- Redistributable dependencies (bundle ONNX Runtime, validate `.dll` versions)
- Post-install verification (auto-run app after install; surface missing dependencies)

#### Phase 4: Ongoing Support (Post-Ship)
- User feedback loop for Windows-specific bugs
- Regression testing before each release (build + smoke test on Windows CI)

**Total effort:** 4–6 weeks to ship  
**Risk mitigation:** Canary release (beta on GitHub first); gather telemetry for 2–4 weeks before general release.

---

### Android — No Code Yet

**Current state:** iOS exists via SwiftUI. **No Android equivalent.** Slint has experimental Android support (not production-ready as of 2026).

#### Recommended Approach: Kotlin + Jetpack Compose
- **Why:** Google's standard. Best Android UX patterns. Direct access to Android APIs (media, storage, notifications). Shared Rust core via FFI.
- **Why not Flutter:** Kotlin is the future (Google prioritizes Kotlin Multiplatform); Flutter's audio handling is less mature.
- **Why not React Native:** Mediocre audio performance; JS thread stalls during long separation tasks.
- **Why not Slint:** Experimental Android support; incomplete API access; may not feel native.

#### Phase 1: Foundation (Weeks 1–2)
- Kotlin module scaffold: `native/android`
- Link Rust core via `StemacleCore.so` (pre-built from `native/core/`)
- Audio decode wrapper (MediaCodec or ExoPlayer for MP3/WAV/FLAC → PCM)
- Minimal UI: Stemacle circle + basic transport (play/pause/stop)
- Rust FFI bindings (generate Kotlin bindings to `stemacle_separate`)

#### Phase 2: Core Parity (Weeks 3–5)
- Stem separation (call Rust on background thread; show progress overlay)
- Four-stem playback (volume, mute, headphones solo per stem)
- Audio engine (Android's AudioTrack + MediaPlayer; match iOS latency)
- Loop controls (1/4, 1/2, 1, 2 measure; per-stem independence; tempo detection)
- Waveform visualization (O(n) peak envelopes, not full STFT; RAM-efficient)

#### Phase 3: Android Power Features (Weeks 6–7)
- File storage (Android Storage Access Framework; scoped storage Android 11+)
- Background service (foreground service for long-running separation; user-visible notification; handle Doze mode)
- Local library (SQLite DB of past projects; quick re-access to cached separations)
- Headphone detection (Bluetooth/wired/speaker routing; auto-pause on unplugging)
- Haptics & Material Design 3 (Compose navigation drawer, bottom sheets, dialogs)

#### Phase 4: Testing & Hardening (Weeks 8–10)
- Device matrix: Pixel 7 (baseline), Samsung Galaxy A51 (mid-range 4GB), OnePlus 12 (flagship), iPad mini (large screen)
- Long file stress test (1-hour+ track; verify no OOM, no ANR, responsive playback)
- RAM pressure (trigger low-memory warnings; verify graceful degradation)
- Audio quality (separation results should match web/iOS to within 1–2% loudness)

#### Phase 5: Distribution (Weeks 11–12)
- Google Play submission (release APK/AAB; sign with Play Store key)
- Play Store listing (screenshots, description, privacy policy, IARC rating)
- Beta testing (release to 1000 testers; collect crashes, feedback)
- Launch (public release; monitor crash rate)

**Total effort:** 10–12 weeks to ship parity app with local library + background processing  
**Risk mitigation:** Beta testing on device matrix; CI emulator testing; crash rate < 2% before public release.

---

### Cross-Platform Testing Strategy

#### Dependency Graph
```
native/core (Rust DSP) — the truth
├── native/apple (SwiftUI) ✅ shipping
├── native/desktop (Slint Linux) ✅ compiles, untested
├── web (JS/WASM) ✅ shipping
├── native/desktop (Slint Windows) ⏳ needs CI + hardening
└── native/android (Kotlin) ⏳ doesn't exist yet
```

#### Golden Vector Regression (For Untested Platforms)
Since you can't run Windows/Android locally:
1. Store audio test files (bundled MP3s) on all platforms
2. Run separation on each platform; diff outputs against web baseline
3. Flag any energy drift > 1% per-stem
4. Smoke tests in CI: load three MP3s, verify no crashes/OOM/decode failures
5. User feedback loop: beta testers on Windows/Android, GitHub issue tracker

#### Release Checklist (Before Ship Date)

**Windows:**
- [ ] CI builds and tests Windows Slint app on every commit
- [ ] Sample MP3s decode correctly on Windows
- [ ] ONNX Runtime outputs match Linux within 1% per-stem loudness
- [ ] UI doesn't break on 1080p, 1440p, 4K
- [ ] File picker handles Windows paths correctly
- [ ] Code-signed `.exe`, `.msi` installer works
- [ ] Post-install verification passes

**Android:**
- [ ] Kotlin/Jetpack scaffolding compiles
- [ ] Rust DSP bindings work (no JNI crashes)
- [ ] Audio decode works (MediaCodec or ExoPlayer)
- [ ] Separation runs on background thread (no ANR)
- [ ] Long-file RAM usage < 1 GB
- [ ] Haptics, notifications, storage SAF work
- [ ] Google Play beta: < 2% crash rate over 2 weeks
- [ ] Privacy policy and IARC rating approved

---

## Part 3: 75-Item Feature Wishlist

**Philosophy:** Not cosmetic tweaks or easy wins. Substantive features that deepen the core music tool and make Stemacle a destination for serious stem work.

### Mixing & Mastering (10)

1. **Stem EQ (3-band parametric)** — Per-stem EQ with interactive frequency viz. Persist presets.
2. **Stem compression** — Threshold, ratio, attack, release. Visual gain reduction meter.
3. **Stereo imaging per stem** — Width control, pan knob, M/S mode toggle. Stereo correlation display.
4. **Master chain** — Linear limiter + soft clipper. LUFS/RMS/peak metering.
5. **Phase alignment tool** — Visual phase correlation. Manual delay adjustment per stem (ms).
6. **Stem blending** — Crossfade between stems (e.g., 20% vocals + drums). Export blended stems.
7. **Doubling/delay** — Independent delay line per stem (time, feedback, wet/dry). Tempo-sync.
8. **Sidechain analysis** — Heat map of spectral overlap between stems. Which stems mask frequencies.
9. **Reference stem layering** — Load external reference track, A/B mix at matched loudness.
10. **Loudness normalization** — LUFS metering and automatic stem gain matching (–14 for streaming, –23 for cinema).

### Stem Isolation & Separation Quality (8)

11. **Stem isolation strength slider** — Adjust separation aggressiveness (isolated vs. clean). Real-time preview.
12. **Alternative model selection** — Switch between Demucs variants mid-session. Model comparison mode.
13. **Stem confidence display** — Per-stem separation confidence (0–100%) based on model entropy. Flag low-confidence.
14. **Stem refinement brush** — Manual spectral editing: paint unwanted frequencies out or recover detail. Undo/redo.
15. **Stem rejection** — Mark 5-second segments "do not process" and re-run. Iterative refinement.
16. **Mono stem detection** — Auto-flag effectively-mono stems; offer mono export.
17. **Transient preservation** — Toggle to preserve/soften attack transients separately.
18. **Stem morphing** — Smooth interpolation between two separation results (0–100 slider).

### Export & Sharing (7)

19. **Stem export as multitrack** — All four stems as a single multitrack WAV (separate tracks) for DAW import.
20. **Stem export with metadata** — Tag each stem with name, duration, sample rate, separation model.
21. **Stem format flexibility** — WAV, MP3, M4A, FLAC, OGG with bitrate selection per format.
22. **Stem splitting presets** — Save custom "stem mix" (e.g., 70% vocals, 30% drums) and export as single file.
23. **Share stem mix URL** — Generate shareable link for read-only playback mode with same stem mix.
24. **Stem BPM tagging** — Include detected BPM in metadata. Offer BPM correction.
25. **Stem credits template** — Auto-fill credits (track name, artist, separator model). User-customizable footer.

### Library & Project Management (10)

26. **Auto-import folder** — Watched folder (`~/Music/To Split`). Auto-process new files in background.
27. **Project history with versioning** — Each separation result is a version. Branch and compare versions.
28. **Stem snapshots** — Labeled snapshots of current state: separation, loops, mix levels, EQ. Load any snapshot.
29. **Batch processing queue** — Load 5–50 files, queue for overnight separation. Progress display, pause/resume.
30. **Project tagging** — Tag projects (genre, artist, "needs work", "done", "archive"). Filter by tags.
31. **Smart collections** — Auto-collections: "recent", "long tracks" (>5 min), "failed separations", "unfinished loops".
32. **Separation cache** — Store full separation results. Re-open cached track loads stems instantly.
33. **Project search** — Full-text search by track name, artist, tags, metadata. Fuzzy matching.
34. **Stem comparison history** — Track which model/settings used per project. Compare results side-by-side.
35. **Undo/redo full project state** — Undo separation changes, EQ tweaks, gain adjustments, not just loops.

### Loop & Timing (8)

36. **Polyrhythmic loops** — Different loop lengths on different stems (4 bars drums, 8 bars vocals). Manual sync.
37. **Loop fade in/out** — Fade at loop boundaries (1–500 ms). Per-stem fade control.
38. **Groove lock** — Lock playback to grid derived from leading stem's attack transients. Dynamically sync if tempo drifts.
39. **Loop marker annotations** — Label loop points ("verse start", "chorus", "bridge"). Timeline view of all markers.
40. **Variable loop speed** — Slow down or speed up loop (0.5x–2x) without changing pitch. Tempo-sync update.
41. **Cue points** — Named cue points throughout track ("intro", "drop", "outro"). One-click jump.
42. **Loop statistics** — Display loop length in ms, beats, bars. Loop coverage % of track.
43. **Swing/humanize loop** — Add groove quantization or humanization (±5–50 ms random timing) to playback.

### Visual & Analysis Tools (9)

44. **Frequency heatmap** — Waterfall/spectrogram over time. Show where energy lives. Stem contribution viz.
45. **Stem isolation spectral view** — FFT of each stem vs. original. See what was "removed" to isolate.
46. **Waveform zoom & navigation** — Pinch-zoom (mobile) or scroll-wheel (desktop). Minimap sidebar for fast nav.
47. **Loudness curve display** — LUFS/RMS over time as overlay on waveform. Identify dynamic range issues.
48. **Stereo correlation meter** — Real-time M/S scope. Identify phase issues at a glance.
49. **Harmonic analysis overlay** — Detected pitch and harmonic series as musical staff on vocals stem.
50. **Separation quality radar** — Radar chart comparing models on energy preservation, isolation, artifacts.
51. **Time-aligned layer view** — Waveforms of all four stems time-aligned (stacked/overlaid), sync'd to transport.
52. **Peak hold memory** — Metering holds peak values for 2–5 sec. Quick visual peak spotting.

### Playback & Performance (5)

53. **Crossfade at loop points** — Auto-crossfade loop repetitions (1–500 ms) to hide artifacts.
54. **Beat sync transport** — Clicking a stem row jumps to nearest beat boundary (no fractional-beat seeking).
55. **Lookahead preview** — Hover over waveform to hear 0.5–2 sec preview without moving transport.
56. **Background separation** — On desktop/iOS, run separation as background task while UI stays responsive.
57. **RAM-efficient long-track mode** — For >30 min tracks, stream processing in chunks instead of holding all in RAM.

### Platform-Specific Power Features (5)

58. **Desktop: Stem folder export** — Create folder with stems as separate files, each with artwork embedded. Open in Finder.
59. **Desktop: System hotkey control** — Global keyboard shortcuts (play/pause, next stem, prev stem) even when backgrounded.
60. **iOS: Lock screen playback widget** — Show current track, transport buttons, stem mix levels on lock screen (iOS 16+).
61. **iOS: AirPlay stem isolation** — AirPlay to speaker but solo a stem (drums only to speaker, full mix to headphones).
62. **Web: PWA installation** — Install as PWA on desktop/mobile. Offline separation support (models cached).

### AI/Adaptive Features (4)

63. **Smart stem recommendations** — Based on loaded track, suggest remix ideas. Learn from user choices.
64. **Vocal acapella auto-detect** — If vocals > 80% of mix energy, flag as acapella; offer acapella export.
65. **Instrumental auto-detection** — If no vocals, offer "instrumental-only export" mode.
66. **Remix generation** — Given a track, generate 3–5 automated remix stems (bass boost, vocal isolation, instrumental).

### Collaboration & Sharing (3)

67. **Remix pack generation** — Export .zip with stems + metadata + template remix project (REAPER, Ableton, Logic).
68. **Collaborative editing** — Share project link; others adjust your stem mix levels and EQ. Real-time changes.
69. **Stem remix gallery** — Upload track, see remixes others created from same source. Listen, rate, download remix stems.

### Accessibility & Workflow (3)

70. **Voice commands** — "Play", "pause", "next stem", "mute all", "loop measures 4 to 8". Speech-to-command.
71. **Keyboard-only navigation** — Full app control via keyboard (no mouse). Arrow keys, Enter, Space, modifiers.
72. **Text-to-speech stem names and status** — Read aloud current stem, transport state, loop boundaries.

### Developer/Creator Tools (3)

73. **Model export** — Export trained Demucs model weights alongside stems.
74. **Separation algorithm telemetry** — Export detailed logs: STFT frame counts, FFT bin resolutions, masking matrix values.
75. **Stem source comparison** — Compute and display how well stems sum back to original (residual energy).

---

## Summary & Prioritization

### Audit Findings: Desktop is the Weak Link

- **Web & Apple:** Mostly aligned; minor state-sync and visual inconsistencies.
- **Desktop (Slint):** Substantially incomplete — **missing loops, spectrograms, keyboard nav, error messages, project persistence.**

**Tier 1 blocker:** Fix loop UI parity across all surfaces before shipping desktop.  
**Tier 2 priority:** Add desktop spectrogram/visualization + project library + error messaging.

### Porting Strategy: Invest in CI First

- **Windows:** 4–6 weeks (add GitHub Actions CI, validate audio codecs, harden Slint, ship with code signing).
- **Android:** 10–12 weeks (Kotlin + Jetpack Compose, link shared Rust core, device testing on 3–5 phones).

**Success criteria:** < 1% crash rate within 30 days of release; golden vector regression on all platforms.

### Feature Wishlist: Audio-First, Not UX-First

The 75 features focus on **mixing/mastering depth, separation quality, library scale, and collaboration** — not cosmetic polish or easy wins. Top priorities:

1. **Per-stem EQ + compression** (makes remixing feel professional)
2. **Library + batch processing** (scales from one-off to producer workflow)
3. **Separation confidence + model selection** (gives users control over trade-offs)
4. **Multitrack export + metadata** (enables DAW integration)
5. **Background jobs + local cache** (makes tool responsive and persistent)

---

## Next Steps

1. **Address Tier 1 issues immediately** — Loop state, desktop visualization, silent failures.
2. **Add Windows CI** — Gate shipping desktop on passing Windows tests.
3. **Design Android strategy** — Commit to Kotlin + Jetpack; start scaffolding in parallel with Tier 1 fixes.
4. **Prioritize Tier 2 accessibility** — Keyboard nav on desktop, ARIA announcements on web, text scaling on iOS.
5. **Roadmap Tier 3** — Nice-to-have consistency passes after core shipping readiness.
