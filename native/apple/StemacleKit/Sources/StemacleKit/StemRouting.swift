import Foundation

/// Pure routing model for the Stem Shuffle / Mixer: each of the four stems is
/// routed to one of two source songs (A or B). Kept free of AVFoundation and
/// SwiftUI so it is unit-testable; `MixerViewModel` owns one of these and uses
/// it to decide which song each stem's audio comes from.
public struct StemRouting: Sendable, Equatable {
    /// Canonical stem order, matching `STEMS` in the core.
    public static let stems = ["drums", "vocals", "bass", "melody"]

    /// Per-stem routing: `false` = source A, `true` = source B.
    private var routeToB: [String: Bool]

    public init() {
        routeToB = Dictionary(uniqueKeysWithValues: Self.stems.map { ($0, false) })
    }

    /// Whether `stem` currently routes to source B (`false` for unknown stems).
    public func routesToB(_ stem: String) -> Bool {
        routeToB[stem] ?? false
    }

    /// Flip a known stem between A and B. Unknown stems are ignored.
    public mutating func toggle(_ stem: String) {
        guard routeToB[stem] != nil else { return }
        routeToB[stem]?.toggle()
    }

    /// Resolve `stem` to one of two source tokens — `b` when routed to B, else `a`.
    public func source<T>(for stem: String, a: T, b: T) -> T {
        routesToB(stem) ? b : a
    }

    /// Playback needs both source songs present.
    public func canPlay(hasA: Bool, hasB: Bool) -> Bool {
        hasA && hasB
    }
}
