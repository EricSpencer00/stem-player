import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private let stemaclePaper = Color(red: 0.93, green: 0.89, blue: 0.80)
private let stemacleRaised = Color(red: 0.97, green: 0.94, blue: 0.86)
private let stemacleInk = Color(red: 0.15, green: 0.12, blue: 0.15)
private let stemacleMuted = Color(red: 0.47, green: 0.41, blue: 0.38)
private let stemaclePlum = Color(red: 0.34, green: 0.13, blue: 0.32)
private let stemacleLine = Color(red: 0.72, green: 0.66, blue: 0.58).opacity(0.65)

@main
struct StemacleMacApp: App {
    @StateObject private var bridge = StemacleNativeBridge()

    var body: some Scene {
        WindowGroup("Stemacle") {
            StemacleMacShell(bridge: bridge)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandMenu("Stemacle") {
                Button("Command Palette") {
                    bridge.sendCommand("command-palette")
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Add Audio Files") {
                    bridge.chooseAudioFilesFromMenu()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Add Folder") {
                    bridge.chooseAudioFolderFromMenu()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Rescan Library") {
                    bridge.rescanLibraryFromMenu()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Open Stem Splitter") {
                    bridge.showSplitter()
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Open Stem Shuffle") {
                    bridge.showShuffle()
                }
                .keyboardShortcut("2", modifiers: [.command])

                Divider()

                Button("Reveal Stemacle Data") {
                    bridge.revealApplicationSupportFromMenu()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Reload Splitter") {
                    bridge.reloadSplitterFromMenu()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Clear Desktop State") {
                    bridge.clearDesktopStateFromMenu()
                }
            }
        }
    }
}

enum StemacleMacRoute: String, CaseIterable, Identifiable {
    case library
    case splitter
    case shuffle
    case queue
    case releases
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .splitter: return "Stem Splitter"
        case .shuffle: return "Stem Shuffle"
        case .queue: return "Queue"
        case .releases: return "Releases"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "music.note.list"
        case .splitter: return "waveform"
        case .shuffle: return "shuffle"
        case .queue: return "list.bullet.rectangle"
        case .releases: return "square.and.arrow.down"
        case .settings: return "slider.horizontal.3"
        }
    }

    static let sidebarRoutes: [StemacleMacRoute] = [.library, .splitter, .shuffle, .settings]

    var mergedDestination: StemacleMacRoute {
        switch self {
        case .queue:
            return .library
        case .releases:
            return .settings
        default:
            return self
        }
    }
}

struct StemacleMacShell: View {
    @ObservedObject var bridge: StemacleNativeBridge
    @State private var selection: StemacleMacRoute? = .library
    @State private var selectedTrackID: StemacleTrack.ID?

    var body: some View {
        NavigationSplitView {
            StemacleMacSidebar(selection: $selection, summary: bridge.desktopSummary)
        } detail: {
            switch selection ?? .library {
            case .library:
                StemacleMacLibraryView(
                    bridge: bridge,
                    selectedTrackID: $selectedTrackID,
                    openSelectedTrack: {
                        guard let selectedTrackID else { return }
                        selection = .splitter
                        bridge.openSelectedTrackInSplitter(selectedTrackID)
                    }
                )
            case .splitter:
                StemacleMacSplitterView(bridge: bridge)
            case .shuffle:
                StemacleMacShuffleView()
            case .queue:
                StemacleMacQueueView(bridge: bridge)
            case .releases:
                StemacleMacReleaseView(bridge: bridge)
            case .settings:
                StemacleMacSettingsView(bridge: bridge)
            }
        }
        .background(stemaclePaper)
        .onReceive(bridge.$requestedRoute) { route in
            guard let route else { return }
            selection = route.mergedDestination
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    bridge.chooseAudioFilesFromMenu()
                    selection = .library
                } label: {
                    Label("Add Audio", systemImage: "waveform.badge.plus")
                }

                Button {
                    bridge.chooseAudioFolderFromMenu()
                    selection = .library
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    bridge.showSplitter()
                } label: {
                    Label("Open Splitter", systemImage: "waveform")
                }

                Button {
                    bridge.showShuffle()
                } label: {
                    Label("Open Shuffle", systemImage: "shuffle")
                }
            }
        }
    }
}

struct StemacleMacSidebar: View {
    @Binding var selection: StemacleMacRoute?
    let summary: StemacleDesktopSummary

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(StemacleMacRoute.sidebarRoutes) { route in
                    Button {
                        selection = route
                    } label: {
                        Label(route.title, systemImage: route.systemImage)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selection == route ? stemacleInk.opacity(0.82) : Color.clear)
                            )
                            .foregroundStyle(selection == route ? stemacleRaised : stemacleInk.opacity(0.72))
                            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Stemacle")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(stemaclePlum)
                Text(summary.storageReady ? "local library ready" : "preparing storage")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(stemacleMuted)
                Text(summary.countText)
                    .font(.caption2)
                    .foregroundStyle(stemacleMuted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 238, max: 280)
        .scrollContentBackground(.hidden)
        .background(stemaclePaper)
    }
}

struct StemacleMacLibraryView: View {
    @ObservedObject var bridge: StemacleNativeBridge
    @Binding var selectedTrackID: StemacleTrack.ID?
    let openSelectedTrack: () -> Void

    var body: some View {
        StemacleMacPage(title: "Library", eyebrow: bridge.desktopSummary.statusText) {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    Button {
                        bridge.chooseAudioFilesFromMenu()
                    } label: {
                        Label("Audio", systemImage: "waveform.badge.plus")
                    }

                    Button {
                        bridge.chooseAudioFolderFromMenu()
                    } label: {
                        Label("Folder", systemImage: "folder.badge.plus")
                    }

                    Button("Open") {
                        openSelectedTrack()
                    }
                    .disabled(selectedTrackID == nil)

                    Spacer()

                    Button {
                        bridge.rescanLibraryFromMenu()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)

                ZStack {
                    Table(bridge.tracks, selection: $selectedTrackID) {
                        TableColumn("Track") { track in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(stemacleInk)
                                Text(track.url.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundStyle(stemacleMuted)
                                    .lineLimit(1)
                            }
                        }
                        TableColumn("Kind") { track in
                            Text(track.sourceKindLabel)
                                .foregroundStyle(stemacleMuted)
                        }
                        .width(72)
                        TableColumn("Added") { track in
                            Text(track.addedAt, style: .relative)
                                .foregroundStyle(stemacleMuted)
                        }
                        .width(90)
                    }

                    if bridge.tracks.isEmpty {
                        ContentUnavailableView(
                            "Drop audio into Stemacle",
                            systemImage: "waveform.badge.plus",
                            description: Text("Add files or folders to index a local library.")
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Queue")
                                .font(.headline)
                                .foregroundStyle(stemacleInk)
                            Text("Analysis, downloads, and exports stay visible inside the library.")
                                .font(.caption)
                                .foregroundStyle(stemacleMuted)
                        }
                        Spacer()
                        Text("\(bridge.queue.count) jobs")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(stemacleMuted)
                    }

                    if bridge.queue.isEmpty {
                        ContentUnavailableView(
                            "No jobs",
                            systemImage: "list.bullet.rectangle",
                            description: Text("Analysis, downloads, and exports appear here.")
                        )
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(bridge.queue) { job in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(job.kind.capitalized)
                                                .font(.body.weight(.semibold))
                                            Spacer()
                                            Text(job.status)
                                                .foregroundStyle(job.status == "failed" ? Color.orange : stemacleMuted)
                                        }
                                        Text(job.message.isEmpty ? job.createdAt : job.message)
                                            .font(.caption)
                                            .foregroundStyle(stemacleMuted)
                                    }
                                    .padding(.vertical, 8)

                                    if job.id != bridge.queue.last?.id {
                                        Divider().overlay(stemacleLine)
                                    }
                                }
                            }
                        }
                        .frame(minHeight: 160, maxHeight: 260)
                    }
                }
            }
        }
    }
}

struct StemacleMacSplitterView: View {
    @ObservedObject var bridge: StemacleNativeBridge

    var body: some View {
        StemacleMacPage(title: "Stem Splitter", eyebrow: "local stem work") {
            StemacleSplitterPane(bridge: bridge)
        }
    }
}

struct StemacleSplitterPane: View {
    @ObservedObject var bridge: StemacleNativeBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Desktop splitter", systemImage: "waveform")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(stemacleMuted)
                Spacer()
                Text("desktop shell, web splitter")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(stemacleMuted)
            }

            StemacleWebSplitter(bridge: bridge, initialURLString: "stemacle://app/app/index.html")
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(stemaclePaper)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(stemacleLine, lineWidth: 1)
                )
        )
    }
}

private struct MacShuffleTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let bpm: Int
    let key: String
}

private enum MacMixDeck: String, CaseIterable, Identifiable {
    case track1 = "1"
    case track2 = "2"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .track1: return "Track 1"
        case .track2: return "Track 2"
        }
    }

    var tint: Color {
        switch self {
        case .track1: return stemaclePlum
        case .track2: return Color(red: 0.82, green: 0.51, blue: 0.2)
        }
    }

    var opposite: MacMixDeck {
        self == .track1 ? .track2 : .track1
    }
}

struct StemacleMacShuffleView: View {
    @State private var track1 = MacShuffleTrack(id: "sample-1", title: "Stem Sample 1", bpm: 122, key: "Am")
    @State private var track2 = MacShuffleTrack(id: "sample-2", title: "Stem Sample 2", bpm: 124, key: "C")
    @State private var stemSources: [String: MacMixDeck] = [
        "vocals": .track1,
        "bass": .track1,
        "drums": .track2,
        "melody": .track2
    ]
    @State private var isPlaying = false
    @State private var syncedBPM = 123
    @State private var trackSettingsDeck: MacMixDeck?
    @State private var nextMixHint = "Next mix queues automatically"

    private let mixStemOrder = ["vocals", "bass", "drums", "melody"]
    private let pool = [
        MacShuffleTrack(id: "sample-1", title: "Stem Sample 1", bpm: 122, key: "Am"),
        MacShuffleTrack(id: "sample-2", title: "Stem Sample 2", bpm: 124, key: "C"),
        MacShuffleTrack(id: "sample-3", title: "Stem Sample 3", bpm: 118, key: "Dm"),
    ]

    var body: some View {
        VStack(spacing: 18) {
            macMixStatusBar

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                macTrackPad(deck: .track1, track: track1)
                macTrackPad(deck: .track2, track: track2)
                ForEach(mixStemOrder, id: \.self) { stemID in
                    macStemPad(stemID: stemID)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $trackSettingsDeck) { deck in
            macTrackSettingsSheet(deck: deck)
        }
    }

    private var macMixStatusBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: "link")
                        .font(.caption2.weight(.bold))
                    Text("\(syncedBPM)")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    Text("bpm")
                        .font(.caption2)
                        .foregroundStyle(stemaclePlum.opacity(0.65))
                }
                .foregroundStyle(stemaclePlum)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(stemaclePlum.opacity(0.08))
                        .overlay(Capsule(style: .continuous).stroke(stemaclePlum.opacity(0.2), lineWidth: 1))
                )

                Spacer()

                Button(action: shufflePair) {
                    Image(systemName: "shuffle")
                        .font(.callout.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(stemacleInk.opacity(0.65))
                .background(Circle().fill(stemaclePaper))
                .overlay(Circle().stroke(stemacleLine, lineWidth: 1))
                .help("Shuffle to next compatible pair")

                Button { isPlaying.toggle() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(stemacleRaised)
                .background(Circle().fill(stemacleInk))
                .help(isPlaying ? "Pause" : "Play")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(stemaclePaper)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(stemacleLine, lineWidth: 1))
            )

            if !nextMixHint.isEmpty {
                Text(nextMixHint)
                    .font(.caption2)
                    .foregroundStyle(stemacleMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func macTrackPad(deck: MacMixDeck, track: MacShuffleTrack) -> some View {
        Button { trackSettingsDeck = deck } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(deck.label)
                        .font(.caption2.weight(.black))
                        .textCase(.uppercase)
                        .foregroundStyle(deck.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule(style: .continuous).fill(deck.tint.opacity(0.12)))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(stemacleInk.opacity(0.3))
                }
                Text(track.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(stemacleInk)
                HStack(spacing: 4) {
                    Text("\(track.bpm) bpm")
                    Text("·").foregroundStyle(stemacleMuted.opacity(0.5))
                    Text(track.key)
                }
                .font(.caption)
                .foregroundStyle(stemacleMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .padding(14)
            .background(macTrackPadBackground(deck: deck))
        }
        .buttonStyle(.plain)
    }

    private func macStemPad(stemID: String) -> some View {
        let source = stemSources[stemID] ?? .track1
        let accent = macStemAccent(stemID)
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                stemSources[stemID] = source == .track1 ? .track2 : .track1
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(macStemTitle(stemID), systemImage: macStemSymbol(stemID))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)

                Text(source.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(source.tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(source.tint.opacity(0.12)))
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .padding(14)
            .background(macStemPadBackground(accent: accent))
        }
        .buttonStyle(.plain)
        .help("Click to move \(macStemTitle(stemID)) to \(source.opposite.label)")
    }

    private func macTrackPadBackground(deck: MacMixDeck) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(stemacleRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(deck.tint.opacity(0.3), lineWidth: 1.5)
            )
    }

    private func macStemPadBackground(accent: Color) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(accent.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(0.25), lineWidth: 1.5)
            )
    }

    private func macStemTitle(_ stemID: String) -> String {
        switch stemID {
        case "vocals": return "Vocals"
        case "bass": return "Bass"
        case "drums": return "Drums"
        case "melody": return "Melody"
        default: return stemID.capitalized
        }
    }

    private func macStemSymbol(_ stemID: String) -> String {
        switch stemID {
        case "vocals": return "waveform"
        case "bass": return "waveform.badge.magnifyingglass"
        case "drums": return "metronome"
        case "melody": return "music.note"
        default: return "waveform"
        }
    }

    private func macStemAccent(_ stemID: String) -> Color {
        switch stemID {
        case "vocals": return stemaclePlum
        case "bass": return Color(red: 0.18, green: 0.34, blue: 0.36)
        case "drums": return Color(red: 0.54, green: 0.24, blue: 0.34)
        case "melody": return Color(red: 0.82, green: 0.51, blue: 0.2)
        default: return stemaclePlum
        }
    }

    private func macTrackSettingsSheet(deck: MacMixDeck) -> some View {
        let track = deck == .track1 ? track1 : track2
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(deck.label)
                        .font(.caption2.weight(.black))
                        .textCase(.uppercase)
                        .foregroundStyle(deck.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule(style: .continuous).fill(deck.tint.opacity(0.12)))
                    Text(track.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(stemacleInk)
                        .lineLimit(2)
                }
                Spacer()
                Button("Done") { trackSettingsDeck = nil }
                    .foregroundStyle(stemaclePlum)
                    .fontWeight(.semibold)
                    .buttonStyle(.plain)
            }
            .padding(24)

            Divider().background(stemacleLine)

            VStack(spacing: 0) {
                macSettingsRow("Tempo", value: "\(track.bpm) bpm")
                Divider().background(stemacleLine)
                macSettingsRow("Key", value: track.key)
            }

            Spacer(minLength: 20)

            Button {
                shuffleTrack(for: deck)
                trackSettingsDeck = nil
            } label: {
                Label("Bring in a stronger match", systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(stemacleRaised)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(stemacleInk)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(minWidth: 340, minHeight: 260)
        .background(stemaclePaper)
    }

    private func macSettingsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(stemacleMuted)
            Spacer()
            Text(value)
                .foregroundStyle(stemacleInk)
        }
        .font(.callout)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func track(for deck: MacMixDeck) -> MacShuffleTrack {
        deck == .track1 ? track1 : track2
    }

    private func shuffleTrack(for deck: MacMixDeck) {
        let other = deck == .track1 ? track2 : track1
        let current = deck == .track1 ? track1 : track2
        let candidates = pool
            .filter { pool.count <= 2 || $0.id != current.id }
            .filter { $0.id != other.id }
            .sorted { macScoreCompatibility(left: $0, right: other) > macScoreCompatibility(left: $1, right: other) }
        guard let next = candidates.first else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            if deck == .track1 { track1 = next } else { track2 = next }
        }
        nextMixHint = "Brought in \(next.title) as a stronger match."
        refreshSync()
    }

    private func shufflePair() {
        guard pool.count >= 2 else { return }
        let bestPair = macRankBestPair()
        guard let pair = bestPair else {
            var candidates = pool
            track1 = candidates.removeFirst()
            track2 = candidates.first(where: { $0.id != track1.id }) ?? pool[1]
            refreshSync()
            return
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            track1 = pair.0
            track2 = pair.1
            stemSources = [
                "vocals": .track1,
                "bass": .track2,
                "drums": .track1,
                "melody": .track2
            ]
        }
        nextMixHint = "Queued · \(track1.title) × \(track2.title)"
        refreshSync()
    }

    private func macRankBestPair() -> (MacShuffleTrack, MacShuffleTrack)? {
        var best: (MacShuffleTrack, MacShuffleTrack)?
        var bestScore = -Double.infinity
        for i in 0..<pool.count {
            for j in (i + 1)..<pool.count {
                let score = macScoreCompatibility(left: pool[i], right: pool[j])
                if score > bestScore {
                    bestScore = score
                    best = (pool[i], pool[j])
                }
            }
        }
        return best
    }

    private func macScoreCompatibility(left: MacShuffleTrack, right: MacShuffleTrack) -> Double {
        let tempoDelta = abs(left.bpm - right.bpm)
        let tempoScore = max(0, 1 - Double(tempoDelta) / 24)
        return tempoScore * 100
    }

    private func refreshSync() {
        syncedBPM = Int(round(Double(track1.bpm + track2.bpm) / 2))
    }
}

struct StemacleMacQueueView: View {
    @ObservedObject var bridge: StemacleNativeBridge

    var body: some View {
        StemacleMacPage(title: "Queue", eyebrow: "\(bridge.queue.count) jobs") {
            List(bridge.queue) { job in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(job.kind.capitalized)
                            .font(.body.weight(.semibold))
                        Spacer()
                        Text(job.status)
                            .foregroundStyle(job.status == "failed" ? Color.orange : stemacleMuted)
                    }
                    Text(job.message.isEmpty ? job.createdAt : job.message)
                        .font(.caption)
                        .foregroundStyle(stemacleMuted)
                }
                .padding(.vertical, 6)
            }
            .overlay {
                if bridge.queue.isEmpty {
                    ContentUnavailableView(
                        "No jobs",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Analysis, downloads, and exports appear here.")
                    )
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

struct StemacleMacReleaseView: View {
    @ObservedObject var bridge: StemacleNativeBridge

    var body: some View {
        StemacleMacPage(title: "Releases", eyebrow: "public artifacts") {
            List(bridge.releases) { release in
                HStack(spacing: 16) {
                    StemacleReleaseArtwork(release: release)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(release.title)
                            .font(.body.weight(.semibold))
                        Text(release.detail)
                            .font(.caption)
                            .foregroundStyle(stemacleMuted)
                    }
                    Spacer()
                    Button(release.actionTitle) {
                        bridge.openRelease(release)
                    }
                }
                .padding(.vertical, 7)
            }
            .scrollContentBackground(.hidden)
        }
    }
}

struct StemacleMacSettingsView: View {
    @ObservedObject var bridge: StemacleNativeBridge

    var body: some View {
        StemacleMacPage(title: "Settings", eyebrow: "local storage") {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 18) {
                        GridRow {
                            Text("Data")
                                .foregroundStyle(stemacleMuted)
                            Text(bridge.desktopSummary.dataRoot)
                                .textSelection(.enabled)
                        }
                        GridRow {
                            Text("Mode")
                                .foregroundStyle(stemacleMuted)
                            Text("Local-first")
                        }
                        GridRow {
                            Text("Storage")
                                .foregroundStyle(stemacleMuted)
                            Text(bridge.desktopSummary.storageReady ? "Ready" : "Preparing")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("High-quality engine")
                            .font(.headline)
                            .foregroundStyle(stemacleInk)
                        Text("Fast preview runs entirely on-device and is always available. High-quality 4/6-stem separation uses a local copy of Demucs in the downloadable desktop build — install Demucs and ffmpeg, then reopen Stemacle to unlock it.")
                            .font(.callout)
                            .foregroundStyle(stemacleMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Link("High-quality setup guide", destination: URL(string: "https://stemacle.com/support/#high-quality")!)
                            .font(.callout.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Releases")
                                    .font(.headline)
                                    .foregroundStyle(stemacleInk)
                                Text("Release downloads and notes now live with the settings surface.")
                                    .font(.caption)
                                    .foregroundStyle(stemacleMuted)
                            }
                            Spacer()
                            Text("\(bridge.releases.count) artifacts")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(stemacleMuted)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
                            ForEach(bridge.releases) { release in
                                VStack(alignment: .leading, spacing: 10) {
                                    StemacleReleaseArtwork(release: release, size: 48)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(release.title)
                                            .font(.callout.weight(.semibold))
                                        Text(release.detail)
                                            .font(.caption)
                                            .foregroundStyle(stemacleMuted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Button(release.actionTitle) {
                                        bridge.openRelease(release)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(stemaclePaper)
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(stemacleLine, lineWidth: 1))
                                )
                            }
                        }
                    }

                    HStack {
                        Button("Reveal Stemacle Data") {
                            bridge.revealApplicationSupportFromMenu()
                        }
                        Button("Clear Desktop State", role: .destructive) {
                            bridge.clearDesktopStateFromMenu()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

struct StemacleMacPage<Content: View>: View {
    let title: String
    let eyebrow: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(stemacleMuted)
                Text(title)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(stemacleInk)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(stemacleRaised)
    }
}

struct StemacleDesktopAppIcon: View {
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: StemaclePaths.webRoot().appendingPathComponent("assets/stemacle-tentacle.png")) {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "waveform.circle.fill")
                    .resizable()
            }
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(9, size * 0.28), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: max(9, size * 0.28), style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.22, green: 0.17, blue: 0.12).opacity(0.18), radius: 6, y: 2)
        .accessibilityLabel("Stemacle app icon")
    }
}

struct StemacleReleaseArtwork: View {
    let release: StemacleReleaseArtifact
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            if let image = NSImage(contentsOf: StemaclePaths.webRoot().appendingPathComponent(release.artPath)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: release.systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(stemaclePlum)
            }
        }
        .frame(width: size, height: size)
        .background(stemaclePaper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(stemacleLine, lineWidth: 1)
        )
        .shadow(color: Color(red: 0.22, green: 0.17, blue: 0.12).opacity(0.12), radius: 8, y: 3)
        .accessibilityHidden(true)
    }
}

struct StemacleWebSplitter: NSViewRepresentable {
    @ObservedObject var bridge: StemacleNativeBridge
    var initialURLString = "stemacle://app/app/index.html"

    func makeCoordinator() -> Coordinator {
        Coordinator(
            schemeHandler: StemacleSchemeHandler(root: StemaclePaths.webRoot()),
            navigationDelegate: StemacleNavigationDelegate()
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: "stemacle")
        configuration.userContentController.addUserScript(WKUserScript(
            source: StemacleNativeBridge.injectedJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        configuration.userContentController.addScriptMessageHandler(
            bridge,
            contentWorld: .page,
            name: "stemacleNative"
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator.navigationDelegate
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        bridge.attach(webView)
        webView.load(URLRequest(url: URL(string: initialURLString)!))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        bridge.attach(webView)
    }

    final class Coordinator {
        let schemeHandler: StemacleSchemeHandler
        let navigationDelegate: StemacleNavigationDelegate

        init(schemeHandler: StemacleSchemeHandler, navigationDelegate: StemacleNavigationDelegate) {
            self.schemeHandler = schemeHandler
            self.navigationDelegate = navigationDelegate
        }
    }
}

final class StemacleNavigationDelegate: NSObject, WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if url.scheme == "stemacle" {
            decisionHandler(.allow)
            return
        }

        if let internalURL = internalStemacleRoute(for: url) {
            webView.load(URLRequest(url: internalURL))
            decisionHandler(.cancel)
            return
        }

        if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    private func internalStemacleRoute(for url: URL) -> URL? {
        guard url.scheme == "https" || url.scheme == "http",
              url.host == "stemacle.com"
        else {
            return nil
        }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty || path == "app" || path == "app/index.html" {
            return URL(string: "stemacle://app/app/index.html")
        }

        if path == "apps/stem-shuffle" || path == "apps/stem-shuffle/index.html" {
            return URL(string: "stemacle://app/apps/stem-shuffle/index.html")
        }

        return nil
    }
}

final class StemacleSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let fileURL = fileURL(for: requestURL)
        else {
            urlSchemeTask.didFailWithError(StemacleSchemeError.notFound)
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType(for: fileURL),
                expectedContentLength: data.count,
                textEncodingName: textEncodingName(for: fileURL)
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func fileURL(for requestURL: URL) -> URL? {
        var path = requestURL.path
        if path.isEmpty || path == "/" {
            path = "/index.html"
        } else if path.hasSuffix("/") {
            path += "index.html"
        }

        let relativePath = String(path.drop(while: { $0 == "/" }))
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : "\(root.path)/"
        guard candidate.path.hasPrefix(rootPath) else { return nil }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let index = candidate.appendingPathComponent("index.html")
                return FileManager.default.fileExists(atPath: index.path) ? index : nil
            }
            return candidate
        }

        return nil
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }

    private func textEncodingName(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "html", "js", "mjs", "css", "json": return "utf-8"
        default: return nil
        }
    }
}

enum StemacleSchemeError: LocalizedError {
    case notFound

    var errorDescription: String? {
        "Stemacle could not find that bundled app resource."
    }
}

@MainActor
final class StemacleNativeBridge: NSObject, ObservableObject, WKScriptMessageHandlerWithReply {
    static let injectedJavaScript = """
    (() => {
      if (window.stemacleNative) return;

      const stateListeners = new Set();
      const commandListeners = new Set();
      const invoke = (name, ...args) => window.webkit.messageHandlers.stemacleNative.postMessage({ name, args });

      window.stemacleNative = {
        platform: 'darwin',
        getDesktopState: () => invoke('getDesktopState'),
        pickAudioFiles: () => invoke('pickAudioFiles'),
        pickAudioFolder: () => invoke('pickAudioFolder'),
        addLibraryPaths: (paths) => invoke('addLibraryPaths', paths),
        rescanLibrary: () => invoke('rescanLibrary'),
        enqueueAnalysis: (trackId, options) => invoke('enqueueAnalysis', trackId, options || {}),
        enqueueDownload: (url) => invoke('enqueueDownload', url),
        saveSession: (session) => invoke('saveSession', session || {}),
        exportTrack: (trackId, options) => invoke('exportTrack', trackId, options || {}),
        readTrackFile: (trackId) => invoke('readTrackFile', trackId),
        revealPath: (path) => invoke('revealPath', path),
        clearDesktopState: () => invoke('clearDesktopState'),
        onStateChanged: (handler) => {
          stateListeners.add(handler);
          invoke('getDesktopState').then((state) => handler(state));
          return () => stateListeners.delete(handler);
        },
        onCommand: (handler) => {
          commandListeners.add(handler);
          return () => commandListeners.delete(handler);
        }
      };

      window.__stemacleNativeStateChanged = (state) => {
        stateListeners.forEach((handler) => handler(state));
      };

      window.__stemacleNativeCommand = (command) => {
        commandListeners.forEach((handler) => handler(command));
      };
    })();
    """

    @Published private(set) var desktopSummary = StemacleDesktopSummary()
    @Published private(set) var tracks: [StemacleTrack] = []
    @Published private(set) var roots: [StemacleRoot] = []
    @Published private(set) var queue: [StemacleJob] = []
    @Published private(set) var sessions: [[String: Any]] = []
    @Published private(set) var exports: [[String: Any]] = []
    @Published private(set) var releases: [StemacleReleaseArtifact] = StemacleReleaseArtifact.all
    @Published var requestedRoute: StemacleMacRoute?

    private weak var webView: WKWebView?
    private let createdAt = ISO8601DateFormatter().string(from: Date())
    private let fileManager = FileManager.default
    private let appSupportRoot: URL

    override init() {
        appSupportRoot = Self.defaultApplicationSupportRoot()
        super.init()
        _ = prepareApplicationSupportDirectories()
        refreshDesktopSummary(from: desktopState())
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func navigate(to urlString: String) {
        guard let url = URL(string: urlString) else { return }
        webView?.load(URLRequest(url: url))
    }

    private func navigateToSplitter(urlString: String) {
        requestedRoute = .splitter
        navigate(to: urlString)
    }

    func showSplitter() {
        navigateToSplitter(urlString: "stemacle://app/app/index.html")
    }

    func showShuffle() {
        requestedRoute = .shuffle
        navigate(to: "stemacle://app/apps/stem-shuffle/index.html")
    }

    func openSelectedTrackInSplitter(_ trackId: String) {
        requestedRoute = .splitter
        evaluate("sessionStorage.setItem('stemacle:pendingTrackId', \(jsonString(trackId)))")
        navigate(to: "stemacle://app/app/index.html")
    }

    func openRelease(_ release: StemacleReleaseArtifact) {
        NSWorkspace.shared.open(release.url)
    }

    func sendCommand(_ command: String) {
        evaluate("__stemacleNativeCommand(\(jsonString(command)))")
    }

    func chooseAudioFilesFromMenu() {
        _ = chooseAudioFiles()
    }

    func chooseAudioFolderFromMenu() {
        _ = chooseAudioFolder()
    }

    func rescanLibraryFromMenu() {
        _ = rescanLibrary()
    }

    func revealApplicationSupportFromMenu() {
        _ = revealPath(appSupportRoot.path)
    }

    func reloadSplitterFromMenu() {
        webView?.reload()
    }

    func clearDesktopStateFromMenu() {
        tracks.removeAll()
        roots.removeAll()
        queue.removeAll()
        sessions.removeAll()
        exports.removeAll()
        emitState()
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        Task { @MainActor in
            let result = self.handle(message.body)
            replyHandler(result.value, result.error)
        }
    }

    private func handle(_ body: Any) -> (value: Any?, error: String?) {
        guard let payload = body as? [String: Any],
              let name = payload["name"] as? String
        else {
            return (nil, "Invalid native bridge message.")
        }
        let args = payload["args"] as? [Any] ?? []

        switch name {
        case "getDesktopState":
            return (desktopState(), nil)
        case "pickAudioFiles":
            return (chooseAudioFiles(), nil)
        case "pickAudioFolder":
            return (chooseAudioFolder(), nil)
        case "addLibraryPaths":
            let paths = args.first as? [String] ?? []
            return (addLibraryPaths(paths), nil)
        case "rescanLibrary":
            return (rescanLibrary(), nil)
        case "enqueueAnalysis":
            let trackId = args.first as? String ?? ""
            let options = args.dropFirst().first as? [String: Any] ?? [:]
            return (enqueueAnalysis(trackId: trackId, options: options), nil)
        case "enqueueDownload":
            let url = args.first as? String ?? ""
            return (enqueueDownload(url: url), nil)
        case "saveSession":
            let session = args.first as? [String: Any] ?? [:]
            return (saveSession(session), nil)
        case "exportTrack":
            let trackId = args.first as? String ?? ""
            let options = args.dropFirst().first as? [String: Any] ?? [:]
            return (exportTrack(trackId: trackId, options: options), nil)
        case "readTrackFile":
            let trackId = args.first as? String ?? ""
            return readTrackFile(trackId)
        case "revealPath":
            let path = args.first as? String ?? ""
            return (revealPath(path), nil)
        case "clearDesktopState":
            clearDesktopStateFromMenu()
            return (desktopState(), nil)
        default:
            return (nil, "Unknown native bridge action: \(name)")
        }
    }

    private func chooseAudioFiles() -> [[String: Any]] {
        let panel = NSOpenPanel()
        panel.title = "Add audio to Stemacle Library"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK else { return [] }
        return addURLs(panel.urls)
    }

    private func chooseAudioFolder() -> [[String: Any]] {
        let panel = NSOpenPanel()
        panel.title = "Add Stemacle Music Folder"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return [] }

        for url in panel.urls {
            roots.append(StemacleRoot(url: url))
        }
        return addURLs(panel.urls.flatMap(audioFiles(in:)))
    }

    private func addLibraryPaths(_ paths: [String]) -> [[String: Any]] {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        let audioURLs = urls.flatMap { url in
            isDirectory(url) ? audioFiles(in: url) : [url]
        }
        return addURLs(audioURLs)
    }

    private func addURLs(_ urls: [URL]) -> [[String: Any]] {
        var added: [StemacleTrack] = []
        for url in urls where isAudioFile(url) {
            let standardized = url.standardizedFileURL
            if !tracks.contains(where: { $0.url == standardized }) {
                let track = StemacleTrack(url: standardized)
                tracks.append(track)
                added.append(track)
            }
        }
        tracks.sort { $0.addedAt > $1.addedAt }
        emitState()
        return added.map { $0.dictionary(paths: cachePaths(for: $0)) }
    }

    private func rescanLibrary() -> [String: Any] {
        let rescanned = roots.flatMap { audioFiles(in: $0.url) }
        _ = addURLs(rescanned)
        return desktopState()
    }

    private func enqueueAnalysis(trackId: String, options: [String: Any]) -> [String: Any] {
        let quality = options["quality"] as? String ?? "fast-preview"
        var job = jobRecord(kind: "analysis", trackId: trackId)
        job.quality = quality
        job.status = "completed"
        job.progress = 1
        job.message = quality == "fast-preview"
            ? "Preview analysis is ready in the bundled splitter."
            : "High quality native analysis is queued for the desktop worker path."
        queue.insert(job, at: 0)
        emitState()
        return job.dictionary()
    }

    private func enqueueDownload(url: String) -> [String: Any] {
        var job = jobRecord(kind: "download", trackId: nil)
        job.url = url
        job.status = "failed"
        job.progress = 1
        job.message = "URL downloads need yt-dlp outside the App Store sandbox."
        job.error = "Install the Windows/Linux workbench or use a local audio file on macOS."
        queue.insert(job, at: 0)
        emitState()
        return job.dictionary()
    }

    private func saveSession(_ session: [String: Any]) -> [String: Any] {
        var record = session
        record["id"] = "session-\(Int(Date().timeIntervalSince1970 * 1000))"
        record["name"] = record["name"] ?? "Stemacle Mac session"
        record["savedAt"] = timestamp()
        sessions.insert(record, at: 0)
        emitState()
        return record
    }

    private func exportTrack(trackId: String, options: [String: Any]) -> [String: Any] {
        let record: [String: Any] = [
            "id": "export-\(Int(Date().timeIntervalSince1970 * 1000))",
            "trackId": trackId,
            "trackName": tracks.first(where: { $0.id == trackId })?.name ?? trackId,
            "kind": options["kind"] as? String ?? "stem-pack",
            "format": options["format"] as? String ?? "wav",
            "status": "planned",
            "createdAt": timestamp()
        ]
        exports.insert(record, at: 0)
        emitState()
        return record
    }

    private func readTrackFile(_ trackId: String) -> (value: Any?, error: String?) {
        guard let track = tracks.first(where: { $0.id == trackId }) else {
            return (nil, "Track was not found in the Mac library.")
        }

        do {
            let data = try Data(contentsOf: track.url)
            return ([
                "name": track.url.lastPathComponent,
                "mimeType": mimeType(for: track.url),
                "bytes": Array(data)
            ], nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func revealPath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    private func desktopState() -> [String: Any] {
        let appRoot = applicationSupportRoot()
        let updatedAt = timestamp()
        refreshDesktopSummary(from: [
            "updatedAt": updatedAt,
            "library": tracks,
            "libraryRoots": roots,
            "queue": queue.map { $0.dictionary() },
            "sessions": sessions,
            "exports": exports,
            "paths": ["dataRoot": appRoot.path],
            "storageReady": prepareApplicationSupportDirectories()
        ])

        return [
            "version": 4,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "platform": "macos",
            "localFirst": true,
            "storageReady": desktopSummary.storageReady,
            "library": tracks.map { $0.dictionary(paths: cachePaths(for: $0)) },
            "libraryRoots": roots.map { $0.dictionary(trackCount: tracks(in: $0).count) },
            "queue": queue.map { $0.dictionary() },
            "sessions": sessions,
            "exports": exports,
            "recentProjects": sessions,
            "tools": [
                "ffmpeg": ["available": false, "command": NSNull()],
                "ffprobe": ["available": false, "command": NSNull()],
                "demucs": ["available": false, "command": NSNull()],
                "ytDlp": ["available": false, "command": NSNull()]
            ],
            "paths": [
                "dataRoot": appRoot.path,
                "modelCacheRoot": appRoot.appendingPathComponent("model-cache").path,
                "stemCacheRoot": appRoot.appendingPathComponent("stem-cache").path,
                "analysisCacheRoot": appRoot.appendingPathComponent("analysis-cache").path,
                "exportRoot": appRoot.appendingPathComponent("exports").path,
                "downloadRoot": appRoot.appendingPathComponent("downloads").path
            ],
            "settings": [
                "downloadRoot": appRoot.appendingPathComponent("downloads").path,
                "localFirst": true
            ],
            "desktop": [
                "storageReady": desktopSummary.storageReady,
                "localFirst": true,
                "statusText": desktopSummary.statusText,
                "libraryCount": desktopSummary.libraryCount,
                "libraryRootCount": desktopSummary.libraryRootCount,
                "queueCount": desktopSummary.queueCount,
                "sessionCount": desktopSummary.sessionCount,
                "exportCount": desktopSummary.exportCount
            ],
            "modelCache": [
                "cacheRoot": appRoot.appendingPathComponent("model-cache").path,
                "models": [
                    ["id": "fast-preview", "label": "Fast Preview", "stems": 4, "status": "ready", "available": true],
                    ["id": "demucs-4stem", "label": "High Quality 4-Stem", "stems": 4, "status": "external", "available": false],
                    ["id": "demucs-6stem", "label": "High Quality 6-Stem", "stems": 6, "status": "external", "available": false],
                    ["id": "mdx-extra-q", "label": "MDX Extra Q", "stems": 4, "status": "external", "available": false]
                ]
            ]
        ]
    }

    private func emitState() {
        guard let json = jsonLiteral(desktopState()) else { return }
        evaluate("__stemacleNativeStateChanged(\(json))")
    }

    private func evaluate(_ source: String) {
        webView?.evaluateJavaScript("window.\(source);", completionHandler: nil)
    }

    private func jobRecord(kind: String, trackId: String?) -> StemacleJob {
        StemacleJob(
            id: "\(kind)-\(Int(Date().timeIntervalSince1970 * 1000))",
            kind: kind,
            status: "queued",
            progress: 0,
            message: "",
            createdAt: timestamp(),
            startedAt: timestamp(),
            finishedAt: timestamp(),
            trackId: trackId,
            trackName: trackId.flatMap { id in tracks.first(where: { $0.id == id })?.name ?? id }
        )
    }

    private func audioFiles(in folder: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, isAudioFile(url) else { return nil }
            return url
        }
    }

    private func isAudioFile(_ url: URL) -> Bool {
        ["mp3", "wav", "m4a", "aac", "ogg", "flac", "opus", "aiff", "aif"]
            .contains(url.pathExtension.lowercased())
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func tracks(in root: StemacleRoot) -> [StemacleTrack] {
        tracks.filter { $0.url.path.hasPrefix(root.url.path) }
    }

    private static func defaultApplicationSupportRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("Stemacle", isDirectory: true)
    }

    private func applicationSupportRoot() -> URL {
        _ = prepareApplicationSupportDirectories()
        return appSupportRoot
    }

    private func prepareApplicationSupportDirectories() -> Bool {
        let directories = [
            appSupportRoot,
            appSupportRoot.appendingPathComponent("model-cache", isDirectory: true),
            appSupportRoot.appendingPathComponent("stem-cache", isDirectory: true),
            appSupportRoot.appendingPathComponent("analysis-cache", isDirectory: true),
            appSupportRoot.appendingPathComponent("exports", isDirectory: true),
            appSupportRoot.appendingPathComponent("downloads", isDirectory: true)
        ]

        do {
            for directory in directories {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            return true
        } catch {
            return false
        }
    }

    private func refreshDesktopSummary(from state: [String: Any]) {
        let paths = state["paths"] as? [String: Any]
        desktopSummary = StemacleDesktopSummary(
            libraryCount: countItems(in: state["library"], fallback: tracks.count),
            libraryRootCount: countItems(in: state["libraryRoots"], fallback: roots.count),
            queueCount: countItems(in: state["queue"], fallback: queue.count),
            sessionCount: countItems(in: state["sessions"], fallback: sessions.count),
            exportCount: countItems(in: state["exports"], fallback: exports.count),
            dataRoot: paths?["dataRoot"] as? String ?? appSupportRoot.path,
            storageReady: state["storageReady"] as? Bool ?? false,
            lastUpdatedAt: state["updatedAt"] as? String ?? timestamp()
        )
    }

    private func countItems(in value: Any?, fallback: Int) -> Int {
        if let items = value as? [Any] {
            return items.count
        }
        return fallback
    }

    private func cachePaths(for track: StemacleTrack) -> [String: Any] {
        let root = applicationSupportRoot()
        let id = track.id.replacingOccurrences(of: "/", with: "-")
        let stemDir = root.appendingPathComponent("stem-cache").appendingPathComponent(id)
        let analysisRoot = root.appendingPathComponent("analysis-cache")
        let exportDir = root.appendingPathComponent("exports").appendingPathComponent(id)
        return [
            "stemDir": stemDir.path,
            "analysisFile": analysisRoot.appendingPathComponent("\(id).json").path,
            "manifestFile": analysisRoot.appendingPathComponent("\(id).manifest.json").path,
            "waveformFile": analysisRoot.appendingPathComponent("\(id).waveform.json").path,
            "exportDir": exportDir.path,
            "stemSets": [:]
        ]
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "m4a", "aac": return "audio/mp4"
        case "flac": return "audio/flac"
        case "ogg", "opus": return "audio/ogg"
        case "aiff", "aif": return "audio/aiff"
        default: return "application/octet-stream"
        }
    }

    private func jsonString(_ value: String) -> String {
        jsonLiteral(value) ?? "\"\""
    }

    private func jsonLiteral(_ value: Any) -> String? {
        if let string = value as? String,
           let data = try? JSONEncoder().encode(string) {
            return String(data: data, encoding: .utf8)
        }

        guard JSONSerialization.isValidJSONObject(["value": value]),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [])
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

struct StemacleDesktopSummary: Equatable {
    var libraryCount = 0
    var libraryRootCount = 0
    var queueCount = 0
    var sessionCount = 0
    var exportCount = 0
    var dataRoot = ""
    var storageReady = false
    var lastUpdatedAt = ""

    var statusText: String {
        storageReady ? "Local library ready" : "Preparing local storage"
    }

    var countText: String {
        "\(libraryCount) tracks • \(libraryRootCount) folders • \(queueCount) jobs • \(sessionCount) sessions • \(exportCount) exports"
    }
}

struct StemacleJob: Identifiable, Equatable {
    let id: String
    let kind: String
    var status: String
    var progress: Double
    var message: String
    let createdAt: String
    let startedAt: String
    let finishedAt: String
    var trackId: String?
    var trackName: String?
    var quality: String?
    var url: String?
    var error: String?

    func dictionary() -> [String: Any] {
        var value: [String: Any] = [
            "id": id,
            "kind": kind,
            "status": status,
            "progress": progress,
            "message": message,
            "createdAt": createdAt,
            "startedAt": startedAt,
            "finishedAt": finishedAt
        ]
        if let trackId {
            value["trackId"] = trackId
        }
        if let trackName {
            value["trackName"] = trackName
        }
        if let quality {
            value["quality"] = quality
        }
        if let url {
            value["url"] = url
        }
        if let error {
            value["error"] = error
        }
        return value
    }
}

struct StemacleReleaseArtifact: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let actionTitle: String
    let systemImage: String
    let artPath: String
    let url: URL

    static let all: [StemacleReleaseArtifact] = [
        StemacleReleaseArtifact(
            id: "web",
            title: "Open web app",
            detail: "Browser instrument on stemacle.com/app.",
            actionTitle: "Open",
            systemImage: "safari",
            artPath: "assets/release-icons/stemacle-release-icon-01.png",
            url: URL(string: "https://stemacle.com/app/")!
        ),
        StemacleReleaseArtifact(
            id: "mac-dmg",
            title: "Stemacle DMG",
            detail: "Apple Silicon installer image for v0.2.1.",
            actionTitle: "Download",
            systemImage: "opticaldiscdrive",
            artPath: "assets/release-icons/stemacle-release-icon-03.png",
            url: URL(string: "https://github.com/EricSpencer00/stem-player/releases/download/v0.2.1/Stemacle-0.2.1-arm64.dmg")!
        ),
        StemacleReleaseArtifact(
            id: "mac-zip",
            title: "App zip",
            detail: "Portable Apple Silicon app bundle for v0.2.1.",
            actionTitle: "Download",
            systemImage: "archivebox",
            artPath: "assets/release-icons/stemacle-release-icon-02.png",
            url: URL(string: "https://github.com/EricSpencer00/stem-player/releases/download/v0.2.1/Stemacle-0.2.1-arm64-mac.zip")!
        ),
        StemacleReleaseArtifact(
            id: "ios",
            title: "Get for iOS",
            detail: "Native iPhone release page.",
            actionTitle: "Open",
            systemImage: "iphone",
            artPath: "assets/stemacle-tentacle.png",
            url: URL(string: "https://stemacle.com/ios-coming-soon/")!
        ),
        StemacleReleaseArtifact(
            id: "github",
            title: "Latest GitHub release",
            detail: "Release notes and current public assets.",
            actionTitle: "Open",
            systemImage: "shippingbox",
            artPath: "assets/release-icons/stemacle-release-icon-05.png",
            url: URL(string: "https://github.com/EricSpencer00/stem-player/releases/latest")!
        ),
        StemacleReleaseArtifact(
            id: "repo",
            title: "Source repo",
            detail: "Public source and build files.",
            actionTitle: "Open",
            systemImage: "chevron.left.forwardslash.chevron.right",
            artPath: "assets/release-icons/stemacle-release-icon-06.png",
            url: URL(string: "https://github.com/EricSpencer00/stem-player")!
        )
    ]
}

struct StemacleTrack: Identifiable, Equatable {
    let url: URL
    let addedAt = Date()

    var id: String { url.standardizedFileURL.path }
    var name: String { url.lastPathComponent }
    var sourceKindLabel: String { "local" }

    func dictionary(paths: [String: Any]) -> [String: Any] {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return [
            "id": id,
            "name": name,
            "sourceKind": "macos",
            "path": url.path,
            "size": values?.fileSize ?? 0,
            "lastModified": values?.contentModificationDate?.timeIntervalSince1970 ?? 0,
            "addedAt": ISO8601DateFormatter().string(from: addedAt),
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "analysisStatus": "indexed",
            "duration": NSNull(),
            "sampleRate": NSNull(),
            "channels": NSNull(),
            "bpm": NSNull(),
            "key": NSNull(),
            "stemAvailability": [
                "preview": false,
                "demucs4": false,
                "demucs6": false,
                "mdxExtraQ": false
            ],
            "cache": paths,
            "analysis": [
                "lastQuality": NSNull(),
                "lastRunAt": NSNull(),
                "error": NSNull()
            ],
            "download": NSNull(),
            "errors": []
        ]
    }
}

struct StemacleRoot: Identifiable, Equatable {
    let url: URL
    let addedAt = Date()

    var id: String { url.standardizedFileURL.path }

    func dictionary(trackCount: Int) -> [String: Any] {
        [
            "id": id,
            "path": url.path,
            "addedAt": ISO8601DateFormatter().string(from: addedAt),
            "lastIndexedAt": ISO8601DateFormatter().string(from: Date()),
            "trackCount": trackCount
        ]
    }
}

enum StemaclePaths {
    static func webRoot() -> URL {
        let repo = repoRoot()
        let sourceDist = repo.appendingPathComponent("dist/native", isDirectory: true)
        if FileManager.default.fileExists(atPath: sourceDist.appendingPathComponent("index.html").path) {
            return sourceDist
        }

        if let resourceRoot = Bundle.main.resourceURL?.appendingPathComponent("repo/dist/native", isDirectory: true),
           FileManager.default.fileExists(atPath: resourceRoot.appendingPathComponent("index.html").path) {
            return resourceRoot
        }

        return repo.appendingPathComponent("native", isDirectory: true)
    }

    static func repoRoot() -> URL {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--repo-root"),
           arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }

        if let envRoot = ProcessInfo.processInfo.environment["STEMACLE_REPO_ROOT"],
           !envRoot.isEmpty {
            return URL(fileURLWithPath: envRoot, isDirectory: true)
        }

        if let resourceRoot = Bundle.main.resourceURL?.appendingPathComponent("repo", isDirectory: true),
           FileManager.default.fileExists(atPath: resourceRoot.path) {
            return resourceRoot
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
