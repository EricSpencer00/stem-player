import XCTest
@testable import StemacleKit

/// Pure routing logic for the Stem Shuffle / Mixer (APPLE-015): each of the four
/// stems is routed to one of two source songs. This was previously embedded in
/// the un-testable `MixerViewModel` (app target); extracting it into StemacleKit
/// gives the routing real, executable unit coverage.
final class StemRoutingTests: XCTestCase {

    /// A fresh routing sends every stem to source A.
    func testDefaultRoutingIsAllSourceA() {
        let routing = StemRouting()
        for stem in StemRouting.stems {
            XCTAssertFalse(routing.routesToB(stem), "\(stem) should default to A")
        }
    }

    /// The canonical stems match the rest of the app.
    func testStemsAreCanonicalOrder() {
        XCTAssertEqual(StemRouting.stems, ["drums", "vocals", "bass", "melody"])
    }

    /// Toggling a stem flips it to B; toggling again returns it to A.
    func testToggleFlipsSingleStem() {
        var routing = StemRouting()
        routing.toggle("vocals")
        XCTAssertTrue(routing.routesToB("vocals"))
        XCTAssertFalse(routing.routesToB("drums"), "other stems unaffected")
        routing.toggle("vocals")
        XCTAssertFalse(routing.routesToB("vocals"))
    }

    /// Toggling an unknown stem is a no-op (does not crash, does not add a key).
    func testToggleUnknownStemIsNoOp() {
        var routing = StemRouting()
        routing.toggle("strings")
        XCTAssertFalse(routing.routesToB("strings"))
    }

    /// `source(for:a:b:)` returns A's token when the stem routes to A.
    func testSourceResolvesToAWhenNotToggled() {
        let routing = StemRouting()
        XCTAssertEqual(routing.source(for: "bass", a: "songA", b: "songB"), "songA")
    }

    /// `source(for:a:b:)` returns B's token after the stem is toggled.
    func testSourceResolvesToBWhenToggled() {
        var routing = StemRouting()
        routing.toggle("bass")
        XCTAssertEqual(routing.source(for: "bass", a: "songA", b: "songB"), "songB")
    }

    /// A mixed routing resolves each stem independently.
    func testMixedRoutingResolvesPerStem() {
        var routing = StemRouting()
        routing.toggle("drums")   // → B
        routing.toggle("melody")  // → B
        XCTAssertEqual(routing.source(for: "drums",  a: 1, b: 2), 2)
        XCTAssertEqual(routing.source(for: "vocals", a: 1, b: 2), 1)
        XCTAssertEqual(routing.source(for: "bass",   a: 1, b: 2), 1)
        XCTAssertEqual(routing.source(for: "melody", a: 1, b: 2), 2)
    }

    /// Playback is only possible when both sources are present.
    func testCanPlayRequiresBothSources() {
        let routing = StemRouting()
        XCTAssertFalse(routing.canPlay(hasA: false, hasB: false))
        XCTAssertFalse(routing.canPlay(hasA: true,  hasB: false))
        XCTAssertFalse(routing.canPlay(hasA: false, hasB: true))
        XCTAssertTrue(routing.canPlay(hasA: true,  hasB: true))
    }
}
