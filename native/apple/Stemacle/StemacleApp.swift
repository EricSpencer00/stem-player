import SwiftUI
import UniformTypeIdentifiers

@main
struct StemacleApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        #if os(macOS)
        .defaultSize(width: 480, height: 860)
        #endif
    }
}

enum Tab: Hashable { case library, splitter, settings }

/// Tabbed shell implementing the verified navigation model (specs/Navigation.tla):
/// Library | Splitter | Settings, with Import reachable from anywhere and fresh
/// splits saved to the Library's stem cache for instant re-open.
struct AppRootView: View {
    @StateObject private var model = StemPlayerViewModel()
    @StateObject private var library = LibraryStore()
    @State private var tab: Tab = .splitter
    @State private var importing = false

    var body: some View {
        TabView(selection: $tab) {
            LibraryView(library: library,
                        onOpen: { project in model.openProject(project); tab = .splitter },
                        onImport: { importing = true })
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(Tab.library)

            SplitterView(model: model, onImport: { importing = true })
                .tabItem { Label("Splitter", systemImage: "waveform") }
                .tag(Tab.splitter)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(Stem.purple)
        .onAppear {
            model.library = library
            if ProcessInfo.processInfo.environment["STEMACLE_TAB"] == "library" { tab = .library }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                tab = .splitter
                Task { await model.loadFile(url) }
            }
        }
        .task {
            if ProcessInfo.processInfo.environment["STEMACLE_AUTOLOAD"] != nil,
               let url = Bundle.main.url(forResource: "demo", withExtension: "wav") {
                model.library = library
                await model.loadFile(url)
                if ProcessInfo.processInfo.environment["STEMACLE_AUTOPLAY"] != nil { model.togglePlay() }
            }
        }
    }
}

/// The Song Library: every split saved as a card, opens instantly from cache.
struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    var onOpen: (Project) -> Void
    var onImport: () -> Void

    var body: some View {
        ZStack {
            Stem.cream.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Library").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Spacer()
                    Button(action: onImport) {
                        Label("Add", systemImage: "plus").font(.subheadline.weight(.medium))
                    }.buttonStyle(.plain).foregroundStyle(Stem.purple)
                }
                .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 6)

                if library.projects.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "square.stack").font(.system(size: 40, weight: .light))
                            .foregroundStyle(Stem.inkSoft)
                        Text("No songs yet").font(.headline)
                        Text("Split a track and it lands here — reopen any time without waiting.")
                            .font(.footnote).foregroundStyle(Stem.inkSoft)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                        Button(action: onImport) { Text("Add a song").font(.subheadline.weight(.medium)) }
                            .buttonStyle(.borderedProminent).tint(Stem.purple).padding(.top, 4)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(library.projects) { project in
                                Button { onOpen(project) } label: { ProjectRow(project: project) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }
            }
        }
        .foregroundStyle(Stem.ink)
    }
}

struct ProjectRow: View {
    let project: Project
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(RadialGradient(colors: [Stem.cream, Stem.creamDeep], center: .center, startRadius: 2, endRadius: 36))
                Image(systemName: "waveform").foregroundStyle(Stem.purple)
            }
            .frame(width: 52, height: 52)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Stem.creamDeep, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(project.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text("\(Int(project.bpm)) BPM · \(clock(project.duration)) · \(project.quality)")
                    .font(.caption).foregroundStyle(Stem.inkSoft)
            }
            Spacer()
            Image(systemName: "play.circle").foregroundStyle(Stem.inkSoft)
        }
        .padding(10)
        .background(Stem.cream)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Stem.creamDeep, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private func clock(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

/// Reports the stem list's scroll offset so the player header can collapse.
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The Splitter tab: the Stemacle player + four-stem panel with spectrogram lanes.
struct SplitterView: View {
    @ObservedObject var model: StemPlayerViewModel
    var onImport: () -> Void
    @State private var scrollOffset: CGFloat = 0
    @State private var masterImage: Image?

    /// Header collapses as the list scrolls up (mobile especially).
    private var headerScale: CGFloat {
        let t = min(max(scrollOffset, 0), 160) / 160
        return 1 - t * 0.6   // shrinks to 40%
    }

    var body: some View {
        ZStack {
            Stem.cream.ignoresSafeArea()
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Text(model.isReady && !model.songTitle.isEmpty ? model.songTitle : "stemacle")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.isReady ? Stem.ink : Stem.inkSoft)
                        .lineLimit(1)
                    Spacer()
                    // Persistent "change song" — load a new track without exiting.
                    Button(action: onImport) {
                        Image(systemName: "plus.circle").foregroundStyle(Stem.purple)
                    }.buttonStyle(.plain)
                }
                .font(.system(size: 17))
                .padding(.horizontal, 18)
                .padding(.top, 8)

                // Player header (compact + collapsing).
                Group {
                    if model.isReady {
                        PlayerHeaderView(model: model)
                    } else {
                        DeviceCircleView(model: model, onLoad: onImport)
                    }
                }
                .frame(maxWidth: model.isReady ? 200 : 280)
                .frame(height: (model.isReady ? 190 : 240) * headerScale)
                .scaleEffect(headerScale, anchor: .top)
                .animation(.easeOut(duration: 0.15), value: model.isReady)

                // The player's master spectrogram overview ("the one in the player").
                if model.isReady {
                    VStack(spacing: 4) {
                        SpectrogramLane(image: masterImage, progress: model.progress,
                                        grid: model.measureGrid, height: 46) { p in
                            model.seek(toProgress: p)
                        }
                        HStack {
                            Text(model.elapsedString)
                            Spacer()
                            Text("\(Int(model.bpm)) BPM")
                            Spacer()
                            Text(model.totalString)
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Stem.inkSoft)
                    }
                    .padding(.horizontal, 18)
                }

                TransportView(model: model)

                if model.isReady { LoopControlBar(model: model).padding(.horizontal, 18) }

                // Stem panel with per-stem spectrogram lanes.
                ScrollView {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: -proxy.frame(in: .named("stemScroll")).minY
                        )
                    }
                    .frame(height: 0)

                    VStack(spacing: 10) {
                        ForEach(Stem.stemOrder, id: \.self) { stem in
                            StemRowView(model: model, stem: stem)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .coordinateSpace(name: "stemScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
            }
        }
        .foregroundStyle(Stem.ink)
        .task(id: model.loadGeneration) {
            masterImage = makeSpectrogramImage(model.masterSpectrogram)
        }
    }
}

/// Ready-state player: spinning disc with the radial EDM spectrum around it.
struct PlayerHeaderView: View {
    @ObservedObject var model: StemPlayerViewModel

    var body: some View {
        ZStack {
            RadialSpectrumView(spectrum: model.currentSpectrum, playing: model.isPlaying)
            SpinningDiscView(playing: model.isPlaying) { model.togglePlay() }
                .padding(46)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The warm matte circle — passive physical display + center load/play control.
/// Shown before a track is loaded.
struct DeviceCircleView: View {
    @ObservedObject var model: StemPlayerViewModel
    var onLoad: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Stem.cream, Stem.creamDeep],
                                     center: .center, startRadius: 8, endRadius: 200))
                .overlay(Circle().stroke(Stem.creamDeep, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
            VStack(spacing: 8) {
                if model.isProcessing {
                    if let p = model.splitProgress {
                        ZStack {
                            Circle().stroke(Stem.creamDeep, lineWidth: 4).frame(width: 64, height: 64)
                            Circle().trim(from: 0, to: CGFloat(p))
                                .stroke(Stem.amber, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90)).frame(width: 64, height: 64)
                            Text("\(Int(p * 100))%").font(.caption.monospacedDigit())
                                .foregroundStyle(Stem.inkSoft)
                        }
                    } else {
                        ProgressView().controlSize(.large)
                    }
                } else {
                    Button(action: onLoad) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Stem.purple)
                    }.buttonStyle(.plain)
                }
                Text(model.status)
                    .font(.footnote).foregroundStyle(Stem.inkSoft)
                    .multilineTextAlignment(.center)
                if !model.isProcessing, let demo = Bundle.main.url(forResource: "demo", withExtension: "wav") {
                    Button("try a sample") { Task { await model.loadFile(demo) } }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Stem.purple)
                        .buttonStyle(.plain)
                }
            }
            .padding(40)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Circle())
        .onTapGesture { if !model.isReady && !model.isProcessing { onLoad() } }
    }
}

/// Global mute, Mix/Solo loop monitoring, and the All-row linked loop.
struct LoopControlBar: View {
    @ObservedObject var model: StemPlayerViewModel
    private let bars: [(String, Float)] = [("¼", 0.25), ("½", 0.5), ("1", 1), ("2", 2)]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                pill("Mute all", on: model.globalMuted) { model.toggleGlobalMute() }
                pill(model.loopAuditionSolo ? "Solo" : "Mix", on: model.loopAuditionSolo) {
                    model.setLoopMonitoring(solo: !model.loopAuditionSolo)
                }
                Spacer()
                Text("All").font(.caption.weight(.medium)).foregroundStyle(Stem.inkSoft)
            }
            HStack(spacing: 6) {
                ForEach(bars, id: \.0) { label, value in
                    let active = model.allLoopBars == value
                    Button(label) { model.setAllLoop(bars: active ? nil : value) }
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(active ? Stem.amber.opacity(0.28) : Stem.creamDeep.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func pill(_ text: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(text, action: action)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(on ? Stem.purple.opacity(0.16) : Stem.creamDeep.opacity(0.5))
            .foregroundStyle(on ? Stem.purple : Stem.inkSoft)
            .clipShape(Capsule())
            .buttonStyle(.plain)
    }
}

struct TransportView: View {
    @ObservedObject var model: StemPlayerViewModel

    var body: some View {
        HStack(spacing: 28) {
            transportButton("backward.end.fill") { model.seek(toProgress: 0) }
            transportButton(model.isPlaying ? "pause.fill" : "play.fill") { model.togglePlay() }
            transportButton("stop.fill") { model.stop() }
        }
        .disabled(!model.isReady)
        .opacity(model.isReady ? 1 : 0.35)
    }

    private func transportButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Stem.ink)
                .frame(width: 44, height: 44)
        }.buttonStyle(.plain)
    }
}

/// One stem: name, controls, the spectrogram lane, and loop-length buttons.
struct StemRowView: View {
    @ObservedObject var model: StemPlayerViewModel
    let stem: String
    @State private var laneImage: Image?
    private let bars: [(String, Float)] = [("¼", 0.25), ("½", 0.5), ("1", 1), ("2", 2)]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(stem.capitalized).font(.subheadline.weight(.medium))
                Spacer()
                iconToggle("speaker.slash.fill", on: model.muted.contains(stem)) { model.toggleMute(stem) }
                iconToggle("headphones", on: model.soloed.contains(stem)) { model.toggleSolo(stem) }
            }
            // Spectrogram lane (the slider below each stem) with tap-to-seek.
            SpectrogramLane(image: laneImage, progress: model.progress, grid: model.measureGrid) { p in
                model.seek(toProgress: p)
            }
            Slider(
                value: Binding(get: { model.volumes[stem] ?? 0.8 },
                               set: { model.setVolume(stem, $0) }), in: 0...1
            ).tint(Stem.purple)

            HStack(spacing: 6) {
                ForEach(bars, id: \.0) { label, value in
                    let active = model.loopBars[stem] == value
                    Button(label) { model.setLoop(stem, bars: active ? nil : value) }
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(active ? Stem.amber.opacity(0.25) : Stem.creamDeep.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Stem.cream)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Stem.creamDeep, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(model.isReady ? 1 : 0.5)
        .task(id: model.loadGeneration) {
            laneImage = makeSpectrogramImage(model.spectrograms[stem] ?? [])
        }
    }

    private func iconToggle(_ name: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 14))
                .foregroundStyle(on ? Stem.purple : Stem.inkSoft)
                .frame(width: 30, height: 30)
                .background(on ? Stem.purple.opacity(0.12) : .clear)
                .clipShape(Circle())
        }.buttonStyle(.plain)
    }
}

/// Settings: the htdemucs queue-server URL. When set, separation runs on the
/// server for full quality; when empty, the app separates on-device (DSP).
struct SettingsView: View {
    @State private var serverURL = UserDefaults.standard.string(forKey: "stemacle.serverURL") ?? ""

    var body: some View {
        ZStack {
            Stem.cream.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings").font(.system(size: 22, weight: .semibold, design: .rounded))
                    .padding(.top, 10)
                Text("Separation server").font(.subheadline.weight(.medium))
                TextField("http://192.168.x.x:8008", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onChange(of: serverURL) { v in
                        UserDefaults.standard.set(v, forKey: "stemacle.serverURL")
                    }
                Text("When set, tracks split with full htdemucs quality on the server. Leave empty to split on-device.")
                    .font(.footnote).foregroundStyle(Stem.inkSoft)
                Spacer()
                HStack(spacing: 10) {
                    Link("Privacy", destination: URL(string: "https://stemacle.com/privacy/")!)
                    Link("Terms", destination: URL(string: "https://stemacle.com/terms/")!)
                    Link("Support", destination: URL(string: "https://stemacle.com/support/")!)
                }
                .font(.footnote).foregroundStyle(Stem.purple)
            }
            .padding(20)
        }
        .foregroundStyle(Stem.ink)
    }
}
