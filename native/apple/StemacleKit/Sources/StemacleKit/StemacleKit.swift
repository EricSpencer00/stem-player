import Foundation
import StemacleCore

/// The four Stemacle stems plus the detected tempo grid, as Swift-native arrays.
public struct StemSplit: Sendable {
    public let drums: [Float]
    public let vocals: [Float]
    public let bass: [Float]
    public let melody: [Float]
    public let sampleRate: UInt32
    public let bpm: Float
    public let measureOffset: Float
    public let beatOffset: Float
    public let tempoConfidence: Float

    /// Stems in canonical order, matching `STEMS` in the core.
    public var ordered: [(name: String, samples: [Float])] {
        [("drums", drums), ("vocals", vocals), ("bass", bass), ("melody", melody)]
    }
}

/// Swift entry point to the shared Rust DSP core. All heavy work happens in Rust;
/// this layer only marshals buffers and frees the C allocation.
public enum Stemacle {
    /// Separate stereo PCM into four mono stems. Pass the same array twice for mono.
    /// Returns `nil` on invalid input.
    public static func separate(left: [Float], right: [Float], sampleRate: UInt32) -> StemSplit? {
        guard !left.isEmpty, left.count == right.count else { return nil }
        let raw: UnsafeMutablePointer<StemacleStems>? = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                stemacle_separate(l.baseAddress, r.baseAddress, left.count, sampleRate)
            }
        }
        guard let raw else { return nil }
        defer { stemacle_stems_free(raw) }
        let s = raw.pointee
        let n = s.len
        func copy(_ ptr: UnsafeMutablePointer<Float>?) -> [Float] {
            guard let ptr, n > 0 else { return [] }
            return Array(UnsafeBufferPointer(start: ptr, count: n))
        }
        return StemSplit(
            drums: copy(s.drums_ptr),
            vocals: copy(s.vocals_ptr),
            bass: copy(s.bass_ptr),
            melody: copy(s.melody_ptr),
            sampleRate: s.sample_rate,
            bpm: s.bpm,
            measureOffset: s.measure_offset,
            beatOffset: s.beat_offset,
            tempoConfidence: s.tempo_confidence
        )
    }

    /// Model-facing frequency bins (matches `MODEL_BINS` in the core / the
    /// Spleeter ONNX model's frequency dimension).
    public static let modelBins = 1024

    /// STFT frame count for a signal length — the row count for `magnitudes` and
    /// the vocal mask handed to / from the neural model.
    public static func frameCount(_ length: Int) -> Int {
        length <= 0 ? 0 : stemacle_frame_count(length)
    }

    /// Vocal-mask frequency weight for a bin (0…1). Keeps sub-bass / high air out
    /// of the vocal stem; mirrors the web `vocalMaskWeightForBin`.
    public static func vocalMaskWeight(bin: Int) -> Float {
        stemacle_vocal_mask_weight_for_bin(bin)
    }

    /// Estimate tempo (bpm + measure/beat grid) from a mono signal. Used by the
    /// Demucs path, which produces stems directly and so needs the loop grid
    /// computed separately.
    public static func estimateTempo(mono: [Float], sampleRate: UInt32)
        -> (bpm: Float, measureOffset: Float, beatOffset: Float, confidence: Float) {
        guard !mono.isEmpty else { return (120, 0, 0, 0) }
        var bpm: Float = 120, mo: Float = 0, bo: Float = 0, conf: Float = 0
        mono.withUnsafeBufferPointer { m in
            stemacle_estimate_tempo(m.baseAddress, mono.count, sampleRate, &bpm, &mo, &bo, &conf)
        }
        return (bpm, mo, bo, conf)
    }

    /// Per-frame magnitude spectra over the first `modelBins` bins for L and R,
    /// row-major (`[f*modelBins + b]`). Feeds the Spleeter ONNX model on iOS.
    /// Returns `nil` on invalid input.
    public static func magnitudes(left: [Float], right: [Float])
        -> (magL: [Float], magR: [Float], frames: Int)? {
        guard !left.isEmpty, left.count == right.count else { return nil }
        let frames = frameCount(left.count)
        guard frames > 0 else { return nil }
        var magL = [Float](repeating: 0, count: frames * modelBins)
        var magR = [Float](repeating: 0, count: frames * modelBins)
        left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                magL.withUnsafeMutableBufferPointer { ml in
                    magR.withUnsafeMutableBufferPointer { mr in
                        stemacle_magnitudes(l.baseAddress, r.baseAddress, left.count,
                                            ml.baseAddress, mr.baseAddress)
                    }
                }
            }
        }
        return (magL, magR, frames)
    }

    /// Separate stereo PCM using a neural vocal `mask` (`frameCount(len)*modelBins`
    /// values, 0…1). The mask comes from the Spleeter ONNX model; the rest of the
    /// pipeline is the shared DSP core. Returns `nil` on invalid input.
    public static func separate(left: [Float], right: [Float], sampleRate: UInt32,
                                mask: [Float]) -> StemSplit? {
        guard !left.isEmpty, left.count == right.count else { return nil }
        let raw: UnsafeMutablePointer<StemacleStems>? = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                mask.withUnsafeBufferPointer { m in
                    stemacle_separate_with_mask(l.baseAddress, r.baseAddress, left.count,
                                                sampleRate, m.baseAddress, mask.count)
                }
            }
        }
        guard let raw else { return nil }
        defer { stemacle_stems_free(raw) }
        let s = raw.pointee
        let n = s.len
        func copy(_ ptr: UnsafeMutablePointer<Float>?) -> [Float] {
            guard let ptr, n > 0 else { return [] }
            return Array(UnsafeBufferPointer(start: ptr, count: n))
        }
        return StemSplit(
            drums: copy(s.drums_ptr), vocals: copy(s.vocals_ptr),
            bass: copy(s.bass_ptr), melody: copy(s.melody_ptr),
            sampleRate: s.sample_rate, bpm: s.bpm,
            measureOffset: s.measure_offset, beatOffset: s.beat_offset,
            tempoConfidence: s.tempo_confidence)
    }

    // MARK: Loop contract (pure helpers, mirror the core)

    public static func measureLength(bpm: Float) -> Float {
        stemacle_measure_length(bpm)
    }

    public static func snapLoopEnd(
        bpm: Float, measureOffset: Float, beatOffset: Float,
        duration: Float, currentSec: Float, loopLength: Float
    ) -> Float {
        stemacle_snap_loop_end(bpm, measureOffset, beatOffset, duration, currentSec, loopLength)
    }

    /// Loop range `[start, end)` and whether it fits within the track.
    public static func loopRange(
        bpm: Float, measureOffset: Float, beatOffset: Float,
        duration: Float, currentSec: Float, loopLength: Float
    ) -> (start: Float, end: Float, fits: Bool) {
        var start: Float = 0
        var end: Float = 0
        let fits = stemacle_loop_range(
            bpm, measureOffset, beatOffset, duration, currentSec, loopLength, &start, &end
        )
        return (start, end, fits != 0)
    }

    public static func audibleStemTime(
        transportSec: Float, loopStart: Float, loopEnd: Float, active: Bool, duration: Float
    ) -> Float {
        stemacle_audible_stem_time(transportSec, loopStart, loopEnd, active ? 1 : 0, duration)
    }

    // MARK: Visualization

    /// A `cols × rows` log-magnitude spectrogram (0...1), column-major
    /// (`grid[col][row]`, row 0 = low frequency) for drawing stem lanes and the
    /// radial player visualizer.
    public static func spectrogram(_ samples: [Float], cols: Int, rows: Int) -> [[Float]] {
        guard cols > 0, rows > 0, !samples.isEmpty else { return [] }
        var flat = [Float](repeating: 0, count: cols * rows)
        samples.withUnsafeBufferPointer { src in
            flat.withUnsafeMutableBufferPointer { dst in
                stemacle_spectrogram(src.baseAddress, samples.count, cols, rows, dst.baseAddress)
            }
        }
        return (0..<cols).map { c in Array(flat[(c * rows)..<((c + 1) * rows)]) }
    }

    /// A `cols`-bucket peak waveform envelope (0…1). O(n) time and O(cols) space —
    /// use on iOS instead of `spectrogram` to avoid the large STFT allocation on long tracks.
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

    /// A `cols`-bucket peak+RMS envelope as `(peak, rms)` pairs, each 0…1, with
    /// `rms <= peak`. The native equivalent of the web `drawWave` (faint RMS body
    /// + darker peak tips); render both layers for a lane that matches the web.
    /// Precompute at a high `cols` so a zoomed scroll window stays smooth.
    public static func waveformPeaksRMS(_ samples: [Float], cols: Int) -> [(peak: Float, rms: Float)] {
        guard cols > 0, !samples.isEmpty else { return [] }
        var flat = [Float](repeating: 0, count: cols * 2)
        samples.withUnsafeBufferPointer { src in
            flat.withUnsafeMutableBufferPointer { dst in
                stemacle_waveform_peaks_rms(src.baseAddress, samples.count, cols, dst.baseAddress)
            }
        }
        return (0..<cols).map { (peak: flat[$0 * 2], rms: flat[$0 * 2 + 1]) }
    }
}
