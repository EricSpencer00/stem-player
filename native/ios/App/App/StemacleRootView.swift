import SwiftUI

struct StemacleRootView: View {
    @StateObject private var player = StemPlayerViewModel()
    @State private var selectedTab: StemacleRootTab = .splitter

    private let secondaryTabContentMaxWidth: CGFloat = 520

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
                nativeNavigation("Shuffle", constrainedWidth: secondaryTabContentMaxWidth) {
                    StemShuffleView()
                }
            case .library:
                nativeNavigation("Library", constrainedWidth: secondaryTabContentMaxWidth) {
                    StemLibraryView(viewModel: player)
                }
            case .settings:
                nativeNavigation("Settings", constrainedWidth: secondaryTabContentMaxWidth) {
                    StemacleSettingsView()
                }
            }
        }
        .tint(StemacleDesign.purple)
        .background(StemacleDesign.paper.ignoresSafeArea())
    }

    @ViewBuilder
    @ViewBuilder
    private func nativeNavigation<Content: View>(
        _ title: String,
        constrainedWidth: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let bodyContent = constrainedTabContent(content(), maxWidth: constrainedWidth)

        if #available(iOS 16.0, *) {
            NavigationStack {
                bodyContent
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        } else {
            NavigationView {
                bodyContent
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationViewStyle(.stack)
        }
    }

    @ViewBuilder
    private func constrainedTabContent<Content: View>(_ content: Content, maxWidth: CGFloat?) -> some View {
        if let maxWidth {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
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
                    selection = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 21, weight: .semibold))
                            .frame(height: 25)
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .frame(maxWidth: .infinity, minHeight: 66)
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
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 10)
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
        StemacleScreen {
            List {
                Section("Samples") {
                    ForEach(viewModel.samples) { sample in
                        Button {
                            viewModel.loadSample(sample)
                        } label: {
                            Label(sample.title, systemImage: "waveform.circle")
                        }
                    }
                }

                Section("Recent projects") {
                    if viewModel.recentProjects.isEmpty {
                        Text("Imported tracks appear here after the first native split.")
                            .foregroundStyle(StemacleDesign.mutedInk)
                    } else {
                        ForEach(viewModel.recentProjects, id: \.self) { project in
                            Label(project, systemImage: "folder")
                        }
                    }
                }

                Section("Local contract") {
                    Label("Files stay on-device", systemImage: "lock")
                    Label("Native Swift splitter", systemImage: "swift")
                    Label("Shuffle is a separate surface", systemImage: "square.split.2x1")
                }
            }
            .background(StemacleDesign.paper)
        }
        .navigationTitle("Library")
    }
}
