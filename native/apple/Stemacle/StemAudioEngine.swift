import AVFoundation
import Foundation
import StemacleKit

/// Four-stem playback engine on `AVAudioEngine`. One `AVAudioPlayerNode` per
/// stem feeds a shared mixer, giving per-stem volume, mute, headphones (solo)
/// isolation, and **independent per-stem looping** — the web app's loop contract.
final class StemAudioEngine {
    static let sampleRate: Double = 44100
    static let outputCeiling: Float = 0.95

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    private var players: [String: AVAudioPlayerNode] = [:]
    private var buffers: [String: AVAudioPCMBuffer] = [:]

    /// Active loop window per stem in seconds, or nil. Independent per stem.
    private var loops: [String: (start: Double, end: Double)] = [:]

    private(set) var isPlaying = false
    private(set) var durationSeconds: Double = 0

    // Transport position tracking for the play cursor.
    private var startDate: Date?
    private var startOffset: Double = 0

    let stems = ["drums", "vocals", "bass", "melody"]

    /// Current global transport position in seconds.
    var currentTime: Double {
        let t = startDate.map { startOffset + Date().timeIntervalSince($0) } ?? startOffset
        return max(0, min(t, durationSeconds))
    }

    init() {
        for stem in stems {
            let node = AVAudioPlayerNode()
            players[stem] = node
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
    }

    /// A `limiterGain` (from the full-track input mix) may be supplied so streaming
    /// window-0 load and the later full-track swap scale identically — otherwise
    /// the per-call dynamic limiter is used (single-shot loads: macOS, cache).
    func load(stems split: [String: [Float]], durationSeconds expectedDuration: Double? = nil,
              limiterGain: Float? = nil) {
        loops.removeAll()  // new file resets loops (invariant)
        let safeSplit = limiterGain.map { Self.cleanedScaled(split, gain: $0) } ?? Self.sanitizedStems(split)
        var maxFrames = 0
        for stem in stems {
            guard let samples = safeSplit[stem], !samples.isEmpty else { continue }
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
            buf.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
            }
            buffers[stem] = buf
            maxFrames = max(maxFrames, samples.count)
        }
        let computedDuration = Double(maxFrames) / Self.sampleRate
        durationSeconds = max(computedDuration, expectedDuration ?? 0)
        startOffset = 0
        startDate = nil
        isPlaying = false
    }

    /// Swap in new full-length stem PCM while preserving the current transport
    /// position and play state — used by streaming separation to replace the
    /// window-0-only audio with the completed track without interrupting
    /// playback. Duration and loops are unchanged (the track length is fixed at
    /// initial load). Content already played (the first window) is identical, so
    /// rescheduling from the current position is seamless.
    func replaceStems(_ split: [String: [Float]], limiterGain: Float) {
        let wasPlaying = isPlaying
        let resumeAt = currentTime
        // Reuse the same per-track gain as the window-0 load so the swap never
        // steps the volume (the dynamic limiter would compute a different gain
        // from the full track than from window 0 alone).
        let safeSplit = Self.cleanedScaled(split, gain: limiterGain)
        for stem in stems {
            guard let samples = safeSplit[stem], !samples.isEmpty else { continue }
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
            buf.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
            }
            buffers[stem] = buf
        }
        if wasPlaying {
            try? play(from: resumeAt)
        }
    }

    func prepare() throws { if !engine.isRunning { try engine.start() } }

    // MARK: Transport

    func play(from offset: Double = 0) throws {
        try prepare()
        for stem in stems { scheduleStem(stem, from: max(0, offset)) }
        startOffset = max(0, offset)
        startDate = Date()
        isPlaying = true
    }

    func resume() throws { try play(from: currentTime) }

    func pause() {
        startOffset = currentTime
        startDate = nil
        for node in players.values { node.stop() }
        isPlaying = false
    }

    func stop() {
        for node in players.values { node.stop() }
        startOffset = 0
        startDate = nil
        isPlaying = false
    }

    func seek(to time: Double) {
        let wasPlaying = isPlaying
        for node in players.values { node.stop() }
        startOffset = max(0, min(time, durationSeconds))
        startDate = nil
        if wasPlaying { try? play(from: startOffset) }
    }

    // MARK: Looping

    /// Set or clear a stem's loop window. When playing, reschedules immediately so
    /// the change is audible. nil clears the loop (stem plays through).
    func setLoop(_ stem: String, range: (start: Double, end: Double)?) {
        if let range { loops[stem] = range } else { loops[stem] = nil }
        if isPlaying { scheduleStem(stem, from: currentTime) }
    }

    func loopWindow(_ stem: String) -> (start: Double, end: Double)? { loops[stem] }

    /// Schedule one stem's node based on its loop state.
    private func scheduleStem(_ stem: String, from offset: Double) {
        guard let node = players[stem], let buf = buffers[stem] else { return }
        node.stop()
        if let loop = loops[stem] {
            let s = Int(loop.start * Self.sampleRate)
            let e = min(Int(loop.end * Self.sampleRate), Int(buf.frameLength))
            guard e > s else { return }
            let audible = Stemacle.audibleStemTime(
                transportSec: Float(offset),
                loopStart: Float(loop.start),
                loopEnd: Float(loop.end),
                active: true,
                duration: Float(durationSeconds)
            )
            let start = min(max(Int(Double(audible) * Self.sampleRate), s), e - 1)
            if start > s {
                node.scheduleBuffer(Self.slice(buf, from: start, to: e), at: nil)
            }
            node.scheduleBuffer(Self.slice(buf, from: s, to: e), at: nil, options: .loops)
        } else {
            let startFrame = Int(offset * Self.sampleRate)
            guard startFrame < Int(buf.frameLength) else { return }
            let seg = startFrame == 0 ? buf : Self.slice(buf, from: startFrame, to: Int(buf.frameLength))
            node.scheduleBuffer(seg, at: nil)
        }
        node.play()
    }

    /// Copy `[from, to)` of a mono buffer into a fresh buffer.
    private static func slice(_ buf: AVAudioPCMBuffer, from: Int, to: Int) -> AVAudioPCMBuffer {
        let count = max(0, to - from)
        let out = AVAudioPCMBuffer(pcmFormat: buf.format, frameCapacity: AVAudioFrameCount(count))!
        out.frameLength = AVAudioFrameCount(count)
        if count > 0 {
            out.floatChannelData![0].update(from: buf.floatChannelData![0] + from, count: count)
        }
        return out
    }

    /// The limiter gain a mix peaking at `peak` needs to stay under the ceiling.
    /// Stems partition the input mix, so the input-mix peak bounds the stem sum —
    /// deriving the gain from the (fully-known) input mix lets streaming apply one
    /// consistent gain across window-0 load and the full-track swap.
    static func limiterGain(forMixPeak peak: Float) -> Float {
        peak > outputCeiling ? outputCeiling / peak : 1
    }

    /// Non-finite cleanup + a fixed limiter gain (no dynamic per-call rescale).
    static func cleanedScaled(_ split: [String: [Float]], gain: Float) -> [String: [Float]] {
        let order = ["drums", "vocals", "bass", "melody"]
        var out: [String: [Float]] = [:]
        for stem in order {
            out[stem] = (split[stem] ?? []).map { $0.isFinite ? $0 * gain : 0 }
        }
        return out
    }

    /// Clean non-finite samples and scale all stems together so a full mix cannot
    /// exceed the output ceiling even when every stem volume is at 1.0.
    private static func sanitizedStems(_ split: [String: [Float]]) -> [String: [Float]] {
        let order = ["drums", "vocals", "bass", "melody"]
        var cleaned: [String: [Float]] = [:]
        var maxFrames = 0
        for stem in order {
            let samples = split[stem] ?? []
            let safe = samples.map { sample -> Float in
                guard sample.isFinite else { return 0 }
                return sample
            }
            cleaned[stem] = safe
            maxFrames = max(maxFrames, safe.count)
        }

        var mixPeak: Float = 0
        for i in 0..<maxFrames {
            var sum: Float = 0
            for stem in order {
                let samples = cleaned[stem] ?? []
                if i < samples.count { sum += samples[i] }
            }
            mixPeak = max(mixPeak, abs(sum))
        }
        guard mixPeak > outputCeiling else { return cleaned }
        let gain = outputCeiling / mixPeak
        for stem in order {
            cleaned[stem] = (cleaned[stem] ?? []).map { $0 * gain }
        }
        return cleaned
    }

    // MARK: Mixing

    /// Apply mute / solo / loop-audition state. `auditionSolo` cues only looped
    /// stems (web Solo mode) without mutating mute; otherwise mute/solo apply.
    /// Volumes are always preserved (persistent global mute invariant).
    func applyMixing(volumes: [String: Float], muted: Set<String>, soloed: Set<String>,
                     globalMuted: Bool, auditionSolo: Bool) {
        let hasLoop = !loops.isEmpty
        let anySolo = !soloed.isEmpty
        for stem in stems {
            let base = volumes[stem] ?? 0.8
            var audible: Bool
            if auditionSolo && hasLoop {
                audible = loops[stem] != nil
            } else if anySolo {
                audible = soloed.contains(stem)
            } else {
                audible = !muted.contains(stem)
            }
            if globalMuted { audible = false }
            players[stem]?.volume = audible ? max(0, min(1, base)) : 0
        }
    }
}
