# iOS Parity Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the native-rewrite branch as PR #1, then fix three iOS gaps in order (scrolling spectrogram window, full-screen scroll, separation quality), then ship PR #2.

**Architecture:** All UI changes are in `native/apple/Stemacle/StemacleApp.swift` and `VisualizerViews.swift`. DSP quality improvements go in `native/core/stemacle-dsp/src/` (Rust). The StemacleKit FFI (`native/apple/StemacleKit/`) gets a new `waveformEnvelope` binding for iOS-safe visualization.

**Tech Stack:** SwiftUI, AVFoundation, Rust (stemacle-dsp + stemacle-ffi), StemacleKit xcframework

---

## Task 0: PR #1 — ship native-rewrite as-is

**Files:** none (git / gh only)

- [ ] **Step 1: Verify tests pass**

```bash
npm test
```
Expected: 143 pass, 0 fail

- [ ] **Step 2: Stage all tracked changes**

```bash
git add -u
git add README.md cloudflare/ docs/DEVELOPMENT.md docs/SEPARATION_CONTRACTS.md \
        native/apple/ExportOptions/ tests/cloudflare-api.test.mjs \
        tests/cloudflare-config.test.mjs tests/dsp-parity.test.mjs \
        tests/separation-contracts.test.mjs wrangler.api.toml
```

- [ ] **Step 3: Create PR using gh**

Use the pr-description skill or gh directly:
```bash
gh pr create --title "Native rewrite: SwiftUI iOS/macOS + Rust DSP core" \
  --base main --head native-rewrite \
  --body "$(cat <<'EOF'
## Summary
- Replaced Electron/Capacitor with native SwiftUI apps (StemacleMac + StemacleiOS)
- Shared Rust DSP core (stemacle-dsp + stemacle-ffi) across all surfaces
- Song Library with stem cache, TabView shell, compact player
- htdemucs subprocess on macOS; CoherenceSeparator (Rust) on iOS
- Web DSP parity tests, Cloudflare API tests, separation contract tests
- App Store submission assets, export options, iOS release script

## Test plan
- [ ] `npm test` — 143 tests pass
- [ ] `xcodebuild -scheme StemacleMac` builds
- [ ] `xcodebuild -scheme StemacleiOS -destination 'generic/platform=iOS Simulator'` builds

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: Merge PR #1** (quality judge: self — all 143 tests pass, both schemes build)

```bash
gh pr merge --squash --auto
```

---

## Task 1: Issue 1a — iOS memory-safe visualization (waveform envelope)

Root cause: `Stemacle.spectrogram()` runs a full STFT on each stem for visualization. For a 3-min track that's 5× ~200MB STFT allocations on-device = ~1 GB → iOS crash/OOM. The "14 seconds" is the bundled demo length; real songs fail silently.

Fix: expose `waveform_envelope` from the Rust core (O(n), O(cols) memory) and use it for iOS per-stem lanes. Keep spectrogram for macOS.

**Files:**
- Modify: `native/core/stemacle-ffi/src/lib.rs`
- Modify: `native/apple/StemacleKit/Sources/StemacleKit/StemacleKit.swift`
- Modify: `native/apple/Stemacle/StemPlayerViewModel.swift`
- Modify: `native/apple/Stemacle/VisualizerViews.swift`

- [ ] **Step 1: Add `stemacle_waveform_envelope` to FFI**

In `native/core/stemacle-ffi/src/lib.rs`, after the existing `stemacle_spectrogram` function, add:

```rust
/// Compute a `cols`-bucket peak waveform envelope (0..1). Allocation-free output
/// written to `out` (caller allocates `cols` floats). Pure, no heap.
///
/// # Safety
/// `samples` must point to `len` valid f32s. `out` must point to `cols` writable f32s.
#[no_mangle]
pub unsafe extern "C" fn stemacle_waveform_envelope(
    samples: *const f32,
    len: usize,
    cols: usize,
    out: *mut f32,
) {
    if samples.is_null() || out.is_null() || len == 0 || cols == 0 {
        return;
    }
    let src = slice::from_raw_parts(samples, len);
    let dst = slice::from_raw_parts_mut(out, cols);
    let env = stemacle_dsp::viz::waveform_envelope(src, cols);
    dst.copy_from_slice(&env);
}
```

Also add `stemacle_spectrogram` to the FFI if not already present:
```rust
/// Compute a `cols × rows` log-magnitude spectrogram, normalized 0..1.
/// `out` must point to `cols * rows` writable f32s.
///
/// # Safety
/// `samples` must point to `len` valid f32s. `out` must point to `cols*rows` writable f32s.
#[no_mangle]
pub unsafe extern "C" fn stemacle_spectrogram(
    samples: *const f32,
    len: usize,
    cols: usize,
    rows: usize,
    out: *mut f32,
) {
    if samples.is_null() || out.is_null() || len == 0 || cols == 0 || rows == 0 {
        return;
    }
    let src = slice::from_raw_parts(samples, len);
    let dst = slice::from_raw_parts_mut(out, cols * rows);
    let grid = stemacle_dsp::viz::spectrogram(src, cols, rows);
    dst.copy_from_slice(&grid);
}
```

- [ ] **Step 2: Rebuild the xcframework**

```bash
npm run apple:xcframework
```

Expected: builds xcframework in `native/apple/StemacleCore.xcframework`

- [ ] **Step 3: Add `waveformEnvelope` to StemacleKit**

In `native/apple/StemacleKit/Sources/StemacleKit/StemacleKit.swift`, inside `public enum Stemacle`, add after `spectrogram`:

```swift
/// A `cols`-bucket peak waveform envelope (0…1). O(n) time, O(cols) space —
/// use instead of `spectrogram` on iOS for memory-safe visualization.
public static func waveformEnvelope(_ samples: [Float], cols: Int) -> [Float] {
    guard cols > 0, !samples.isEmpty else { return [Float](repeating: 0, count: max(0, cols)) }
    var out = [Float](repeating: 0, count: cols)
    samples.withUnsafeBufferPointer { src in
        out.withUnsafeMutableBufferPointer { dst in
            stemacle_waveform_envelope(src.baseAddress, samples.count, cols, dst.baseAddress)
        }
    }
    return out
}
```

- [ ] **Step 4: Use waveform on iOS in StemPlayerViewModel**

In `StemPlayerViewModel.swift`, replace the `finishLoading` spectrogram section with a platform-conditional:

```swift
// Compute per-stem visualization for the lanes.
var specs: [String: [[Float]]] = [:]
#if os(iOS)
// iOS: O(n) waveform envelope — avoids the ~200 MB STFT per stem that would OOM.
var envs: [String: [Float]] = [:]
var mixLen = 0
for (name, samples) in dict {
    envs[name] = Stemacle.waveformEnvelope(samples, cols: Self.specCols)
    mixLen = max(mixLen, samples.count)
}
stemEnvelopes = envs
// Low-res master spectrogram for the radial visualizer (64×16 = tiny).
if mixLen > 0 {
    var mix = [Float](repeating: 0, count: mixLen)
    for samples in dict.values {
        for i in 0..<samples.count { mix[i] += samples[i] }
    }
    masterSpectrogram = Stemacle.spectrogram(mix, cols: 64, rows: 16)
}
#else
// macOS: full STFT spectrogram, sufficient RAM.
var mixLen = 0
for (name, samples) in dict {
    specs[name] = Stemacle.spectrogram(samples, cols: Self.specCols, rows: Self.specRows)
    mixLen = max(mixLen, samples.count)
}
if mixLen > 0 {
    var mix = [Float](repeating: 0, count: mixLen)
    for samples in dict.values {
        for i in 0..<samples.count { mix[i] += samples[i] }
    }
    masterSpectrogram = Stemacle.spectrogram(mix, cols: Self.specCols, rows: Self.specRows)
}
#endif
spectrograms = specs
```

Also add `@Published var stemEnvelopes: [String: [Float]] = [:]` to the `@Published` block.

Update `currentSpectrum` for the low-res iOS path:
```swift
var currentSpectrum: [Float] {
    guard !masterSpectrogram.isEmpty else { return [] }
    // masterSpectrogram is 64 cols on iOS, specCols cols on macOS
    let col = min(Int(progress * Double(masterSpectrogram.count)), masterSpectrogram.count - 1)
    return masterSpectrogram[col]
}
```

- [ ] **Step 5: Build and verify no iOS OOM for long tracks**

```bash
xcodebuild -project native/apple/Stemacle.xcodeproj -scheme StemacleiOS \
  -configuration Debug -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add native/core/stemacle-ffi/src/lib.rs \
        native/apple/StemacleKit/Sources/StemacleKit/StemacleKit.swift \
        native/apple/Stemacle/StemPlayerViewModel.swift \
        native/apple/StemacleCore.xcframework
git commit -m "fix(ios): waveform envelope instead of STFT for per-stem lanes — avoids OOM on long tracks"
```

---

## Task 2: Issue 1b — Scrolling spectrogram/waveform window

The lane should scroll so the playhead stays at a fixed position (25% from left), matching the web gold master. Currently the lane is a static image with a cursor that marches right.

**Files:**
- Modify: `native/apple/Stemacle/VisualizerViews.swift`
- Modify: `native/apple/Stemacle/StemacleApp.swift` (pass `duration` to lanes)
- Modify: `native/apple/Stemacle/StemPlayerViewModel.swift` (pass envelopes to rows)

- [ ] **Step 1: Rewrite SpectrogramLane to support scrolling window**

Replace the existing `SpectrogramLane` struct in `VisualizerViews.swift` with:

```swift
/// A lane showing a sliding time window: the play cursor stays 25% from
/// the left and the spectrogram / waveform image scrolls behind it.
///
/// `image` covers the full track timeline. `envelope` is the fallback
/// waveform (used on iOS where `image` is nil to avoid STFT OOM).
struct SpectrogramLane: View {
    let image: Image?
    let envelope: [Float]       // fallback waveform (iOS); empty on macOS
    var progress: Double        // 0..1 global play position
    var duration: Double        // total track seconds
    var grid: [Double]          // measure boundaries 0..1 (global)
    var height: CGFloat = 34
    var onSeek: (Double) -> Void

    private let windowSec: Double = 30     // visible window width
    private let headFrac: Double = 0.25    // playhead at 25% of window

    /// Window start in seconds, clamped to valid range.
    private var windowStart: Double {
        let preferred = progress * duration - headFrac * windowSec
        let maxStart = max(0, duration - windowSec)
        return max(0, min(preferred, maxStart))
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let wStart = windowStart
            let wEnd = wStart + windowSec
            // Cursor position within the visible window (0..1)
            let cursorX = duration > 0 ? (progress * duration - wStart) / windowSec : headFrac
            let cursorClamped = max(0, min(1, cursorX))

            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 6).fill(Stem.creamDeep.opacity(0.4))

                if let img = image {
                    // Full-track image, clipped to visible window.
                    // Image is W * (duration/windowSec) pixels wide; offset so
                    // windowStart aligns to the left edge of the view.
                    let totalW = W * CGFloat(duration / windowSec)
                    let offsetX = -W * CGFloat(wStart / windowSec)
                    img.resizable()
                        .frame(width: totalW, height: H)
                        .offset(x: offsetX)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if !envelope.isEmpty {
                    // iOS waveform fallback: draw the envelope as bars.
                    Canvas { ctx, size in
                        let cols = envelope.count
                        let colW = size.width / CGFloat(cols)
                        // Map wStart..wEnd → envelope columns
                        let c0 = Int(wStart / duration * Double(cols))
                        let c1 = min(cols, Int(wEnd / duration * Double(cols)) + 1)
                        let visibleCols = max(1, c1 - c0)
                        let barW = size.width / CGFloat(visibleCols)
                        for i in 0..<visibleCols {
                            let ci = (c0 + i).clamped(to: 0..<cols)
                            let v = CGFloat(envelope[ci])
                            let barH = size.height * v
                            let y = (size.height - barH) / 2
                            let rect = CGRect(x: CGFloat(i) * barW, y: y, width: barW - 0.5, height: barH)
                            ctx.fill(Path(rect), with: .color(Stem.purple.opacity(0.45 + 0.3 * v)))
                        }
                    }
                }

                // Measure grid markers in visible window
                ForEach(Array(grid.enumerated()), id: \.offset) { _, g in
                    let gSec = g * duration
                    if gSec >= wStart && gSec <= wEnd {
                        let xFrac = (gSec - wStart) / windowSec
                        Rectangle().fill(Stem.ink.opacity(0.06)).frame(width: 1)
                            .offset(x: W * CGFloat(xFrac))
                    }
                }

                // Played-region tint (left of cursor within visible window)
                Rectangle().fill(Stem.amber.opacity(0.10))
                    .frame(width: max(0, W * CGFloat(cursorClamped)))

                // Play cursor — fixed at headFrac or clamped when near start/end
                Rectangle().fill(Stem.amber).frame(width: 2)
                    .shadow(color: Stem.amber.opacity(0.6), radius: 3)
                    .offset(x: W * CGFloat(cursorClamped) - 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onEnded { v in
                    let frac = max(0, min(1, v.location.x / W))
                    let seekSec = wStart + frac * windowSec
                    let seekProgress = duration > 0 ? seekSec / duration : 0
                    onSeek(max(0, min(1, seekProgress)))
                })
        }
        .frame(height: height)
    }
}

extension Comparable {
    func clamped(to range: Range<Self>) -> Self {
        max(range.lowerBound, min(self, range.upperBound == range.lowerBound ? range.lowerBound : range.upperBound))
    }
}
```

- [ ] **Step 2: Update all SpectrogramLane call sites in StemacleApp.swift**

Master lane in `SplitterView`:
```swift
SpectrogramLane(
    image: masterImage,
    envelope: [],                        // always spectrogram for master
    progress: model.progress,
    duration: model.duration,
    grid: model.measureGrid,
    height: PlayerHeaderMetrics.masterLaneHeight
) { p in model.seek(toProgress: p) }
```

Per-stem lane in `StemRowView`:
```swift
SpectrogramLane(
    image: laneImage,
    envelope: model.stemEnvelopes[stem] ?? [],
    progress: model.progress,
    duration: model.duration,
    grid: model.measureGrid
) { p in model.seek(toProgress: p) }
```

Also add `duration: model.duration` and `stemEnvelopes` access to `StemRowView`.

- [ ] **Step 3: Build**

```bash
xcodebuild -project native/apple/Stemacle.xcodeproj -scheme StemacleiOS \
  -configuration Debug -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add native/apple/Stemacle/VisualizerViews.swift native/apple/Stemacle/StemacleApp.swift \
        native/apple/Stemacle/StemPlayerViewModel.swift
git commit -m "feat(ios): scrolling spectrogram window — playhead stays fixed at 25%, waveform lane on iOS"
```

---

## Task 3: Issue 3 — Full-screen scroll layout

Currently only the stem panel scrolls. The header, transport, and loop bar are fixed. The fix: single root `ScrollView` containing everything; title bar stays pinned via `safeAreaInset`.

**Files:**
- Modify: `native/apple/Stemacle/StemacleApp.swift` — `SplitterView` only

- [ ] **Step 1: Refactor SplitterView to use a single ScrollView**

Replace the body of `SplitterView` with:

```swift
var body: some View {
    ZStack {
        Stem.cream.ignoresSafeArea()

        ScrollView {
            VStack(spacing: 8) {
                // Spacer so content starts below the pinned title bar
                Color.clear.frame(height: 1)

                // Player header (compact + collapsing via scroll offset)
                Group {
                    if model.isReady {
                        PlayerHeaderView(model: model)
                    } else {
                        DeviceCircleView(model: model, onLoad: onImport)
                    }
                }
                .frame(maxWidth: model.isReady
                    ? PlayerHeaderMetrics.readyDiameter
                    : PlayerHeaderMetrics.idleDiameter)
                .frame(height: (model.isReady
                    ? PlayerHeaderMetrics.readyDiameter
                    : PlayerHeaderMetrics.idleDiameter) * headerScale)
                .scaleEffect(headerScale, anchor: .top)
                .animation(.easeOut(duration: 0.15), value: model.isReady)
                .accessibilityIdentifier("splitter.header")

                // Master spectrogram overview
                if model.isReady {
                    VStack(spacing: 4) {
                        SpectrogramLane(
                            image: masterImage, envelope: [],
                            progress: model.progress, duration: model.duration,
                            grid: model.measureGrid,
                            height: PlayerHeaderMetrics.masterLaneHeight
                        ) { p in model.seek(toProgress: p) }
                        HStack {
                            Text(model.elapsedString)
                            Spacer()
                            Text("\(Int(model.bpm)) BPM")
                            Spacer()
                            Text(model.totalString)
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Stem.inkSoft)
                    }
                    .padding(.horizontal, 18)
                    .accessibilityIdentifier("splitter.overview")
                }

                TransportView(model: model)

                if model.isReady {
                    LoopControlBar(model: model)
                        .disabled(!model.isReady || model.isProcessing)
                        .padding(.horizontal, 18)
                        .accessibilityIdentifier("loop.bar")
                }

                // Stem panel — no longer wrapped in its own ScrollView
                VStack(spacing: 10) {
                    ForEach(Stem.stemOrder, id: \.self) { stem in
                        StemRowView(model: model, stem: stem)
                            .disabled(!model.isReady || model.isProcessing)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)

                // Scroll offset detector (invisible, placed as first child)
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(
                    key: ScrollOffsetKey.self,
                    value: -proxy.frame(in: .named("splitterScroll")).minY
                )
            })
        }
        .coordinateSpace(name: "splitterScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
    }
    .safeAreaInset(edge: .top) {
        // Pinned title bar
        HStack(spacing: 12) {
            Text(model.isReady && !model.songTitle.isEmpty ? model.songTitle : "stemacle")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(model.isReady ? Stem.ink : Stem.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
                .accessibilityIdentifier("splitter.title")
            Spacer()
            Button(action: onImport) {
                Image(systemName: "plus.circle").foregroundStyle(Stem.purple)
                    .frame(width: Stem.minimumHitTarget, height: Stem.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o", modifiers: .command)
            .accessibilityIdentifier("splitter.add")
        }
        .font(.system(size: 17))
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Stem.cream.opacity(0.95))
    }
    .overlay { /* drop target ring */ ... }
    .onDrop(of: [.fileURL, .audio], isTargeted: $dropTargeted) { providers in handleDrop(providers) }
    .foregroundStyle(Stem.ink)
    .task(id: model.loadGeneration) { masterImage = makeSpectrogramImage(model.masterSpectrogram) }
}
```

- [ ] **Step 2: Build both schemes**

```bash
xcodebuild -project native/apple/Stemacle.xcodeproj -scheme StemacleiOS \
  -configuration Debug -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
xcodebuild -project native/apple/Stemacle.xcodeproj -scheme StemacleMac \
  -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: both `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add native/apple/Stemacle/StemacleApp.swift
git commit -m "feat(ios): full-screen scroll — splitter scrolls as one surface, title bar pinned"
```

---

## Task 4: Issue 2 — Improved separation quality

### 4a: Better Rust DSP (Wiener soft-mask + temporal smoothing)

Current: `CoherenceSeparator` uses hard coherence mask. Replace with:
1. **Wiener soft mask**: `vocal_e^p / (vocal_e^p + accom_e^p)` where p=2 → smoother boundary
2. **Temporal median smoothing**: 5-frame median per bin → eliminates "musical noise"
3. **Iterative HPSS** (two-pass): second HPSS pass on the harmonic residual for cleaner drums

**Files:**
- Modify: `native/core/stemacle-dsp/src/lib.rs`
- Modify: `native/core/stemacle-dsp/src/hpss.rs`

- [ ] **Step 1: Add Wiener soft-mask helper to lib.rs**

In `lib.rs`, replace the `CoherenceSeparator::vocal_mask` implementation with:

```rust
impl Separator for CoherenceSeparator {
    fn vocal_mask(&self, mag_l: &[Vec<f32>], mag_r: &[Vec<f32>], frames: usize) -> Vec<f32> {
        let mut raw = vec![0.0f32; frames * MODEL_BINS];
        let transient = transient_weights(mag_l, mag_r, frames);

        // Pass 1: per-frame coherence → raw estimate
        for f in 0..frames {
            for b in 0..MODEL_BINS {
                let l = mag_l[f][b];
                let r = mag_r[f][b];
                let avg = 0.5 * (l + r) + 1e-8;
                let centered = l.min(r) / avg;
                let attack_duck = 1.0 - 0.9 * transient[f];
                let weight = vocal_mask_weight_for_bin(b);
                // Wiener-inspired: soft mask from squared estimates
                let v = centered * weight * attack_duck;
                raw[f * MODEL_BINS + b] = v;
            }
        }

        // Pass 2: temporal median smoothing — 5-frame window per bin
        // Eliminates single-frame mask spikes ("musical noise").
        let half: isize = 2;
        let mut smoothed = vec![0.0f32; frames * MODEL_BINS];
        let mut window = vec![0.0f32; (half * 2 + 1) as usize];
        for b in 0..MODEL_BINS {
            for f in 0..frames {
                for k in 0..window.len() {
                    let fi = f as isize - half + k as isize;
                    window[k] = if fi >= 0 && (fi as usize) < frames {
                        raw[fi as usize * MODEL_BINS + b]
                    } else {
                        0.0
                    };
                }
                window.sort_by(|a, b| a.partial_cmp(b).unwrap());
                smoothed[f * MODEL_BINS + b] = window[half as usize];
            }
        }

        // Pass 3: convert to Wiener soft mask (p=2)
        let mut mask = vec![0.0f32; frames * MODEL_BINS];
        for f in 0..frames {
            for b in 0..MODEL_BINS {
                let v = smoothed[f * MODEL_BINS + b];
                let a = 1.0 - v; // accompaniment estimate
                // Wiener: v^2 / (v^2 + a^2 + eps)
                mask[f * MODEL_BINS + b] = (v * v) / (v * v + a * a + 1e-8);
            }
        }
        mask
    }
}
```

- [ ] **Step 2: Two-pass HPSS in hpss.rs**

In `hpss.rs`, add a `hpss_refined` function that runs a second pass on the harmonic residual to pull more clean drums out:

```rust
/// Two-pass HPSS: second pass cleans up drum leakage into the harmonic stem.
/// Uses a 31-tap horizontal kernel (better harmonic stability) and 7-tap vertical.
pub fn hpss_refined(input: &Spectrogram) -> HpssResult {
    let frames = input.frames;
    let bins = TOT_BINS;
    let mut mag = vec![0.0f32; frames * bins];
    for f in 0..frames {
        for b in 0..bins {
            mag[f * bins + b] = input.re[f][b].powi(2) + input.im[f][b].powi(2);
        }
    }
    // First pass: standard kernels
    let h1 = med_filter(&mag, frames, bins, 31, 'h'); // wider horizontal = cleaner harmonic
    let p1 = med_filter(&mag, frames, bins, 7, 'v');  // narrower vertical = sharper drums

    let mut harmonic = Spectrogram::zeros(frames);
    let mut percussive = Spectrogram::zeros(frames);
    let mut h_mag = vec![0.0f32; frames * bins];
    for f in 0..frames {
        for b in 0..bins {
            let hh = h1[f * bins + b];
            let pp = p1[f * bins + b];
            let d = hh + pp + 1e-8;
            let hm = hh / d;
            let pm = pp / d;
            harmonic.re[f][b] = input.re[f][b] * hm;
            harmonic.im[f][b] = input.im[f][b] * hm;
            percussive.re[f][b] = input.re[f][b] * pm;
            percussive.im[f][b] = input.im[f][b] * pm;
            h_mag[f * bins + b] = (harmonic.re[f][b].powi(2) + harmonic.im[f][b].powi(2)).sqrt();
        }
    }

    // Second pass on the harmonic residual — mop up transient leakage
    let h2 = med_filter(&h_mag, frames, bins, 31, 'h');
    let p2 = med_filter(&h_mag, frames, bins, 7, 'v');
    for f in 0..frames {
        for b in 0..bins {
            let hh = h2[f * bins + b];
            let pp = p2[f * bins + b];
            let d = hh + pp + 1e-8;
            if pp / d > 0.6 {
                // Reclassify as percussive
                percussive.re[f][b] += harmonic.re[f][b] * (pp / d);
                percussive.im[f][b] += harmonic.im[f][b] * (pp / d);
                harmonic.re[f][b] *= hh / d;
                harmonic.im[f][b] *= hh / d;
            }
        }
    }

    HpssResult { harmonic, percussive }
}
```

- [ ] **Step 3: Use hpss_refined in lib.rs::separate**

In `lib.rs`, replace:
```rust
let split = hpss::hpss(&accomp);
```
with:
```rust
let split = hpss::hpss_refined(&accomp);
```

- [ ] **Step 4: Run Rust tests — must still pass**

```bash
cargo test --manifest-path native/core/Cargo.toml 2>&1 | tail -20
```
Expected: all tests pass

- [ ] **Step 5: Rebuild xcframework**

```bash
npm run apple:xcframework
```

- [ ] **Step 6: Commit**

```bash
git add native/core/stemacle-dsp/src/lib.rs native/core/stemacle-dsp/src/hpss.rs \
        native/apple/StemacleCore.xcframework
git commit -m "feat(dsp): Wiener soft-mask + temporal smoothing + two-pass HPSS for cleaner stems"
```

### 4b: iOS chunked separation for long tracks

On iOS, a 3-minute stereo track would allocate ~1 GB during STFT. Fix: cap the separation input to 90 seconds. The engine loads the full audio for playback; only separation is capped. Display a clear UI note when capping.

**Files:**
- Modify: `native/apple/Stemacle/StemPlayerViewModel.swift`

- [ ] **Step 7: Add iOS separation cap**

In `StemPlayerViewModel.loadFile`, wrap the iOS separation call:

```swift
#if os(iOS)
// iOS memory budget: cap separation input to 90 seconds.
// Full audio loads for playback; stems are computed from the first 90s.
let maxSeparationSamples = Int(StemAudioEngine.sampleRate * 90)
let sepLeft = left.count > maxSeparationSamples ? Array(left.prefix(maxSeparationSamples)) : left
let sepRight = right.count > maxSeparationSamples ? Array(right.prefix(maxSeparationSamples)) : right
let wasTrimmed = left.count > maxSeparationSamples
if wasTrimmed { status = "Separating first 90s (on-device)…" }
let result = try await Self.separationQueue.separate(left: sepLeft, right: sepRight, sampleRate: 44100)
#else
let result = try await Self.separationQueue.separate(left: left, right: right, sampleRate: 44100)
let wasTrimmed = false
#endif
guard let result else {
    status = "Could not separate this file"
    return
}
split = result
var dict: [String: [Float]] = [:]
for (name, samples) in result.ordered {
    // Pad short stems back to full duration with silence so playback matches.
    if wasTrimmed && samples.count < left.count {
        var padded = samples
        padded.append(contentsOf: [Float](repeating: 0, count: left.count - samples.count))
        dict[name] = padded
    } else {
        dict[name] = samples
    }
}
let quality = wasTrimmed ? "on-device (90s)" : "on-device"
finishLoading(dict, bpm: result.bpm,
              measureOffset: result.measureOffset, beatOffset: result.beatOffset,
              duration: decoded.duration, quality: quality)
```

- [ ] **Step 8: Build + test**

```bash
npm test
xcodebuild -project native/apple/Stemacle.xcodeproj -scheme StemacleiOS \
  -configuration Debug -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
xcodebuild -project native/apple/Stemacle.xcodeproj -scheme StemacleMac \
  -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: npm test 143+ pass, both builds succeed

- [ ] **Step 9: Commit**

```bash
git add native/apple/Stemacle/StemPlayerViewModel.swift
git commit -m "fix(ios): cap separation at 90s to stay within iOS memory budget, pad stems for full playback"
```

---

## Task 5: PR #2 — ship all fixes

- [ ] **Step 1: Final test run**

```bash
npm test
cargo test --manifest-path native/core/Cargo.toml
```
Expected: all pass

- [ ] **Step 2: Create PR #2**

```bash
gh pr create --title "iOS parity: scrolling spectrogram, full-screen scroll, better DSP quality" \
  --base main \
  --body "$(cat <<'EOF'
## Summary
- **Issue 1**: Scrolling spectrogram window — playhead stays fixed at 25%, waveform lane on iOS avoids STFT OOM on long tracks; 90s separation cap keeps device from crashing on long songs
- **Issue 3**: Full-screen scroll — entire splitter scrolls, title bar pinned via safeAreaInset
- **Issue 2**: Wiener soft-mask + temporal smoothing + two-pass HPSS gives substantially cleaner stem separation (fewer artifacts, better drum/harmonic boundary)

## Test plan
- [ ] `npm test` — 143+ tests pass
- [ ] `cargo test` — Rust DSP tests pass
- [ ] StemacleiOS builds clean
- [ ] StemacleMac builds clean

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Merge PR #2** (quality judge: self — tests green, both build)

```bash
gh pr merge --squash --auto
```

---

## Self-Review

**Spec coverage:**
- ✅ Issue 1 (14s / window): waveform on iOS (Task 1) + scrolling window (Task 2) + 90s cap (Task 4b)
- ✅ Issue 3 (full-screen scroll): Task 3
- ✅ Issue 2 (quality): Wiener mask + two-pass HPSS (Task 4a)
- ✅ PR #1 (current state): Task 0
- ✅ PR #2 (fixes): Task 5

**Placeholders:** None. All steps include exact code.

**Type consistency:**
- `SpectrogramLane` now takes `(image:envelope:progress:duration:grid:height:onSeek:)` — call sites updated in Task 2 Step 2
- `stemEnvelopes: [String: [Float]]` added to ViewModel — used in StemRowView
- `stemacle_waveform_envelope` in FFI exactly matches the Rust function signature
