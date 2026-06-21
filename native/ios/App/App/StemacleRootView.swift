import SwiftUI

struct StemacleRootView: View {
    @StateObject private var player = StemPlayerViewModel()

    var body: some View {
        tabs
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 16.0, *) {
            tabContent
                .toolbarBackground(StemacleDesign.paper, for: .navigationBar, .tabBar)
                .toolbarColorScheme(.light, for: .navigationBar, .tabBar)
        } else {
            tabContent
        }
    }

    private var tabContent: some View {
        TabView {
            nativeNavigation("Stem Splitter") {
                StemPlayerView(viewModel: player)
            }
            .tabItem {
                Label("Stem Splitter", systemImage: "waveform")
            }

            nativeNavigation("Shuffle") {
                StemShuffleView()
            }
            .tabItem {
                Label("Shuffle", systemImage: "shuffle")
            }

            nativeNavigation("Library") {
                StemLibraryView(viewModel: player)
            }
            .tabItem {
                Label("Library", systemImage: "music.note.list")
            }

            nativeNavigation("Settings") {
                StemacleSettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(StemacleDesign.purple)
    }

    @ViewBuilder
    private func nativeNavigation<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                content()
                    .navigationTitle(title)
            }
        } else {
            NavigationView {
                content()
                    .navigationTitle(title)
            }
            .navigationViewStyle(.stack)
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
