import AVFoundation
import Combine
import Foundation
import StemacleKit

struct DecodedAudio {
    let left: [Float]
    let right: [Float]
    let duration: Double
}

private final class DecodeInputState {
    var finished = false
}

private final class DeviceSeparationQueue {
    private let queue = OperationQueue()

    init() {
        queue.name = "com.stemacle.device-separation"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
    }

    func separate(left: [Float], right: [Float], sampleRate: UInt32) async throws -> StemSplit? {
        try await perform { Stemacle.separate(left: left, right: right, sampleRate: sampleRate) }
    }

    /// Run arbitrary separation work on the serial background queue (keeps heavy
    /// DSP / ONNX inference off the main actor, one window at a time).
    func perform<T>(_ work: @escaping () -> T) async throws -> T {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            queue.addOperation {
                continuation.resume(returning: work())
            }
        }
    }
}

/// Drives the Stemacle player UI: decodes a file, runs separation on the shared
/// Rust core, and exposes transport + per-stem state to SwiftUI.
@MainActor
final class StemPlayerViewModel: ObservableObject {
    let stems = ["drums", "vocals", "bass", "melody"]

    @Published var status: String = "Drop or choose a track"
    @Published var songTitle: String = ""
    @Published var isProcessing = false
    /// Separation progress 0...1; nil when indeterminate.
    @Published var splitProgress: Double?
    @Published var isReady = false
    @Published var isPlaying = false
    @Published var bpm: Float = 120
    @Published var duration: Double = 0

    @Published var volumes: [String: Float] = [:]
    @Published var muted: Set<String> = []
    @Published var soloed: Set<String> = []
    /// Selected loop length per stem in bars (nil = no loop). Matches LOOP_BARS.
    @Published var loopBars: [String: Float] = [:]
    /// All-row linked loop length in bars (nil = none).
    @Published var allLoopBars: Float?
    /// Persistent global mute (does not reset per-stem volumes).
    @Published var globalMuted = false
    /// Loop monitoring: false = Mix (looped stems play against the mix),
    /// true = Solo (only looped stems are cued).
    @Published var loopAuditionSolo = false

    private var measureOffset: Float = 0
    private var beatOffset: Float = 0

    /// Per-stem spectrogram grids: `spectrograms[stem][col][row]`, 0...1.
    @Published var spectrograms: [String: [[Float]]] = [:]
    /// Per-stem peak+RMS waveforms for iOS (O(n), avoids STFT OOM on long tracks).
    /// High column count so a zoomed scroll window matches the web waveform.
    @Published var stemWaveforms: [String: [(peak: Float, rms: Float)]] = [:]
    /// Master (mix) peak+RMS waveform for the iOS overview lane.
    @Published var masterWaveform: [(peak: Float, rms: Float)] = []
    /// Master (mix) spectrogram for the radial player visualizer.
    @Published var masterSpectrogram: [[Float]] = []
    /// Bumped each load so views can rebuild cached spectrogram images.
    @Published var loadGeneration = 0
    /// Live transport position in seconds (drives play cursors + the visualizer).
    @Published var position: Double = 0

    private let engine = StemAudioEngine()
    private var split: StemSplit?
    private var ticker: Timer?

    #if os(iOS)
    /// On-device separators, best-first: HT-Demucs (direct 4-stem waveforms) →
    /// Spleeter (neural mask) → DSP. Each is nil when its model isn't bundled, so
    /// the app degrades gracefully. Created lazily so model loading only happens
    /// when a track is actually separated.
    private lazy var demucs: DemucsSeparator? = DemucsSeparator()
    private lazy var spleeter: SpleeterSeparator? = SpleeterSeparator()

    /// Tempo/loop grid for a window's stereo mix — the Demucs path needs it
    /// computed separately (it outputs stems directly, not via `separate`).
    private static func windowTempo(_ l: [Float], _ r: [Float]) -> (Float, Float, Float) {
        let n = min(l.count, r.count)
        var mono = [Float](repeating: 0, count: n)
        for k in 0..<n { mono[k] = 0.5 * (l[k] + r[k]) }
        let t = Stemacle.estimateTempo(mono: mono, sampleRate: 44100)
        return (t.bpm, t.measureOffset, t.beatOffset)
    }
    #endif

    /// Set by the app so fresh splits are saved to the Library / stem cache.
    var library: LibraryStore?

    /// Spectrogram resolution for the stem lanes.
    static let specCols = 240
    static let specRows = 48
    /// Waveform column resolution for the iOS peak+RMS lanes. High enough that a
    /// 30 s scroll window over a multi-minute track still renders hundreds of
    /// columns (the web recomputes per-pixel; we precompute dense instead).
    static let waveformCols = 3000

    private static let separationQueue = DeviceSeparationQueue()

    private var controlsEnabled: Bool { isReady && !isProcessing }

    init() {
        for stem in stems { volumes[stem] = 0.8 }
    }

    /// Normalized progress 0...1 for the visualizer/cursor.
    var progress: Double { duration > 0 ? position / duration : 0 }

    /// Per-stem lane cursor progress (0...1). When a stem has an active loop, the
    /// transport position is folded into the loop window (via `audibleStemTime`,
    /// the same helper the web gold master uses) so the playhead oscillates inside
    /// the loop instead of drifting to the end of the track with global transport.
    func laneProgress(for stem: String) -> Double {
        guard duration > 0 else { return 0 }
        guard let win = engine.loopWindow(stem) else { return progress }
        let audible = Stemacle.audibleStemTime(
            transportSec: Float(position),
            loopStart: Float(win.start), loopEnd: Float(win.end),
            active: true, duration: Float(duration)
        )
        return min(1, max(0, Double(audible) / duration))
    }

    /// Master overview cursor progress (0...1). When an All-row linked loop is
    /// active every stem shares one window, so the overview playhead folds into it
    /// (like `laneProgress`) instead of drifting to the end of the track while the
    /// audio loops — otherwise the visible cursor contradicts what you hear.
    var masterProgress: Double {
        guard duration > 0, allLoopBars != nil else { return progress }
        for stem in stems where engine.loopWindow(stem) != nil {
            return laneProgress(for: stem)
        }
        return progress
    }

    /// Normalized x positions (0...1) of 4/4 measure boundaries for lane grid markers.
    var measureGrid: [Double] {
        guard duration > 0, bpm > 0 else { return [] }
        let measure = Double((60.0 / bpm) * 4)
        guard measure > 0.05 else { return [] }
        var out: [Double] = []
        var t = Double(measureOffset)
        while t < duration && out.count < 256 {
            if t >= 0 { out.append(t / duration) }
            t += measure
        }
        return out
    }

    /// The spectrogram column index currently under the play head (0...specCols-1).
    var playColumn: Int {
        guard duration > 0 else { return 0 }
        return min(Self.specCols - 1, Int(progress * Double(Self.specCols)))
    }

    /// Elapsed / total time, formatted m:ss. Folds into the loop during an
    /// All-row loop so the readout tracks the audible position (matches the
    /// overview cursor) instead of the transport drifting to the track end.
    var elapsedString: String { Self.clock(masterProgress * duration) }
    var totalString: String { Self.clock(duration) }
    private static func clock(_ s: Double) -> String {
        let t = Int(s.rounded(.down))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    /// Install separated stems from the on-device path.
    /// Fresh splits are persisted to the Library; cache re-opens pass persist:false.
    private func finishLoading(_ dict: [String: [Float]], bpm: Float,
                              measureOffset: Float, beatOffset: Float, duration: Double, quality: String,
                              persist: Bool = true, limiterGain: Float? = nil) {
        self.bpm = bpm
        self.measureOffset = measureOffset
        self.beatOffset = beatOffset
        // reset loop state on new file (invariant)
        loopBars.removeAll(); allLoopBars = nil
        engine.load(stems: dict, durationSeconds: duration, limiterGain: limiterGain)
        self.duration = engine.durationSeconds
        if persist {
            library?.add(title: songTitle, stems: dict, sampleRate: Int(StemAudioEngine.sampleRate),
                         bpm: bpm, measureOffset: measureOffset, beatOffset: beatOffset,
                         duration: self.duration, quality: quality)
        }
        recomputeVisualization(dict)
        position = 0
        loadGeneration += 1
        isReady = true
        status = "Ready · \(Int(bpm)) BPM · \(quality)"
    }

    /// Rebuild the per-stem lane + overview visualization from a stem dict.
    /// iOS uses a peak+RMS waveform (O(n), O(cols) space) to avoid the ~200 MB
    /// STFT allocation the full spectrogram needs on long tracks; macOS has the
    /// RAM for the full log-magnitude spectrogram. Bumps `loadGeneration` so
    /// cached lane images rebuild (used both by initial load and streaming swap).
    private func recomputeVisualization(_ dict: [String: [Float]]) {
        var mixLen = 0
        for samples in dict.values { mixLen = max(mixLen, samples.count) }
        // Both platforms render the warm log-magnitude spectrogram. It is safe on
        // iOS now because `Stemacle.spectrogram` streams frame-by-frame with
        // bounded memory (it used to materialize the whole STFT and OOM, which is
        // why iOS previously fell back to a plain waveform).
        var specs: [String: [[Float]]] = [:]
        for (name, samples) in dict {
            specs[name] = Stemacle.spectrogram(samples, cols: Self.specCols, rows: Self.specRows)
        }
        spectrograms = specs
        stemWaveforms = [:]
        masterWaveform = []
        if mixLen > 0 {
            var mix = [Float](repeating: 0, count: mixLen)
            for samples in dict.values {
                for i in 0..<samples.count { mix[i] += samples[i] }
            }
            masterSpectrogram = Stemacle.spectrogram(mix, cols: Self.specCols, rows: Self.specRows)
        }
    }

    #if os(iOS)
    /// Suno-style streaming separation. Separates window 0 up front so the user
    /// can play the first part immediately, then fills the remaining windows in
    /// the background and swaps in the completed track — all within a per-window
    /// memory budget (the whole-track STFT would OOM the iOS process). Seams use
    /// the `StreamingChunker` crossfade so they stay click-free.
    private func streamingSeparate(left: [Float], right: [Float], duration: Double) async throws {
        let total = left.count
        let chunker = StreamingChunker(totalSamples: total, sampleRate: StemAudioEngine.sampleRate)
        guard chunker.windowCount > 0 else {
            status = "Could not separate this file"
            return
        }

        // On-device separators, captured best-first. `quality` is finalized from
        // window 0's *actual* engine so the label never overstates what ran.
        let demucs = self.demucs
        let neural = spleeter
        var quality = "on-device"

        // One limiter gain for the whole track, from the decoded input mix (known
        // upfront). Stems partition the mix, so this bounds the stem sum — and
        // applying the *same* gain at window-0 load and the full-track swap means
        // the swap never steps the volume.
        var inputPeak: Float = 0
        let mixN = min(left.count, right.count)
        for i in 0..<mixN { inputPeak = max(inputPeak, abs(0.5 * (left[i] + right[i]))) }
        let limiterGain = StemAudioEngine.limiterGain(forMixPeak: inputPeak)

        // Separate one window [s,e), trying engines best-first: Demucs (direct
        // 4-stem waveforms) → Spleeter (neural mask) → DSP. `needsTempo` (window 0
        // only) computes the loop grid for the Demucs path, which — unlike the
        // DSP/Spleeter split — doesn't return tempo. Returns the engine used.
        func separateWindow(_ i: Int, needsTempo: Bool) async throws
            -> (dict: [String: [Float]], bpm: Float, measureOffset: Float, beatOffset: Float, engine: String)? {
            let (s, e) = chunker.windowRange(i)
            let wl = Array(left[s..<e]); let wr = Array(right[s..<e])
            return try await Self.separationQueue.perform {
                if let demucs, let d = demucs.separate(left: wl, right: wr) {
                    let t = needsTempo ? Self.windowTempo(wl, wr) : (Float(120), Float(0), Float(0))
                    return (d, t.0, t.1, t.2, "demucs")
                }
                let split: StemSplit?
                let engine: String
                if let neural, let n = neural.separate(left: wl, right: wr, sampleRate: 44100) {
                    split = n; engine = "neural"
                } else {
                    split = Stemacle.separate(left: wl, right: wr, sampleRate: 44100)
                    engine = "on-device"
                }
                guard let r = split else { return nil }
                var d: [String: [Float]] = [:]
                for (name, samples) in r.ordered { d[name] = samples }
                return (d, r.bpm, r.measureOffset, r.beatOffset, engine)
            }
        }

        // Full-length accumulators; each window adds its crossfaded contribution.
        var acc: [String: [Float]] = [:]
        for stem in stems { acc[stem] = [Float](repeating: 0, count: total) }

        // --- Window 0: separate, place, load → immediate playback. ---
        status = "Separating (on-device)…"
        guard let first = try await separateWindow(0, needsTempo: true) else {
            status = "Could not separate this file"
            return
        }
        quality = first.engine
        for stem in stems {
            var buf = acc[stem]!
            chunker.accumulate(into: &buf, windowStem: first.dict[stem] ?? [], window: 0)
            acc[stem] = buf
        }
        // Persist only the *completed* full track (persist:false for window 0).
        finishLoading(acc, bpm: first.bpm,
                      measureOffset: first.measureOffset, beatOffset: first.beatOffset,
                      duration: duration, quality: quality, persist: false, limiterGain: limiterGain)

        if chunker.windowCount == 1 {
            library?.add(title: songTitle, stems: acc, sampleRate: Int(StemAudioEngine.sampleRate),
                         bpm: bpm, measureOffset: measureOffset, beatOffset: beatOffset,
                         duration: self.duration, quality: quality)
            return
        }

        status = "Playing first part · finishing separation…"

        // --- Remaining windows in the background; swap in the completed track. ---
        // `loadGeneration` (bumped by every finishLoading) is our cancel token: if
        // a newer file loads while we're working, it changes and we abandon.
        let gen = loadGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            for i in 1..<chunker.windowCount {
                if self.loadGeneration != gen { return }
                guard let w = try? await separateWindow(i, needsTempo: false) else { continue }
                if self.loadGeneration != gen { return }
                for stem in self.stems {
                    var buf = acc[stem]!
                    chunker.accumulate(into: &buf, windowStem: w.dict[stem] ?? [], window: i)
                    acc[stem] = buf
                }
                self.status = "Finishing separation… \(i + 1)/\(chunker.windowCount)"
            }
            if self.loadGeneration != gen { return }
            // Swap the completed full track in without interrupting playback,
            // reusing the window-0 limiter gain so the volume never steps.
            self.engine.replaceStems(acc, limiterGain: limiterGain)
            self.recomputeVisualization(acc)
            self.loadGeneration += 1
            self.library?.add(title: self.songTitle, stems: acc,
                              sampleRate: Int(StemAudioEngine.sampleRate),
                              bpm: self.bpm, measureOffset: self.measureOffset,
                              beatOffset: self.beatOffset, duration: self.duration,
                              quality: quality)
            self.status = "Ready · \(Int(self.bpm)) BPM · \(quality)"
        }
    }
    #endif

    /// Instant re-open from the Library's stem cache — no re-separation.
    func openProject(_ project: Project) {
        guard let dict = library?.stems(for: project) else {
            status = "Cached stems missing"
            return
        }
        stop()
        songTitle = project.title
        isProcessing = false
        finishLoading(dict, bpm: project.bpm, measureOffset: project.measureOffset,
                      beatOffset: project.beatOffset, duration: project.duration,
                      quality: project.quality, persist: false)
    }

    /// Spectrum column (row values 0...1) at the current play head, for the
    /// radial visualizer. Falls back to an empty spectrum.
    var currentSpectrum: [Float] {
        guard !masterSpectrogram.isEmpty else { return [] }
        // masterSpectrogram is 64 cols on iOS, specCols cols on macOS. Uses the
        // folded master position so the radial visualizer tracks an active loop.
        let col = min(Int(masterProgress * Double(masterSpectrogram.count)), masterSpectrogram.count - 1)
        return masterSpectrogram[col]
    }

    /// Decode `url` to 44.1 kHz stereo, separate using the best available *local*
    /// engine, and load the audio engine. Separation is always on-device — audio
    /// is never uploaded (the App Store privacy posture: "your music stays on this
    /// device"). Priority:
    ///   1. htdemucs subprocess – macOS only, when a local Demucs venv is present
    ///      (a local process, no network), for quality that beats the web app.
    ///   2. on-device DSP – CoherenceSeparator (Rust), always-available fallback
    ///      and the only engine on iOS.
    ///
    /// A network separation server (`StemServerClient` / `server/app.py`) exists
    /// for a possible future opt-in (e.g. a Cloudflare-hosted queue) but is
    /// deliberately NOT wired in here, so no build ever uploads audio by default.
    ///
    /// The on-device DSP runs in parallel for BPM/tempo so the loop grid stays
    /// accurate even when the macOS subprocess supplies the high-quality stems.
    func loadFile(_ url: URL) async {
        isProcessing = true
        isReady = false
        splitProgress = nil
        songTitle = url.deletingPathExtension().lastPathComponent
        status = "Decoding…"
        defer { isProcessing = false; splitProgress = nil }

        do {
            let decoded = try decodeStereo44k(url)
            let left = decoded.left
            let right = decoded.right

            // --- Tier 1: htdemucs subprocess (macOS only, local, no network) ---
            #if os(macOS)
            let subprocCfg = SubprocessDemucsConfig.fromEnv()
            if subprocCfg.available() {
                status = "Separating with htdemucs (local)…"
                do {
                    // Run BPM analysis and subprocess in parallel on background threads.
                    async let analysisTask = Self.separationQueue.separate(
                        left: left, right: right, sampleRate: 44100)
                    let subprocStems = try await Task.detached(priority: .userInitiated) {
                        try subprocCfg.separate(left: left, right: right, sampleRate: 44100)
                    }.value
                    let analysis = try? await analysisTask
                    finishLoading(subprocStems,
                                  bpm: analysis?.bpm ?? 120,
                                  measureOffset: analysis?.measureOffset ?? 0,
                                  beatOffset: analysis?.beatOffset ?? 0,
                                  duration: decoded.duration,
                                  quality: subprocCfg.qualityLabel)
                    split = analysis
                    return
                } catch {
                    status = "Local Demucs failed, falling back to on-device…"
                }
            }
            #endif

            // --- Tier 2: on-device DSP (CoherenceSeparator, always available) ---
            #if os(iOS)
            // iOS memory budget: the whole-track STFT peaks ~1 GB and is
            // jetsam-killed. Stream the separation instead — separate the first
            // window immediately so playback can start, then fill the rest in the
            // background (Suno-style), keeping peak memory bounded to one window.
            try await streamingSeparate(left: left, right: right, duration: decoded.duration)
            #else
            status = "Separating (on-device)…"
            let result = try await Self.separationQueue.separate(
                left: left, right: right, sampleRate: 44100)
            guard let result else {
                status = "Could not separate this file"
                return
            }
            split = result
            var dict: [String: [Float]] = [:]
            for (name, samples) in result.ordered { dict[name] = samples }
            finishLoading(dict, bpm: result.bpm,
                          measureOffset: result.measureOffset, beatOffset: result.beatOffset,
                          duration: decoded.duration,
                          quality: "on-device")
            #endif
        } catch {
            status = "Load failed: \(error.localizedDescription)"
        }
    }

    // MARK: Transport

    func togglePlay() {
        guard isReady else { return }
        do {
            if isPlaying {
                engine.pause()
                isPlaying = false
                stopTicker()
            } else {
                try engine.resume()
                applyMixing()
                isPlaying = true
                startTicker()
            }
        } catch {
            status = "Playback error: \(error.localizedDescription)"
        }
    }

    func stop() {
        engine.stop()
        isPlaying = false
        position = 0
        stopTicker()
    }

    /// Seek to a normalized progress (0...1) — used by tapping a spectrogram lane.
    func seek(toProgress p: Double) {
        let t = max(0, min(1, p)) * duration
        engine.seek(to: t)
        position = t
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.position = self.engine.currentTime
                // End of track: no active loop and the head reached the end.
                let hasLoop = !self.loopBars.values.compactMap { $0 }.isEmpty || self.allLoopBars != nil
                if self.isPlaying && !hasLoop && self.duration > 0,
                   self.position >= self.duration - 0.02 {
                    self.engine.stop()
                    self.isPlaying = false
                    self.position = 0
                    self.stopTicker()
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: Per-stem controls

    func setVolume(_ stem: String, _ value: Float) {
        guard controlsEnabled else { return }
        volumes[stem] = value
        applyMixing()
    }

    func toggleMute(_ stem: String) {
        guard controlsEnabled else { return }
        if muted.contains(stem) { muted.remove(stem) } else { muted.insert(stem) }
        applyMixing()
    }

    func toggleSolo(_ stem: String) {
        guard controlsEnabled else { return }
        if soloed.contains(stem) {
            soloed.removeAll()
        } else {
            soloed.removeAll()
            soloed.insert(stem)
        }
        applyMixing()
    }

    func toggleGlobalMute() {
        guard controlsEnabled else { return }
        globalMuted.toggle()
        applyMixing()
    }

    func setLoopMonitoring(solo: Bool) {
        guard controlsEnabled else { return }
        let hasLoop = !loopBars.values.compactMap { $0 }.isEmpty || allLoopBars != nil
        if solo && !hasLoop { return }
        loopAuditionSolo = solo
        applyMixing()
    }

    // MARK: Looping (functional)

    /// Compute the snapped loop window for a length in bars at the current head,
    /// rejecting loops that would spill past the end of the track.
    private func loopWindow(bars: Float) -> (start: Double, end: Double)? {
        let length = bars * Stemacle.measureLength(bpm: bpm)
        let r = Stemacle.loopRange(
            bpm: bpm, measureOffset: measureOffset, beatOffset: beatOffset,
            duration: Float(duration), currentSec: Float(position), loopLength: length
        )
        guard r.fits else { return nil }
        return (Double(r.start), Double(r.end))
    }

    /// Toggle a per-stem loop of `bars` length (nil arg clears).
    func setLoop(_ stem: String, bars: Float?) {
        guard controlsEnabled else { return }
        // Any individual stem edit breaks the All-row linked state, so drop that
        // indicator (mirrors the web `setStemLoop` → `clearAllLoopIndicator`
        // contract). Without this, `allLoopBars` goes stale and the All row
        // claims a linked loop the stems no longer share — verified reachable by
        // tests/loop-state-model.test.mjs.
        allLoopBars = nil
        guard let bars else {
            loopBars[stem] = nil
            engine.setLoop(stem, range: nil)
            applyMixing()
            return
        }
        guard let win = loopWindow(bars: bars) else {
            status = "Loop won't fit before the end"
            return
        }
        loopBars[stem] = bars
        engine.setLoop(stem, range: win)
        applyMixing()
    }

    /// Apply one linked loop across every stem (the All row), or clear all.
    func setAllLoop(bars: Float?) {
        guard controlsEnabled else { return }
        guard let bars else {
            allLoopBars = nil
            var updated = loopBars
            for stem in stems { updated[stem] = nil; engine.setLoop(stem, range: nil) }
            loopBars = updated
            applyMixing()
            return
        }
        guard let win = loopWindow(bars: bars) else {
            status = "Loop won't fit before the end"
            return
        }
        allLoopBars = bars
        var updated = loopBars
        for stem in stems { updated[stem] = bars; engine.setLoop(stem, range: win) }
        loopBars = updated
        applyMixing()
    }

    private func applyMixing() {
        engine.applyMixing(volumes: volumes, muted: muted, soloed: soloed,
                           globalMuted: globalMuted, auditionSolo: loopAuditionSolo)
    }

    // MARK: Decoding

    /// Decode any AVFoundation-readable file to two 44.1 kHz mono Float arrays.
    private func decodeStereo44k(_ url: URL) throws -> DecodedAudio {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: StemAudioEngine.sampleRate,
            channels: 2,
            interleaved: false
        )!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
            throw NSError(domain: "Stemacle", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format"])
        }

        let ratio = target.sampleRate / file.processingFormat.sampleRate
        let estimatedFrames = max(0, Int(Double(file.length) * ratio))
        var left: [Float] = []
        var right: [Float] = []
        left.reserveCapacity(estimatedFrames)
        right.reserveCapacity(estimatedFrames)

        let inputState = DecodeInputState()
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputState.finished {
                outStatus.pointee = .endOfStream
                return nil
            }
            let frames: AVAudioFrameCount = 16384
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)
            else {
                outStatus.pointee = .endOfStream
                return nil
            }
            do {
                try file.read(into: buf)
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
            if buf.frameLength == 0 {
                inputState.finished = true
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            return buf
        }

        conversionLoop: while true {
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 16384) else {
                throw NSError(domain: "Stemacle", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Out of memory decoding"])
            }

            var error: NSError?
            let status = converter.convert(to: out, error: &error, withInputFrom: inputBlock)
            if let error { throw error }

            let n = Int(out.frameLength)
            if n > 0, let chans = out.floatChannelData {
                left.append(contentsOf: UnsafeBufferPointer(start: chans[0], count: n))
                let rightChannel = target.channelCount > 1 ? chans[1] : chans[0]
                right.append(contentsOf: UnsafeBufferPointer(start: rightChannel, count: n))
            }

            switch status {
            case .haveData, .inputRanDry:
                continue
            case .endOfStream:
                break conversionLoop
            case .error:
                throw NSError(domain: "Stemacle", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Could not decode this file"])
            @unknown default:
                break conversionLoop
            }
        }

        let sampleCount = max(left.count, right.count)
        let duration = Double(sampleCount) / StemAudioEngine.sampleRate
        return DecodedAudio(left: left, right: right.isEmpty ? left : right, duration: duration)
    }
}
