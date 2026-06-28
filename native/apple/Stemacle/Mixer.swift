import AVFoundation
import Combine
import Foundation
import StemacleKit
import SwiftUI

/// Plays a four-stem mix where each stem can come from one of two source
/// projects (the Stem Shuffle / Mixer). Tempo/key matching is a planned
/// foundation; today this layers and routes cached stems, synced from the start.
@MainActor
final class MixerViewModel: ObservableObject {
    let stems = StemRouting.stems

    @Published var sourceA: Project?
    @Published var sourceB: Project?
    /// Pure routing model (unit-tested in StemacleKit). `objectWillChange` is
    /// fired manually on mutation since it is a value type, not a Published ref.
    private var routing = StemRouting()
    @Published var isPlaying = false
    @Published var hint = "Pick two songs, then route each stem."

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var players: [String: AVAudioPlayerNode] = [:]
    private weak var library: LibraryStore?

    init() {}

    func attach(_ library: LibraryStore) { self.library = library }

    var canPlay: Bool { routing.canPlay(hasA: sourceA != nil, hasB: sourceB != nil) }

    /// Whether `stem` currently routes to source B (drives the segmented picker).
    func routesToB(_ stem: String) -> Bool { routing.routesToB(stem) }

    private func ensureNodes() {
        guard players.isEmpty else { return }
        for s in stems {
            let node = AVAudioPlayerNode()
            players[s] = node
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
    }

    func toggleRoute(_ stem: String) {
        objectWillChange.send()
        routing.toggle(stem)
        if isPlaying { restart() }
    }

    func source(for stem: String) -> Project? {
        routing.source(for: stem, a: sourceA, b: sourceB)
    }

    func togglePlay() { isPlaying ? stop() : restart() }

    private func restart() {
        guard canPlay, let library else { return }
        ensureNodes()
        // Cache each source's stems once.
        var cache: [UUID: [String: [Float]]] = [:]
        func cachedStems(for project: Project) -> [String: [Float]]? {
            if let c = cache[project.id] { return c }
            let s = library.stems(for: project)
            if let s { cache[project.id] = s }
            return s
        }
        do { try engine.start() } catch { hint = "Audio error"; return }
        for stem in stems {
            guard let node = players[stem],
                  let project = source(for: stem),
                  let samples = cachedStems(for: project)?[stem], !samples.isEmpty else { continue }
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
            buf.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
            }
            node.stop()
            node.scheduleBuffer(buf, at: nil)
            node.play()
        }
        isPlaying = true
    }

    func stop() {
        for node in players.values { node.stop() }
        isPlaying = false
    }
}

struct MixerView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var mixer: MixerViewModel

    var body: some View {
        ZStack {
            Stem.cream.ignoresSafeArea()
            if library.projects.count < 2 {
                emptyState
            } else {
                content
            }
        }
        .foregroundStyle(Stem.ink)
        .onAppear { mixer.attach(library) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "shuffle").font(.system(size: 40, weight: .light)).foregroundStyle(Stem.inkSoft)
            Text("Stem Shuffle").font(.headline)
            Text("Split at least two songs, then mix and match their stems here.")
                .font(.footnote).foregroundStyle(Stem.inkSoft)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stem Shuffle").font(.system(size: 22, weight: .semibold, design: .rounded))
                .padding(.top, 10).padding(.horizontal, 18)

            HStack(spacing: 12) {
                sourcePicker("A", selection: $mixer.sourceA)
                sourcePicker("B", selection: $mixer.sourceB)
            }
            .padding(.horizontal, 18)

            VStack(spacing: 8) {
                ForEach(mixer.stems, id: \.self) { stem in
                    routeRow(stem)
                }
            }
            .padding(.horizontal, 18)

            Button { mixer.togglePlay() } label: {
                Label(mixer.isPlaying ? "Stop" : "Play mix", systemImage: mixer.isPlaying ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Stem.purple)
            .disabled(!mixer.canPlay)
            .padding(.horizontal, 18)
            .accessibilityIdentifier("mixer.play")

            Text("Stems from two songs, routed live. Tempo and key matching are on the way.")
                .font(.caption).foregroundStyle(Stem.inkSoft).padding(.horizontal, 18)
            Spacer()
        }
    }

    private func sourcePicker(_ label: String, selection: Binding<Project?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source \(label)").font(.caption.weight(.medium)).foregroundStyle(Stem.inkSoft)
            Menu {
                ForEach(library.projects) { p in
                    Button(p.title) { selection.wrappedValue = p }
                }
            } label: {
                HStack {
                    Text(selection.wrappedValue?.title ?? "Choose…").lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption)
                }
                .padding(10)
                .background(Stem.cream)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Stem.creamDeep, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityIdentifier("mixer.source.\(label)")
        }
        .frame(maxWidth: .infinity)
    }

    private func routeRow(_ stem: String) -> some View {
        let toB = mixer.routesToB(stem)
        return HStack {
            Text(stem.capitalized).font(.subheadline.weight(.medium)).frame(width: 80, alignment: .leading)
            Spacer()
            Picker("", selection: Binding(
                get: { toB }, set: { _ in mixer.toggleRoute(stem) }
            )) {
                Text("A").tag(false)
                Text("B").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .accessibilityIdentifier("mixer.route.\(stem)")
        }
        .padding(10)
        .background(Stem.cream)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Stem.creamDeep, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
