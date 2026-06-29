import SwiftUI
import StoreKit
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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

enum Tab: Hashable { case library, splitter, shuffle, settings }

/// Tabbed shell implementing the verified navigation model (specs/Navigation.tla):
/// Library | Splitter | Shuffle | Settings, with Import reachable from anywhere and fresh
/// splits saved to the Library's stem cache for instant re-open.
struct AppRootView: View {
    @StateObject private var model = StemPlayerViewModel()
    @StateObject private var library = LibraryStore()
    @StateObject private var mixer = MixerViewModel()
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

            MixerView(library: library, mixer: mixer)
                .tabItem { Label("Shuffle", systemImage: "shuffle") }
                .tag(Tab.shuffle)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(Stem.purple)
        .onAppear {
            model.library = library
            if ProcessInfo.processInfo.environment["STEMACLE_TAB"] == "library" { tab = .library }
            if ProcessInfo.processInfo.environment["STEMACLE_TAB"] == "shuffle" { tab = .shuffle }
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
                            .frame(minWidth: Stem.minimumHitTarget, minHeight: Stem.minimumHitTarget,
                                   alignment: .trailing)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(Stem.purple)
                        .accessibilityIdentifier("library.add")
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
                        Button(action: onImport) {
                            Text("Add a song")
                                .font(.subheadline.weight(.medium))
                                .frame(minWidth: Stem.minimumHitTarget, minHeight: Stem.minimumHitTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Stem.purple)
                        .padding(.top, 4)
                        .accessibilityIdentifier("library.empty.add")
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(library.projects) { project in
                                Button { onOpen(project) } label: { ProjectRow(project: project) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("project.row.\(project.id.uuidString)")
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
        .contentShape(Rectangle())
    }
    private func clock(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

/// Reports the stem list's scroll offset so the player header can collapse.
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

enum PlayerHeaderMetrics {
    static let readyDiameter: CGFloat = 156
    static let idleDiameter: CGFloat = 220
    static let masterLaneHeight: CGFloat = 34
    static let transportSpacing: CGFloat = 22
}

/// The Splitter tab: the Stemacle player + four-stem panel with spectrogram lanes.
struct SplitterView: View {
    @ObservedObject var model: StemPlayerViewModel
    var onImport: () -> Void
    @State private var scrollOffset: CGFloat = 0
    @State private var masterImage: Image?
    @State private var dropTargeted = false

    /// Header collapses as the list scrolls up (mobile especially).
    private var headerScale: CGFloat {
        let t = min(max(scrollOffset, 0), 160) / 160
        return 1 - t * 0.6   // shrinks to 40%
    }

    var body: some View {
        ZStack {
            Stem.cream.ignoresSafeArea()

            // Single ScrollView so the whole screen moves together.
            ScrollView {
                VStack(spacing: 8) {
                    // Invisible offset detector at the top of the scroll content.
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: -proxy.frame(in: .named("splitterScroll")).minY
                        )
                    }
                    .frame(height: 0)

                    // Player header (compact + collapsing via scroll offset).
                    Group {
                        if model.isReady {
                            PlayerHeaderView(model: model)
                        } else {
                            DeviceCircleView(model: model, onLoad: onImport)
                        }
                    }
                    .frame(maxWidth: model.isReady ? PlayerHeaderMetrics.readyDiameter : PlayerHeaderMetrics.idleDiameter)
                    .frame(height: (model.isReady ? PlayerHeaderMetrics.readyDiameter : PlayerHeaderMetrics.idleDiameter) * headerScale)
                    .scaleEffect(headerScale, anchor: .top)
                    .animation(.easeOut(duration: 0.15), value: model.isReady)
                    .accessibilityIdentifier("splitter.header")

                    // Master spectrogram overview.
                    if model.isReady {
                        VStack(spacing: 4) {
                            SpectrogramLane(image: masterImage, envelope: [],
                                            progress: model.progress, duration: model.duration,
                                            grid: model.measureGrid,
                                            height: PlayerHeaderMetrics.masterLaneHeight) { p in
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
                        .accessibilityIdentifier("splitter.overview")
                    }

                    TransportView(model: model)

                    if model.isReady {
                        LoopControlBar(model: model)
                            .disabled(!model.isReady || model.isProcessing)
                            .padding(.horizontal, 18)
                            .accessibilityIdentifier("loop.bar")
                    }

                    // Stem panels — no longer in a nested ScrollView.
                    VStack(spacing: 10) {
                        ForEach(Stem.stemOrder, id: \.self) { stem in
                            StemRowView(model: model, stem: stem)
                                .disabled(!model.isReady || model.isProcessing)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .coordinateSpace(name: "splitterScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
        }
        // Title bar stays pinned above the scroll content.
        .safeAreaInset(edge: .top) {
            HStack(spacing: 12) {
                Text(model.isReady && !model.songTitle.isEmpty ? model.songTitle : "stemacle")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.isReady ? Stem.ink : Stem.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
                    .accessibilityIdentifier("splitter.title")
                Spacer()
                Button(action: onImport) {
                    Image(systemName: "plus.circle").foregroundStyle(Stem.purple)
                        .frame(width: Stem.minimumHitTarget, height: Stem.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("o", modifiers: .command)
                .accessibilityIdentifier("splitter.add")
            }
            .font(.system(size: 17))
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .background(Stem.cream.opacity(0.94).ignoresSafeArea(edges: .top))
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Stem.purple.opacity(0.35), lineWidth: 2)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL, .audio], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
        .foregroundStyle(Stem.ink)
        .task(id: model.loadGeneration) {
            masterImage = makeSpectrogramImage(model.masterSpectrogram)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                Task { await model.loadFile(url) }
            }
            return true
        }
        return false
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
                        .accessibilityIdentifier("splitter.progress")
                    } else {
                        ProgressView().controlSize(.large)
                            .accessibilityIdentifier("splitter.progress")
                    }
                } else {
                    Button(action: onLoad) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Stem.purple)
                            .frame(width: Stem.minimumHitTarget, height: Stem.minimumHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("splitter.load")
                }
                Text(model.status)
                    .font(.footnote).foregroundStyle(Stem.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier("splitter.status")
                if !model.isProcessing, let demo = Bundle.main.url(forResource: "demo", withExtension: "wav") {
                    Button("try a sample") { Task { await model.loadFile(demo) } }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Stem.purple)
                        .frame(minHeight: Stem.minimumHitTarget)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("splitter.sample")
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
                        .frame(maxWidth: .infinity, minHeight: Stem.minimumHitTarget)
                        .background(active ? Stem.amber.opacity(0.28) : Stem.creamDeep.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("loop.all.\(label)")
                }
            }
        }
    }

    private func pill(_ text: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(text, action: action)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(minHeight: Stem.minimumHitTarget)
            .background(on ? Stem.purple.opacity(0.16) : Stem.creamDeep.opacity(0.5))
            .foregroundStyle(on ? Stem.purple : Stem.inkSoft)
            .clipShape(Capsule())
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityIdentifier("loop.\(text.replacingOccurrences(of: " ", with: ".").lowercased())")
    }
}

struct TransportView: View {
    @ObservedObject var model: StemPlayerViewModel

    var body: some View {
        HStack(spacing: PlayerHeaderMetrics.transportSpacing) {
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
                .frame(width: Stem.minimumHitTarget, height: Stem.minimumHitTarget)
                // Whole 44pt frame is tappable, not just the centered glyph.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transport.\(name)")
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
            // Spectrogram / waveform lane with tap-to-seek and scrolling window.
            SpectrogramLane(image: laneImage,
                            envelope: model.stemEnvelopes[stem] ?? [],
                            progress: model.progress, duration: model.duration,
                            grid: model.measureGrid) { p in
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
        .accessibilityIdentifier("stem.row.\(stem)")
        .task(id: model.loadGeneration) {
            laneImage = makeSpectrogramImage(model.spectrograms[stem] ?? [])
        }
    }

    private func iconToggle(_ name: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 14))
                .foregroundStyle(on ? Stem.purple : Stem.inkSoft)
                .frame(width: Stem.minimumHitTarget, height: Stem.minimumHitTarget)
                .background(on ? Stem.purple.opacity(0.12) : .clear)
                .clipShape(Circle())
                // Off-state background is .clear, so without this only the 14pt
                // glyph would be tappable — make the whole circle live.
                .contentShape(Circle())
        }.buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        ZStack {
            Stem.cream.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Settings").font(.system(size: 22, weight: .semibold, design: .rounded))
                        .padding(.top, 10)

                    Text("Your music stays on this device. Stemacle does not use accounts, analytics, or uploads.")
                        .font(.footnote)
                        .foregroundStyle(Stem.inkSoft)
                        .lineSpacing(2)

                    VStack(spacing: 0) {
                        SettingsRow(title: "App Settings", systemImage: "gearshape",
                                    subtitle: "Notifications, files, and system permissions") {
                            openAppSettings()
                        }
                        Divider().padding(.leading, 54)
                        SettingsLinkRow(title: "Privacy Policy", systemImage: "hand.raised",
                                        subtitle: "Plain-language privacy details",
                                        url: URL(string: "https://stemacle.com/privacy/")!)
                        Divider().padding(.leading, 54)
                        SettingsLinkRow(title: "Terms of Use", systemImage: "doc.text",
                                        subtitle: "Your responsibilities and app terms",
                                        url: URL(string: "https://stemacle.com/terms/")!)
                        Divider().padding(.leading, 54)
                        SettingsLinkRow(title: "Support", systemImage: "questionmark.circle",
                                        subtitle: "Help, contact, and review links",
                                        url: URL(string: "https://stemacle.com/support/")!)
                        Divider().padding(.leading, 54)
                        SettingsRow(title: "Rate Stemacle", systemImage: "star",
                                    subtitle: "Tell the App Store how it feels") {
                            requestReview()
                        }
                    }
                    .background(Stem.cream.opacity(0.68))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Stem.creamDeep, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("settings.publicRows")

                    Text("Stemacle separates audio locally. Quality can vary by song, but your tracks stay yours.")
                        .font(.caption)
                        .foregroundStyle(Stem.inkSoft)
                        .lineSpacing(2)
                        .padding(.top, 2)
                }
                .padding(20)
            }
        }
        .foregroundStyle(Stem.ink)
    }

    private func openAppSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #elseif os(macOS)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        #endif
    }
}

struct SettingsRow: View {
    let title: String
    let systemImage: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Stem.purple)
                    .frame(width: 32, height: Stem.minimumHitTarget)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(Stem.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Stem.inkSoft)
            }
            .frame(minHeight: Stem.minimumHitTarget)
            .padding(.horizontal, 12)
            // Whole row is tappable — without this the transparent Spacer gap
            // between the title and the chevron is dead to touch.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.\(title.replacingOccurrences(of: " ", with: ".").lowercased())")
    }
}

struct SettingsLinkRow: View {
    let title: String
    let systemImage: String
    let subtitle: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Stem.purple)
                    .frame(width: 32, height: Stem.minimumHitTarget)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(Stem.inkSoft)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Stem.inkSoft)
            }
            .frame(minHeight: Stem.minimumHitTarget)
            .padding(.horizontal, 12)
            // Whole row opens the link — the Spacer gap would otherwise be dead.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.\(title.replacingOccurrences(of: " ", with: ".").lowercased())")
    }
}
