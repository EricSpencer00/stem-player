import SwiftUI

/// Stemacle's restrained, warm palette. Per PRODUCT.md: warm cream surfaces,
/// matte depth through tone, muted purple as the single action accent, amber
/// only for active loop dots.
enum Stem {
    static let cream = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let creamDeep = Color(red: 0.92, green: 0.89, blue: 0.84)
    static let ink = Color(red: 0.17, green: 0.15, blue: 0.20)
    static let inkSoft = Color(red: 0.42, green: 0.39, blue: 0.44)
    static let purple = Color(red: 0.42, green: 0.34, blue: 0.56)
    static let amber = Color(red: 0.85, green: 0.62, blue: 0.28)

    static let stemOrder = ["drums", "vocals", "bass", "melody"]
    static let minimumHitTarget: CGFloat = 44
}
