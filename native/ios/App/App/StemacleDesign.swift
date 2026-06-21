import SwiftUI
import UIKit

private let backgroundArtworkLift: CGFloat = -62

enum StemacleDesign {
    static let paper = Color(red: 0.95, green: 0.91, blue: 0.82)
    static let pageTwo = Color(red: 0.89, green: 0.85, blue: 0.74)
    static let deviceOuter = Color(red: 0.82, green: 0.77, blue: 0.66)
    static let deviceInner = Color(red: 0.88, green: 0.84, blue: 0.74)
    static let center = Color(red: 0.80, green: 0.74, blue: 0.61)
    static let track = Color(red: 0.72, green: 0.66, blue: 0.56)
    static let ink = Color(red: 0.15, green: 0.12, blue: 0.15)
    static let inkSoft = Color(red: 0.28, green: 0.24, blue: 0.27)
    static let mutedInk = Color(red: 0.46, green: 0.41, blue: 0.39)
    static let inkGhost = Color(red: 0.62, green: 0.57, blue: 0.51)
    static let purple = Color(red: 0.63, green: 0.40, blue: 0.66)
    static let amber = Color(red: 0.86, green: 0.74, blue: 0.53)
    static let amberGlow = Color(red: 0.86, green: 0.74, blue: 0.53).opacity(0.34)
    static let rowGlow = Color(red: 0.79, green: 0.74, blue: 0.66).opacity(0.36)
    static let shadow = Color(red: 0.22, green: 0.17, blue: 0.12).opacity(0.18)

    static func stemColor(_ stem: Stem) -> Color {
        switch stem {
        case .drums:
            return Color(red: 0.54, green: 0.24, blue: 0.34)
        case .bass:
            return Color(red: 0.18, green: 0.34, blue: 0.36)
        case .vocals:
            return purple
        case .melody:
            return amber
        }
    }
}

enum StemacleAsset: String, CaseIterable, Identifiable {
    case appIcon
    case cutout
    case bottomBorder
    case background
    case cornerFlourish
    case emptyDots
    case waveformIcon
    case loopBadge
    case loadingSwirl

    var id: String { rawValue }

    var fileName: String {
        switch self {
        case .appIcon:
            return "stemacle-tentacle.png"
        case .cutout:
            return "stemacle-tentacle-cutout.png"
        case .bottomBorder:
            return "tentacle-bottom-border.png"
        case .background:
            return "suction-cup-pattern-bg.png"
        case .cornerFlourish:
            return "tentacle-corner-flourish.png"
        case .emptyDots:
            return "tentacle-empty-state-dots.png"
        case .waveformIcon:
            return "tentacle-waveform-icon.png"
        case .loopBadge:
            return "tentacle-loop-badge-icon.png"
        case .loadingSwirl:
            return "tentacle-loading-swirl-icon.png"
        }
    }

    var relativeDirectory: String {
        switch self {
        case .appIcon, .cutout:
            return ""
        case .bottomBorder, .background, .cornerFlourish, .emptyDots:
            return "tentacle-b-roll/graphics"
        case .waveformIcon, .loopBadge, .loadingSwirl:
            return "tentacle-b-roll/icons"
        }
    }

    var label: String {
        switch self {
        case .appIcon:
            return "Stemacle app icon"
        case .cutout:
            return "Original cutout tentacle"
        case .bottomBorder:
            return "Bottom tentacle border"
        case .background:
            return "Background texture"
        case .cornerFlourish:
            return "Corner flourish"
        case .emptyDots:
            return "Empty state dots"
        case .waveformIcon:
            return "Waveform icon"
        case .loopBadge:
            return "Loop badge"
        case .loadingSwirl:
            return "Loading swirl"
        }
    }

    var bundleSubdirectory: String {
        relativeDirectory.isEmpty ? "public/assets" : "public/assets/\(relativeDirectory)"
    }
}

struct StemacleAppIconMark: View {
    var size: CGFloat = 34

    var body: some View {
        StemacleAssetImage(asset: .appIcon)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: max(10, size * 0.28), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: max(10, size * 0.28), style: .continuous)
                    .stroke(Color.white.opacity(0.36), lineWidth: 1)
            )
            .shadow(color: StemacleDesign.shadow.opacity(0.75), radius: size * 0.18, y: size * 0.08)
            .accessibilityLabel("Stemacle app icon")
    }
}

struct StemacleScreen<Content: View>: View {
    var showsTentacleFooter = true
    let content: Content

    init(showsTentacleFooter: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsTentacleFooter = showsTentacleFooter
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                StemacleBackground()
            }
            .overlay(alignment: .bottom) {
                if showsTentacleFooter {
                    TentacleFooter(opacity: 0.42)
                        .allowsHitTesting(false)
                }
            }
    }
}

struct StemacleBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            // Base paper gradient
            LinearGradient(
                colors: [StemacleDesign.paper, StemacleDesign.pageTwo],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Subtle suction-cup texture
            StemacleAssetImage(asset: .background)
                .scaledToFill()
                .opacity(0.105)
                .blendMode(.multiply)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            // Top fade to keep it above the navigator and unify the beige at the status/navigation bar seam
            LinearGradient(
                colors: [StemacleDesign.paper, StemacleDesign.paper.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 96)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .zIndex(1)
        }
    }
}

struct TentacleFooter: View {
    var opacity: Double = 0.48

    var body: some View {
        StemacleAssetImage(asset: .bottomBorder)
            .aspectRatio(contentMode: .fill)
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .clipped()
            .opacity(opacity)
            .offset(y: backgroundArtworkLift)
            .accessibilityLabel(StemacleAsset.bottomBorder.label)
    }
}

struct StemacleAssetImage: View {
    let asset: StemacleAsset

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else {
                Image(systemName: "waveform")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    private var image: UIImage? {
        guard let url = Bundle.main.url(
            forResource: asset.fileName,
            withExtension: nil,
            subdirectory: asset.bundleSubdirectory
        ) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}

struct StemacleHairline: View {
    var body: some View {
        Rectangle()
            .fill(StemacleDesign.track.opacity(0.75))
            .frame(height: 1)
    }
}

struct HideScrollContentBackgroundIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

struct StemacleCompactListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .modifier(HideScrollContentBackgroundIfAvailable())
            .foregroundStyle(StemacleDesign.ink)
            .tint(StemacleDesign.purple)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(StemacleDesign.paper.opacity(0.92))
            .listRowSeparatorTint(StemacleDesign.track.opacity(0.45))
    }
}

extension View {
    func stemacleCompactList() -> some View {
        modifier(StemacleCompactListStyle())
    }
}

struct StemaclePanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(StemacleDesign.paper.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(StemacleDesign.track.opacity(0.66), lineWidth: 1)
                    )
            )
    }
}

struct WaveformBars: View {
    var values: [Float]
    var color: Color
    var cursor: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let height = max(1, proxy.size.height)
            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 1) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        Rectangle()
                            .fill(color.opacity(0.68))
                            .frame(
                                width: max(1, width / CGFloat(max(1, values.count))),
                                height: max(1, CGFloat(value) * height)
                            )
                    }
                }
                Rectangle()
                    .fill(StemacleDesign.ink)
                    .frame(width: 2, height: height)
                    .offset(x: min(width - 2, max(0, width * cursor)))
            }
        }
    }
}

#Preview("Background with top fade under navigation") {
    NavigationView {
        VStack(spacing: 12) {
            Text("Background QA")
                .font(.headline)
            Text("Verify beige gradient, texture, and top fade.")
                .font(.caption)
                .foregroundStyle(StemacleDesign.mutedInk)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { StemacleBackground() }
        .navigationTitle("Visual QA")
        .navigationBarTitleDisplayMode(.inline)
    }
}
