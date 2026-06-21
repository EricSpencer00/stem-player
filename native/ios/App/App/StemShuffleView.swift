import SwiftUI

private let utilityContentWidth: CGFloat = 520

private struct ShuffleTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let bpm: Int
    let key: String
}

struct StemShuffleView: View {
    @State private var left = ShuffleTrack(id: "sample-1", title: "Stem Sample 1", bpm: 122, key: "Am")
    @State private var right = ShuffleTrack(id: "sample-2", title: "Stem Sample 2", bpm: 124, key: "C")
    @State private var crossfade = 0.5
    @State private var blend = 0.42
    @State private var lead = "A"

    private let tracks = [
        ShuffleTrack(id: "sample-1", title: "Stem Sample 1", bpm: 122, key: "Am"),
        ShuffleTrack(id: "sample-2", title: "Stem Sample 2", bpm: 124, key: "C"),
        ShuffleTrack(id: "sample-3", title: "Stem Sample 3", bpm: 118, key: "Dm"),
    ]

    var body: some View {
        StemacleScreen {
            ScrollView {
                VStack(spacing: 12) {
                    DeckCard(side: "A", track: left, level: 1 - crossfade, lead: lead == "A")
                    DeckCard(side: "B", track: right, level: crossfade, lead: lead == "B")

                    StemaclePanel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Blend")
                                    .font(.caption.weight(.bold))
                                    .textCase(.uppercase)
                                Spacer()
                                Button {
                                    shufflePair()
                                } label: {
                                    Label("Shuffle Pair", systemImage: "shuffle")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(StemacleDesign.purple)
                            }

                            Picker("Lead", selection: $lead) {
                                Text("A").tag("A")
                                Text("B").tag("B")
                            }
                            .pickerStyle(.segmented)

                            Slider(value: $crossfade, in: 0...1) {
                                Text("Crossfade")
                            }
                            .tint(StemacleDesign.purple)

                            Slider(value: $blend, in: 0...1) {
                                Text("Stem blend")
                            }
                            .tint(StemacleDesign.amber)

                            Text("Shuffle keeps pair picking, rate feel, crossfade, and lead A/B separate from the main splitter so each surface stays focused.")
                                .font(.caption2)
                                .foregroundStyle(StemacleDesign.mutedInk)
                        }
                    }

                    VStack(spacing: 10) {
                        ForEach(Stem.allCases) { stem in
                            HStack {
                                Label(stem.title, systemImage: stem.symbolName)
                                Spacer()
                                ProgressView(value: blend)
                                    .tint(StemacleDesign.inkSoft)
                                    .frame(width: 120)
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.bottom, 110)
                }
                .frame(maxWidth: utilityContentWidth)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Shuffle")
    }

    func shufflePair() {
        guard tracks.count >= 2 else { return }
        var candidates = tracks.shuffled()
        left = candidates.removeFirst()
        right = candidates.first(where: { $0.id != left.id }) ?? tracks[1]
        crossfade = 0.5
        blend = 0.42
        lead = Bool.random() ? "A" : "B"
    }
}

private struct DeckCard: View {
    let side: String
    let track: ShuffleTrack
    let level: Double
    let lead: Bool

    var body: some View {
        StemaclePanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(side)
                        .font(.headline.weight(.black))
                    Spacer()
                    if lead {
                        Label("Lead", systemImage: "arrowtriangle.right.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(StemacleDesign.amber)
                    }
                }
                Text(track.title)
                    .font(.subheadline.weight(.semibold))
                HStack {
                    Label("\(track.bpm) bpm", systemImage: "metronome")
                    Label(track.key, systemImage: "key")
                }
                .font(.caption)
                .foregroundStyle(StemacleDesign.mutedInk)
                ProgressView(value: level)
                    .tint(side == "A" ? StemacleDesign.purple : StemacleDesign.amber)
            }
        }
    }
}
