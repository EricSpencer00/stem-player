import Foundation

/// Plans a memory-bounded, **streaming** separation of a long track.
///
/// The Rust STFT allocates full-length complex spectrograms, so separating a
/// whole multi-minute track at once peaks around a gigabyte and the iOS process
/// is jetsam-killed. That is why the old path capped input at 90 s and
/// silence-padded the rest. Instead we split the track into overlapping windows,
/// separate each independently (bounded peak memory ≈ one window), and stitch the
/// per-window stems back with a linear crossfade over the overlap.
///
/// The crossfade is a **partition of unity**: in every overlap region the two
/// windows' weights sum to 1, so a constant signal reconstructs exactly. The
/// overlap (`padSamples`) is chosen larger than the core's ~93 ms edge de-click
/// (`declick_edges`), so each window's faded edge lands in its own near-zero
/// weight region and the neighbour covers it — seams stay click-free.
///
/// Suno-style: the caller separates window 0 first (fast first sound), then fills
/// the remaining windows in the background.
public struct StreamingChunker: Sendable {
    /// Total samples in the full track (per channel).
    public let totalSamples: Int
    /// Core advance between window starts, in samples (`winLen - padSamples`).
    public let hop: Int
    /// Window length in samples.
    public let winLen: Int
    /// Overlap / crossfade width in samples.
    public let padSamples: Int

    /// Build a chunk plan. `chunkSeconds` is the window length; `overlapSeconds`
    /// the crossfade width (must exceed the core's de-click, ~0.1 s).
    public init(totalSamples: Int, sampleRate: Double,
                chunkSeconds: Double = 30, overlapSeconds: Double = 0.75) {
        let total = max(0, totalSamples)
        let ov = max(1, Int(overlapSeconds * sampleRate))
        // Window must be strictly longer than the overlap so hop > 0.
        let wl = max(ov + 1, Int(chunkSeconds * sampleRate))
        self.totalSamples = total
        self.padSamples = min(ov, wl - 1)
        self.winLen = wl
        self.hop = wl - self.padSamples
    }

    /// Number of windows needed to cover the whole track.
    public var windowCount: Int {
        guard totalSamples > 0 else { return 0 }
        if totalSamples <= winLen { return 1 }
        // ceil((total - winLen) / hop) + 1
        return (totalSamples - winLen + hop - 1) / hop + 1
    }

    /// Half-open sample range `[start, end)` a given window must be separated over.
    public func windowRange(_ i: Int) -> (start: Int, end: Int) {
        let start = min(i * hop, max(0, totalSamples - 1))
        let end = min(start + winLen, totalSamples)
        return (start, end)
    }

    /// Crossfade weight (0…1) for global sample `g` under window `i`. Left/right
    /// ramps are suppressed at the track's first/last window so those true edges
    /// keep full amplitude.
    public func weight(global g: Int, window i: Int) -> Float {
        let start = i * hop
        let local = g - start
        if local < 0 || local >= winLen { return 0 }
        let last = windowCount - 1
        let ov = Float(padSamples)
        var w: Float = 1
        if i > 0 && local < padSamples {                 // fade in against window i-1
            w = min(w, Float(local) / ov)
        }
        if i < last && local >= winLen - padSamples {    // fade out into window i+1
            w = min(w, Float(winLen - local) / ov)
        }
        return max(0, min(1, w))
    }

    /// Accumulate one window's separated stem into a full-length destination
    /// buffer, applying the crossfade taper. `dst.count` must be `totalSamples`;
    /// `windowStem` must be exactly `windowRange(i)` long.
    public func accumulate(into dst: inout [Float], windowStem: [Float], window i: Int) {
        let (start, end) = windowRange(i)
        let n = min(windowStem.count, end - start)
        guard n > 0, dst.count >= end else { return }
        for k in 0..<n {
            let g = start + k
            dst[g] += windowStem[k] * weight(global: g, window: i)
        }
    }
}
