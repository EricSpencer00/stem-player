import XCTest
@testable import StemacleKit

final class StreamingChunkerTests: XCTestCase {
    /// A constant signal must reconstruct to itself: in every overlap the two
    /// windows' crossfade weights sum to 1 (partition of unity).
    func testPartitionOfUnityReconstructsConstant() {
        let sr = 44_100.0
        // ~3.2 min so many windows are exercised.
        let total = Int(sr * 190)
        let chunker = StreamingChunker(totalSamples: total, sampleRate: sr,
                                       chunkSeconds: 30, overlapSeconds: 0.75)
        XCTAssertGreaterThan(chunker.windowCount, 5, "long track should need many windows")

        var dst = [Float](repeating: 0, count: total)
        for i in 0..<chunker.windowCount {
            let (s, e) = chunker.windowRange(i)
            let windowStem = [Float](repeating: 1.0, count: e - s)  // constant "separated" window
            chunker.accumulate(into: &dst, windowStem: windowStem, window: i)
        }

        var maxErr: Float = 0
        for v in dst { maxErr = max(maxErr, abs(v - 1.0)) }
        XCTAssertLessThan(maxErr, 1e-4, "constant signal must reconstruct to 1.0 everywhere (partition of unity)")
    }

    /// Windows tile the whole track: the last window reaches the final sample.
    func testWindowsCoverWholeTrack() {
        let sr = 44_100.0
        let total = Int(sr * 130)
        let chunker = StreamingChunker(totalSamples: total, sampleRate: sr)
        let last = chunker.windowRange(chunker.windowCount - 1)
        XCTAssertEqual(last.end, total, "last window must reach the end of the track")
        // No gaps: each window's start is within the previous window's range.
        for i in 1..<chunker.windowCount {
            let prev = chunker.windowRange(i - 1)
            let cur = chunker.windowRange(i)
            XCTAssertLessThan(cur.start, prev.end, "window \(i) must overlap window \(i - 1)")
        }
    }

    /// A short track fits in a single window with no ramps (full amplitude).
    func testShortTrackSingleWindow() {
        let sr = 44_100.0
        let total = Int(sr * 12)
        let chunker = StreamingChunker(totalSamples: total, sampleRate: sr, chunkSeconds: 30)
        XCTAssertEqual(chunker.windowCount, 1)
        XCTAssertEqual(chunker.weight(global: 0, window: 0), 1.0)
        XCTAssertEqual(chunker.weight(global: total - 1, window: 0), 1.0)
    }
}
