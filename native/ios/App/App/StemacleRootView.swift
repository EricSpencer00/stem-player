import Foundation
import SwiftUI

struct StemacleRootView: View {
    @StateObject private var player = StemPlayerViewModel()
    @State private var selectedTab: StemacleRootTab = .splitter

    var body: some View {
        tabs
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 16.0, *) {
            tabContent
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StemacleRootTabBar(selection: $selectedTab, showTopDivider: selectedTab != .splitter)
                }
                .toolbarBackground(StemacleDesign.paper, for: .navigationBar, .tabBar)
                .toolbarBackground(.visible, for: .navigationBar, .tabBar)
                .toolbarColorScheme(.light, for: .navigationBar)
        } else {
            tabContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StemacleRootTabBar(selection: $selectedTab, showTopDivider: selectedTab != .splitter)
                }
        }
    }

    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .splitter:
                nativeNavigation("Stem Splitter") {
                    StemPlayerView(viewModel: player)
                }
            case .shuffle:
                nativeNavigation("Shuffle") {
                    StemShuffleView()
                }
            case .library:
                nativeNavigation("Library") {
                    StemLibraryView(viewModel: player)
                }
            case .settings:
                nativeNavigation("Settings") {
                    StemacleSettingsView()
                }
            }
        }
        .tint(StemacleDesign.purple)
        .background(StemacleDesign.paper.ignoresSafeArea())
    }

    @ViewBuilder
    private func nativeNavigation<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                content()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        } else {
            NavigationView {
                content()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationViewStyle(.stack)
        }
    }
}

private enum StemacleRootTab: String, CaseIterable, Identifiable {
    case splitter
    case shuffle
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .splitter:
            return "Stem Splitter"
        case .shuffle:
            return "Shuffle"
        case .library:
            return "Library"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .splitter:
            return "waveform"
        case .shuffle:
            return "shuffle"
        case .library:
            return "music.note.list"
        case .settings:
            return "gearshape"
        }
    }
}

private struct StemacleRootTabBar: View {
    @Binding var selection: StemacleRootTab
    var showTopDivider: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            ForEach(StemacleRootTab.allCases) { tab in
                Button {
                    if selection != tab {
                        StemacleHaptics.toggle()
                    }
                    selection = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(height: 20)
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(selection == tab ? StemacleDesign.purple : StemacleDesign.mutedInk)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(StemacleDesign.paper)
                                .overlay(Capsule().stroke(Color.white.opacity(0.38), lineWidth: 1))
                                .shadow(color: StemacleDesign.shadow.opacity(0.32), radius: 8, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(StemacleDesign.paper.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            if showTopDivider {
                StemacleHairline()
            }
        }
    }
}

struct StemLibraryView: View {
    @ObservedObject var viewModel: StemPlayerViewModel

    var body: some View {
        StemacleScreen(showsTentacleFooter: false) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Local library")
                                    .font(.caption.weight(.bold))
                                    .textCase(.uppercase)
                                    .foregroundStyle(StemacleDesign.inkSoft)
                                Text("Previous tracks, sorted your way")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(StemacleDesign.ink)
                            }
                            Spacer()
                            Text("\(viewModel.visibleLibraryItems.count) item\(viewModel.visibleLibraryItems.count == 1 ? "" : "s")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(StemacleDesign.mutedInk)
                        }

                        Text("All of this stays on the device. Tap a track to reopen it in the splitter, then sort by recency, name, or queue state.")
                            .font(.caption)
                            .foregroundStyle(StemacleDesign.mutedInk)

                        Picker("Sort", selection: $viewModel.librarySort) {
                            ForEach(StemLibrarySort.allCases) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                        .pickerStyle(.segmented)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(StemLibraryFilter.allCases) { filter in
                                    Button {
                                        viewModel.libraryFilter = filter
                                    } label: {
                                        Text(filter.title)
                                            .font(.caption.weight(.semibold))
                                            .textCase(.uppercase)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(viewModel.libraryFilter == filter ? StemacleDesign.purple.opacity(0.22) : StemacleDesign.paper)
                                            )
                                            .overlay(
                                                Capsule()
                                                    .stroke(viewModel.libraryFilter == filter ? StemacleDesign.purple : StemacleDesign.track.opacity(0.55), lineWidth: 1)
                                            )
                                            .foregroundStyle(viewModel.libraryFilter == filter ? StemacleDesign.ink : StemacleDesign.mutedInk)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Previous tracks") {
                    if viewModel.visibleLibraryItems.isEmpty {
                        Text(viewModel.libraryFilter == .all
                             ? "Imported songs and local splits will appear here once you add a file."
                             : "No tracks match this filter yet.")
                            .font(.caption)
                            .foregroundStyle(StemacleDesign.mutedInk)
                    } else {
                        ForEach(viewModel.visibleLibraryItems) { item in
                            StemLibraryTrackRow(item: item) {
                                viewModel.openLibraryItem(item)
                            }
                        }
                    }
                }

                Section("Queue statuses") {
                    if viewModel.queueLibraryItems.isEmpty {
                        Text("Track imports, splits, and failures will show up here.")
                            .font(.caption)
                            .foregroundStyle(StemacleDesign.mutedInk)
                    } else {
                        ForEach(viewModel.queueLibraryItems) { item in
                            StemLibraryQueueRow(item: item) {
                                viewModel.openLibraryItem(item)
                            }
                        }
                    }
                }
            }
            .stemacleCompactList()
            .background(StemacleDesign.paper)
        }
    }
}

private struct StemLibraryTrackRow: View {
    let item: StemLibraryItem
    let openAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(StemacleDesign.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(StemacleDesign.mutedInk)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                StemLibraryStatusPill(status: item.status)
            }

            HStack(spacing: 8) {
                Button(action: openAction) {
                    Text(item.status == .failed ? "Retry" : "Open")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(StemacleDesign.paper)
                .background(Capsule().fill(StemacleDesign.ink))

                if let duration = item.duration {
                    Text(durationText(duration))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(StemacleDesign.inkGhost)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        let source = item.sourceName
        let status = item.statusMessage
        return [source, status].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let whole = max(0, Int(duration.rounded()))
        return "\(whole / 60):\(String(format: "%02d", whole % 60))"
    }
}

private struct StemLibraryQueueRow: View {
    let item: StemLibraryItem
    let openAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StemacleDesign.ink)
                Text("\(item.status.title) · \(item.statusMessage)")
                    .font(.caption)
                    .foregroundStyle(StemacleDesign.mutedInk)
            }

            Spacer(minLength: 8)

            Button(action: openAction) {
                Image(systemName: item.status == .failed ? "arrow.clockwise" : "arrow.forward")
                    .font(.caption.weight(.semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(StemacleDesign.purple)
            .background(Circle().fill(StemacleDesign.purple.opacity(0.14)))
        }
        .padding(.vertical, 6)
    }
}

private struct StemLibraryStatusPill: View {
    let status: StemLibraryItem.Status

    var body: some View {
        Label(status.title, systemImage: status.symbolName)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(background))
            .overlay(Capsule().stroke(border, lineWidth: 1))
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch status {
        case .ready:
            return StemacleDesign.purple.opacity(0.12)
        case .processing:
            return StemacleDesign.center.opacity(0.20)
        case .queued:
            return StemacleDesign.track.opacity(0.15)
        case .failed:
            return Color(red: 0.84, green: 0.45, blue: 0.34).opacity(0.14)
        }
    }

    private var border: Color {
        switch status {
        case .ready:
            return StemacleDesign.purple.opacity(0.45)
        case .processing:
            return StemacleDesign.center.opacity(0.72)
        case .queued:
            return StemacleDesign.track.opacity(0.56)
        case .failed:
            return Color(red: 0.84, green: 0.45, blue: 0.34).opacity(0.72)
        }
    }

    private var foreground: Color {
        switch status {
        case .ready:
            return StemacleDesign.purple
        case .processing:
            return StemacleDesign.inkSoft
        case .queued:
            return StemacleDesign.mutedInk
        case .failed:
            return Color(red: 0.58, green: 0.20, blue: 0.14)
        }
    }
}
