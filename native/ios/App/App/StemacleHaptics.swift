import UIKit

/// Lightweight wrapper around UIKit feedback generators so Stemacle's controls
/// feel like a physical object rather than a web page. Every call is a no-op on
/// hardware without a Taptic Engine, so callers can fire freely without guards.
///
/// Must be called from the main thread; all current call sites live on the
/// `@MainActor` view model or in SwiftUI views.
enum StemacleHaptics {
    /// A soft tap for incidental control changes (mute, volume detents).
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// A firmer tap for transport actions (play / pause / restart / stop).
    static func transport() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// A crisp selection click for switching tabs or monitor modes.
    static func toggle() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// A rigid thunk when a loop locks in — the most "physical" interaction.
    static func loopEngaged() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// A success notification when a split finishes and stems are ready.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// An error notification when a load fails.
    static func failure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
