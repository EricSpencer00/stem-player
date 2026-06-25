import XCTest
@testable import StemacleKit

final class StemacleKitTests: XCTestCase {
    /// The Swift wrapper marshals a real separation through the Rust core and
    /// frees the C allocation. Verifies four aligned, non-empty stems.
    func testSeparateProducesFourAlignedStems() {
        let fftSize = 4096, hop = 1024
        let len = fftSize + 60 * hop
        let mono = (0..<len).map { i -> Float in
            sinf(0.02 * Float(i)) * 0.5 + sinf(0.2 * Float(i)) * 0.2
        }
        guard let split = Stemacle.separate(left: mono, right: mono, sampleRate: 44100) else {
            return XCTFail("separation returned nil")
        }
        XCTAssertGreaterThan(split.drums.count, 0)
        XCTAssertEqual(split.vocals.count, split.drums.count)
        XCTAssertEqual(split.bass.count, split.drums.count)
        XCTAssertEqual(split.melody.count, split.drums.count)
        XCTAssertTrue(split.bpm >= 60 && split.bpm <= 240, "bpm \(split.bpm)")
        XCTAssertEqual(split.ordered.map(\.name), ["drums", "vocals", "bass", "melody"])
    }

    func testInvalidInputReturnsNil() {
        XCTAssertNil(Stemacle.separate(left: [], right: [], sampleRate: 44100))
        XCTAssertNil(Stemacle.separate(left: [1, 2], right: [1], sampleRate: 44100))
    }

    /// Loop contract parity with the Rust core's golden cases.
    func testLoopContractMatchesCore() {
        XCTAssertEqual(Stemacle.measureLength(bpm: 120), 2.0, accuracy: 1e-5)

        let end = Stemacle.snapLoopEnd(
            bpm: 120, measureOffset: 0, beatOffset: 0, duration: 60, currentSec: 2.6, loopLength: 2.0)
        XCTAssertEqual(end, 4.0, accuracy: 1e-4)

        // A 4s loop must be rejected on a 3s track.
        let r = Stemacle.loopRange(
            bpm: 120, measureOffset: 0, beatOffset: 0, duration: 3, currentSec: 2.5, loopLength: 4.0)
        XCTAssertFalse(r.fits)

        let a = Stemacle.audibleStemTime(
            transportSec: 5.5, loopStart: 2.0, loopEnd: 4.0, active: true, duration: 60)
        XCTAssertEqual(a, 3.5, accuracy: 1e-4)
    }
}
