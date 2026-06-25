import AVFoundation
import Combine
import Foundation
import StemacleKit

/// Drives the Stemacle player UI: decodes a file, runs separation on the shared
/// Rust core, and exposes transport + per-stem state to SwiftUI.
@MainActor
final class StemPlayerViewModel: ObservableObject {
    let stems = ["drums", "vocals", "bass", "melody"]

    @Published var status: String = "Drop or choose a track"
    @Published var songTitle: String = ""
    @Published var isProcessing = false
    /// Separation progress 0...1 (server jobs); nil when indeterminate.
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

    /// Install separated stems (shared by the server + on-device paths).
    /// Fresh splits are persisted to the Library; cache re-opens pass persist:false.
    private func finishLoading(_ dict: [String: [Float]], bpm: Float,
                              measureOffset: Float, beatOffset: Float, quality: String,
                              persist: Bool = true) {
        self.bpm = bpm
        self.measureOffset = measureOffset
        self.beatOffset = beatOffset
        // reset loop state on new file (invariant)
        loopBars.removeAll(); allLoopBars = nil
        engine.load(stems: dict)
        duration = engine.durationSeconds
        if persist {
            library?.add(title: songTitle, stems: dict, sampleRate: Int(StemAudioEngine.sampleRate),
                         bpm: bpm, measureOffset: measureOffset, beatOffset: beatOffset,
                         duration: engine.durationSeconds, quality: quality)
        }
        // Compute per-stem spectrograms for the lanes.
        var specs: [String: [[Float]]] = [:]
        var mixLen = 0
        for (name, samples) in dict {
            specs[name] = Stemacle.spectrogram(samples, cols: Self.specCols, rows: Self.specRows)
            mixLen = max(mixLen, samples.count)
        }
        spectrograms = specs
        // Master spectrogram from the summed mix for the radial visualizer.
        if mixLen > 0 {
            var mix = [Float](repeating: 0, count: mixLen)
            for samples in dict.values {
                for i in 0..<samples.count { mix[i] += samples[i] }
            }
            masterSpectrogram = Stemacle.spectrogram(mix, cols: Self.specCols, rows: Self.specRows)
        }
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
                      beatOffset: project.beatOffset, quality: project.quality, persist: false)
    }

    /// Spectrum column (row values 0...1) at the current play head, for the
    /// radial visualizer. Falls back to an empty spectrum.
    var currentSpectrum: [Float] {
        guard !masterSpectrogram.isEmpty else { return [] }
        return masterSpectrogram[min(playColumn, masterSpectrogram.count - 1)]
    }

    /// Decode `url` to 44.1 kHz stereo, separate on the Rust core, load the engine.
    func loadFile(_ url: URL) async {
        isProcessing = true
        isReady = false
        splitProgress = nil
        songTitle = url.deletingPathExtension().lastPathComponent
        status = "Decoding…"
        defer { isProcessing = false; splitProgress = nil }

        do {
            let (left, right) = try decodeStereo44k(url)

            // Prefer the high-quality htdemucs queue server when configured;
            // fall back to the on-device DSP core if it's unreachable or fails.
            if let server = StemServerClient.configured() {
                do {
                    status = "Splitting in the background (htdemucs)…"
                    splitProgress = 0
                    let jobID = try await server.submit(left: left, right: right, sampleRate: 44100)
                    let stems = try await server.awaitStems(jobID) { p in
                        self.splitProgress = p
                        self.status = "Splitting… \(Int(p * 100))%"
                    }
                    let t = Stemacle.separate(left: left, right: right, sampleRate: 44100)
                    finishLoading(stems, bpm: t?.bpm ?? 120,
                                  measureOffset: t?.measureOffset ?? 0, beatOffset: t?.beatOffset ?? 0,
                                  quality: "htdemucs")
                    return
                } catch {
                    splitProgress = nil
                    status = "Server unavailable, splitting on-device…"
                }
            }

            status = isProcessing ? status : "Separating…"
            // Hop heavy work off the main actor.
            let result: StemSplit? = await Task.detached(priority: .userInitiated) {
                Stemacle.separate(left: left, right: right, sampleRate: 44100)
            }.value
            guard let result else {
                status = "Could not separate this file"
                return
            }
            split = result
            var dict: [String: [Float]] = [:]
            for (name, samples) in result.ordered { dict[name] = samples }
            finishLoading(dict, bpm: result.bpm,
                          measureOffset: result.measureOffset, beatOffset: result.beatOffset,
                          quality: "on-device")
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
        volumes[stem] = value
        applyMixing()
    }

    func toggleMute(_ stem: String) {
        if muted.contains(stem) { muted.remove(stem) } else { muted.insert(stem) }
        applyMixing()
    }

    func toggleSolo(_ stem: String) {
        if soloed.contains(stem) { soloed.remove(stem) } else { soloed.insert(stem) }
        applyMixing()
    }

    func toggleGlobalMute() { globalMuted.toggle(); applyMixing() }

    func setLoopMonitoring(solo: Bool) { loopAuditionSolo = solo; applyMixing() }

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
        guard let bars else {
            allLoopBars = nil
            for stem in stems { loopBars[stem] = nil; engine.setLoop(stem, range: nil) }
            applyMixing()
            return
        }
        guard let win = loopWindow(bars: bars) else {
            status = "Loop won't fit before the end"
            return
        }
        allLoopBars = bars
        for stem in stems { loopBars[stem] = bars; engine.setLoop(stem, range: win) }
        applyMixing()
    }

    private func applyMixing() {
        engine.applyMixing(volumes: volumes, muted: muted, soloed: soloed,
                           globalMuted: globalMuted, auditionSolo: loopAuditionSolo)
    }

    // MARK: Decoding

    /// Decode any AVFoundation-readable file to two 44.1 kHz mono Float arrays.
    private func decodeStereo44k(_ url: URL) throws -> (left: [Float], right: [Float]) {
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
        let capacity = AVAudioFrameCount(Double(file.length) * ratio) + 4096
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw NSError(domain: "Stemacle", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Out of memory decoding"])
        }

        var finished = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if finished {
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
                finished = true
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            return buf
        }

        var error: NSError?
        converter.convert(to: out, error: &error, withInputFrom: inputBlock)
        if let error { throw error }

        let n = Int(out.frameLength)
        let chans = out.floatChannelData!
        let left = Array(UnsafeBufferPointer(start: chans[0], count: n))
        let right = target.channelCount > 1
            ? Array(UnsafeBufferPointer(start: chans[1], count: n))
            : left
        return (left, right)
    }
}
