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
}
