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
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StemSplit?, Error>) in
            queue.addOperation {
                let result = Stemacle.separate(left: left, right: right, sampleRate: sampleRate)
                continuation.resume(returning: result)
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
    /// Per-stem waveform envelopes for iOS (O(n), avoids STFT OOM on long tracks).
    @Published var stemEnvelopes: [String: [Float]] = [:]
    /// Master (mix) spectrogram for the radial player visualizer.
    @Published var masterSpectrogram: [[Float]] = []
    /// Bumped each load so views can rebuild cached spectrogram images.
    @Published var loadGeneration = 0
    /// Live transport position in seconds (drives play cursors + the visualizer).
    @Published var position: Double = 0

    private let engine = StemAudioEngine()
    private var split: StemSplit?
    private var ticker: Timer?

    /// Set by the app so fresh splits are saved to the Library / stem cache.
    var library: LibraryStore?

    /// Spectrogram resolution for the stem lanes.
    static let specCols = 240
    static let specRows = 48

    private static let separationQueue = DeviceSeparationQueue()

    private var controlsEnabled: Bool { isReady && !isProcessing }

    init() {
        for stem in stems { volumes[stem] = 0.8 }
    }

    /// Normalized progress 0...1 for the visualizer/cursor.
    var progress: Double { duration > 0 ? position / duration : 0 }

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

    /// Elapsed / total time, formatted m:ss.
    var elapsedString: String { Self.clock(position) }
    var totalString: String { Self.clock(duration) }
    private static func clock(_ s: Double) -> String {
        let t = Int(s.rounded(.down))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    /// Install separated stems from the on-device path.
    /// Fresh splits are persisted to the Library; cache re-opens pass persist:false.
    private func finishLoading(_ dict: [String: [Float]], bpm: Float,
                              measureOffset: Float, beatOffset: Float, duration: Double, quality: String,
                              persist: Bool = true) {
        self.bpm = bpm
        self.measureOffset = measureOffset
        self.beatOffset = beatOffset
        // reset loop state on new file (invariant)
        loopBars.removeAll(); allLoopBars = nil
        engine.load(stems: dict, durationSeconds: duration)
        self.duration = engine.durationSeconds
        if persist {
            library?.add(title: songTitle, stems: dict, sampleRate: Int(StemAudioEngine.sampleRate),
                         bpm: bpm, measureOffset: measureOffset, beatOffset: beatOffset,
                         duration: self.duration, quality: quality)
        }
        // Compute per-stem visualization.
        // iOS uses a peak waveform envelope (O(n), O(cols) space) to avoid the
        // ~200 MB STFT allocation that each spectrogram call requires on long tracks.
        // macOS has sufficient RAM for the full log-magnitude spectrogram.
        var mixLen = 0
        for samples in dict.values { mixLen = max(mixLen, samples.count) }
        #if os(iOS)
        var envs: [String: [Float]] = [:]
        for (name, samples) in dict {
            envs[name] = Stemacle.waveformEnvelope(samples, cols: Self.specCols)
        }
        stemEnvelopes = envs
        spectrograms = [:]
        // Low-res master spectrogram (64×16) for the radial visualizer — tiny allocation.
        if mixLen > 0 {
            var mix = [Float](repeating: 0, count: mixLen)
            for samples in dict.values {
                for i in 0..<samples.count { mix[i] += samples[i] }
            }
            masterSpectrogram = Stemacle.spectrogram(mix, cols: 64, rows: 16)
        }
        #else
        var specs: [String: [[Float]]] = [:]
        for (name, samples) in dict {
            specs[name] = Stemacle.spectrogram(samples, cols: Self.specCols, rows: Self.specRows)
        }
        spectrograms = specs
        stemEnvelopes = [:]
        if mixLen > 0 {
            var mix = [Float](repeating: 0, count: mixLen)
            for samples in dict.values {
                for i in 0..<samples.count { mix[i] += samples[i] }
            }
            masterSpectrogram = Stemacle.spectrogram(mix, cols: Self.specCols, rows: Self.specRows)
        }
        #endif
        position = 0
        loadGeneration += 1
        isReady = true
        status = "Ready · \(Int(bpm)) BPM · \(quality)"
    }

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
        // masterSpectrogram is 64 cols on iOS, specCols cols on macOS
        let col = min(Int(progress * Double(masterSpectrogram.count)), masterSpectrogram.count - 1)
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
            // iOS memory budget: the Rust STFT allocates ~200 MB per stereo
            // spectrogram; a 3-minute track peaks at ~1 GB and crashes.
            // Cap the separation input to 90 seconds; silence-pad stems back
            // to the full duration so playback length is always correct.
            #if os(iOS)
            let maxSepSamples = Int(StemAudioEngine.sampleRate * 90)
            let wasTrimmed = left.count > maxSepSamples
            let sepLeft  = wasTrimmed ? Array(left.prefix(maxSepSamples))  : left
            let sepRight = wasTrimmed ? Array(right.prefix(maxSepSamples)) : right
            if wasTrimmed { status = "Separating first 90s (on-device)…" } else {
                status = "Separating (on-device)…"
            }
            #else
            let sepLeft = left; let sepRight = right; let wasTrimmed = false
            status = "Separating (on-device)…"
            #endif

            let result = try await Self.separationQueue.separate(
                left: sepLeft, right: sepRight, sampleRate: 44100)
            guard let result else {
                status = "Could not separate this file"
                return
            }
            split = result
            var dict: [String: [Float]] = [:]
            let fullLen = left.count
            for (name, samples) in result.ordered {
                if wasTrimmed && samples.count < fullLen {
                    var padded = samples
                    padded.append(contentsOf: [Float](repeating: 0, count: fullLen - samples.count))
                    dict[name] = padded
                } else {
                    dict[name] = samples
                }
            }
            let quality = wasTrimmed ? "on-device (90s)" : "on-device"
            finishLoading(dict, bpm: result.bpm,
                          measureOffset: result.measureOffset, beatOffset: result.beatOffset,
                          duration: decoded.duration,
                          quality: quality)
            if wasTrimmed {
                status = "⚠️ Only first 90 seconds separated (device limit). Rest is padded with silence."
            }
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

        let duration = Double(max(left.count, right.count)) / StemAudioEngine.sampleRate
        return DecodedAudio(left: left, right: right.isEmpty ? left : right, duration: duration)
    }
}
