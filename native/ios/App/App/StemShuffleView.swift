import SwiftUI

private struct ShuffleTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let bpm: Int
    let key: String
    let duration: TimeInterval

    var durationLabel: String {
        let safe = max(0, duration)
        let minutes = Int(safe) / 60
        let seconds = Int(safe) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

private struct ShufflePair: Identifiable, Equatable {
    let left: ShuffleTrack
    let right: ShuffleTrack
    let score: Double
    let tempoDelta: Int
    let keyDelta: Int
    let durationRatio: Double

    var id: String { "\(left.id)-\(right.id)" }
}

private enum MixDeck: String, CaseIterable, Identifiable {
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
        case .track1: return StemacleDesign.purple
        case .track2: return StemacleDesign.amber
        }
    }

    var opposite: MixDeck {
        self == .track1 ? .track2 : .track1
    }
}

private enum MixLeadMode: String, CaseIterable, Identifiable {
    case track1
    case blend
    case track2

    var id: String { rawValue }

    var label: String {
        switch self {
        case .track1: return "Lead 1"
        case .blend: return "Blend"
        case .track2: return "Lead 2"
        }
    }

    var symbolName: String {
        switch self {
        case .track1: return "1.square.fill"
        case .blend: return "circle.lefthalf.filled"
        case .track2: return "2.square.fill"
        }
    }
}

struct StemShuffleView: View {
    @State private var track1 = ShuffleTrack(id: "sample-1", title: "Stem Sample 1", bpm: 122, key: "Am", duration: 216)
    @State private var track2 = ShuffleTrack(id: "sample-2", title: "Stem Sample 2", bpm: 124, key: "C", duration: 228)
    @State private var stemSources: [Stem: MixDeck] = [
        .vocals: .track1,
        .bass: .track1,
        .drums: .track2,
        .melody: .track2
    ]
    @State private var leadMode: MixLeadMode = .blend
    @State private var isPlaying = false
    @State private var syncedBPM = 123
    @State private var trackSettingsDeck: MixDeck?
    @State private var pairCycleIndex = -1
    @State private var nextMixHint = "Tap shuffle to cycle the most compatible pair"

    private let mixStemOrder: [Stem] = [.vocals, .bass, .drums, .melody]

    private let pool = [
        ShuffleTrack(id: "sample-1", title: "Stem Sample 1", bpm: 122, key: "Am", duration: 216),
        ShuffleTrack(id: "sample-2", title: "Stem Sample 2", bpm: 124, key: "C", duration: 228),
        ShuffleTrack(id: "sample-3", title: "Stem Sample 3", bpm: 118, key: "Dm", duration: 208),
    ]

    private var activePair: ShufflePair? {
        rankCompatiblePairs(from: pool).first { pair in
            (pair.left.id == track1.id && pair.right.id == track2.id) ||
            (pair.left.id == track2.id && pair.right.id == track1.id)
        }
    }

    var body: some View {
        StemacleScreen(showsTentacleFooter: true) {
            ScrollView {
                VStack(spacing: 12) {
                    MixStatusBar(
                        syncedBPM: syncedBPM,
                        isPlaying: isPlaying,
                        leadMode: leadMode,
                        summary: nextMixHint,
                        compatibilityMeta: compatibilityMeta,
                        togglePlayback: { isPlaying.toggle() },
                        shufflePair: shufflePair,
                        setLeadMode: setLeadMode
                    )

                    MixPadGrid(
                        track1: track1,
                        track2: track2,
                        stemSources: stemSources,
                        mixStemOrder: mixStemOrder,
                        onTrackSettings: { trackSettingsDeck = $0 },
                        onToggleStem: toggleStemSource
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(item: $trackSettingsDeck) { deck in
            if #available(iOS 16.0, *) {
                TrackSettingsSheet(
                    deck: deck,
                    track: track(for: deck),
                    compatibilityMeta: compatibilityMeta,
                    leadMode: leadMode,
                    onShuffleTrack: { shuffleTrack(for: deck) }
                )
                .presentationDetents([.medium])
            } else {
                TrackSettingsSheet(
                    deck: deck,
                    track: track(for: deck),
                    compatibilityMeta: compatibilityMeta,
                    leadMode: leadMode,
                    onShuffleTrack: { shuffleTrack(for: deck) }
                )
            }
        }
    }

    private var compatibilityMeta: String {
        guard let pair = activePair else {
            return "Analyze at least two tracks before the deck stage can rank compatibility."
        }
        return "score \(pair.score.toOneDecimal) · \(pair.tempoDelta) BPM delta · \(pair.keyDelta) semitone delta · \(pair.durationRatio.toPercent)"
    }

    private func track(for deck: MixDeck) -> ShuffleTrack {
        deck == .track1 ? track1 : track2
    }

    private func otherTrack(for deck: MixDeck) -> ShuffleTrack {
        deck == .track1 ? track2 : track1
    }

    private func shuffleTrack(for deck: MixDeck) {
        guard pool.count >= 2 else { return }
        let other = otherTrack(for: deck)
        let current = track(for: deck)
        let candidates = pool.filter { pool.count <= 2 || $0.id != current.id }

        let ranked = candidates
            .map { candidate in
                RankedTrack(track: candidate, score: scoreCompatibility(left: candidate, right: other))
            }
            .filter { $0.track.id != other.id }
            .sorted { left, right in
                if left.score != right.score { return left.score > right.score }
                if left.track.bpm != right.track.bpm { return left.track.bpm < right.track.bpm }
                return left.track.title.localizedCaseInsensitiveCompare(right.track.title) == .orderedAscending
            }

        guard let next = ranked.first?.track else { return }
        if deck == .track1 {
            track1 = next
        } else {
            track2 = next
        }
        refreshMixState()
        nextMixHint = "Queued \(track1.title) × \(track2.title) from the strongest local match."
    }

    private func toggleStemSource(_ stem: Stem) {
        guard let current = stemSources[stem] else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
            stemSources[stem] = current.opposite
        }
        nextMixHint = "Manual split updated for \(stem.title)."
        StemacleHaptics.tap()
    }

    private func shufflePair() {
        guard pool.count >= 2 else { return }
        let ranked = rankCompatiblePairs(from: pool)
        guard !ranked.isEmpty else { return }
        pairCycleIndex = (pairCycleIndex + 1) % ranked.count
        let pair = ranked[pairCycleIndex]
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            track1 = pair.left
            track2 = pair.right
            leadMode = .blend
            applyStemSources(for: leadMode)
        }
        refreshMixState()
        nextMixHint = "Loaded \(pair.left.title) × \(pair.right.title) · pair \(pairCycleIndex + 1) of \(ranked.count)"
        StemacleHaptics.loopEngaged()
    }

    private func setLeadMode(_ mode: MixLeadMode) {
        leadMode = mode
        applyStemSources(for: mode)
        refreshMixState()
        nextMixHint = "\(mode.label) selected for \(track1.title) × \(track2.title)."
    }

    private func applyStemSources(for mode: MixLeadMode) {
        switch mode {
        case .track1:
            stemSources = [
                .vocals: .track1,
                .bass: .track1,
                .drums: .track2,
                .melody: .track2
            ]
        case .blend:
            stemSources = [
                .vocals: .track1,
                .bass: .track2,
                .drums: .track1,
                .melody: .track2
            ]
        case .track2:
            stemSources = [
                .vocals: .track2,
                .bass: .track2,
                .drums: .track1,
                .melody: .track1
            ]
        }
    }

    private func refreshMixState() {
        switch leadMode {
        case .track1:
            syncedBPM = track1.bpm
        case .blend:
            syncedBPM = Int(round(Double(track1.bpm + track2.bpm) / 2))
        case .track2:
            syncedBPM = track2.bpm
        }
    }
}

private struct MixStatusBar: View {
    let syncedBPM: Int
    let isPlaying: Bool
    let leadMode: MixLeadMode
    let summary: String
    let compatibilityMeta: String
    let togglePlayback: () -> Void
    let shufflePair: () -> Void
    let setLeadMode: (MixLeadMode) -> Void

    @Namespace private var leadModeNS

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "link")
                        .font(.caption2.weight(.bold))
                    Text("\(syncedBPM)")
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                    Text("bpm")
                        .font(.caption2)
                        .foregroundStyle(StemacleDesign.purple.opacity(0.7))
                }
                .foregroundStyle(StemacleDesign.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(StemacleDesign.purple.opacity(0.1))
                        .overlay(Capsule(style: .continuous).stroke(StemacleDesign.purple.opacity(0.22), lineWidth: 1))
                )

                Spacer(minLength: 0)

                Button(action: shufflePair) {
                    Image(systemName: "shuffle")
                        .font(.callout.weight(.semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(StemacleDesign.inkSoft)
                .background(Circle().fill(StemacleDesign.paper.opacity(0.8)))
                .overlay(Circle().stroke(StemacleDesign.track.opacity(0.5), lineWidth: 1))

                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(StemacleDesign.paper)
                .background(Circle().fill(StemacleDesign.ink))
                .shadow(color: StemacleDesign.shadow, radius: 8, y: 3)
            }

            HStack(spacing: 3) {
                ForEach(MixLeadMode.allCases) { mode in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            setLeadMode(mode)
                        }
                    } label: {
                        Label(mode.label, systemImage: mode.symbolName)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(leadMode == mode ? StemacleDesign.paper : StemacleDesign.inkSoft)
                    }
                    .buttonStyle(.plain)
                    .background {
                        if leadMode == mode {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(StemacleDesign.ink)
                                .matchedGeometryEffect(id: "leadMode", in: leadModeNS)
                        }
                    }
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(StemacleDesign.paper.opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(StemacleDesign.track.opacity(0.4), lineWidth: 1)
                    )
            )

            if !summary.isEmpty {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(StemacleDesign.inkGhost)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MixPadGrid: View {
    let track1: ShuffleTrack
    let track2: ShuffleTrack
    let stemSources: [Stem: MixDeck]
    let mixStemOrder: [Stem]
    let onTrackSettings: (MixDeck) -> Void
    let onToggleStem: (Stem) -> Void

    private let columns = [
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            MixTrackPadButton(deck: .track1, track: track1, action: { onTrackSettings(.track1) })
            MixTrackPadButton(deck: .track2, track: track2, action: { onTrackSettings(.track2) })
            ForEach(mixStemOrder) { stem in
                MixStemPadButton(
                    stem: stem,
                    source: stemSources[stem] ?? .track1,
                    action: { onToggleStem(stem) }
                )
            }
        }
    }
}

private struct MixTrackPadButton: View {
    let deck: MixDeck
    let track: ShuffleTrack
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    Text(deck.label)
                        .font(.caption2.weight(.black))
                        .textCase(.uppercase)
                        .foregroundStyle(deck.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule(style: .continuous).fill(deck.tint.opacity(0.14)))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(StemacleDesign.inkGhost)
                }
                Text(track.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(StemacleDesign.ink)
                HStack(spacing: 4) {
                    Text("\(track.bpm) bpm")
                    Text("·").foregroundStyle(StemacleDesign.inkGhost)
                    Text(track.key)
                    Text("·").foregroundStyle(StemacleDesign.inkGhost)
                    Text(track.durationLabel)
                }
                .font(.caption2)
                .foregroundStyle(StemacleDesign.mutedInk)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(12)
            .background(trackPadBackground(deck: deck))
        }
        .buttonStyle(.plain)
    }
}

private struct MixStemPadButton: View {
    let stem: Stem
    let source: MixDeck
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Label(stem.title, systemImage: stem.symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(StemacleDesign.stemColor(stem))

                Text(source.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(source.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(source.tint.opacity(0.14))
                    )
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(12)
            .background(stemPadBackground(stem: stem))
        }
        .buttonStyle(.plain)
    }
}

private func stemPadBackground(stem: Stem) -> some View {
    let accent = StemacleDesign.stemColor(stem)
    return RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(accent.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.3), lineWidth: 1.5)
        )
}

private func trackPadBackground(deck: MixDeck) -> some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(StemacleDesign.paper.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(deck.tint.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: StemacleDesign.shadow, radius: 4, y: 1)
}

private struct TrackSettingsSheet: View {
    let deck: MixDeck
    let track: ShuffleTrack
    let compatibilityMeta: String
    let leadMode: MixLeadMode
    let onShuffleTrack: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(StemacleDesign.track.opacity(0.6))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 22)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(deck.label)
                        .font(.caption2.weight(.black))
                        .textCase(.uppercase)
                        .foregroundStyle(deck.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule(style: .continuous).fill(deck.tint.opacity(0.14)))
                    Text(track.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(StemacleDesign.ink)
                        .lineLimit(2)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(StemacleDesign.purple)
            }
            .padding(.horizontal, 24)

            StemacleHairline()
                .padding(.top, 20)

            VStack(spacing: 0) {
                settingsRow("Tempo", value: "\(track.bpm) bpm")
                StemacleHairline()
                settingsRow("Key", value: track.key)
                StemacleHairline()
                settingsRow("Duration", value: track.durationLabel)
                StemacleHairline()
                settingsRow("Lead", value: leadMode.label)
            }
            .padding(.top, 6)

            if !compatibilityMeta.isEmpty {
                Text(compatibilityMeta)
                    .font(.caption2)
                    .foregroundStyle(StemacleDesign.inkGhost)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }

            Spacer(minLength: 24)

            Button {
                onShuffleTrack()
                dismiss()
                StemacleHaptics.loopEngaged()
            } label: {
                Label("Bring in a stronger local match", systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(StemacleDesign.paper)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(StemacleDesign.ink)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(StemacleDesign.paper.ignoresSafeArea())
    }

    private func settingsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(StemacleDesign.inkSoft)
            Spacer()
            Text(value)
                .foregroundStyle(StemacleDesign.mutedInk)
        }
        .font(.callout)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

private struct RankedTrack {
    let track: ShuffleTrack
    let score: Double
}

private func rankCompatiblePairs(from tracks: [ShuffleTrack]) -> [ShufflePair] {
    let readyTracks = tracks
    var pairs: [ShufflePair] = []

    for index in 0..<readyTracks.count {
        for nested in (index + 1)..<readyTracks.count {
            let left = readyTracks[index]
            let right = readyTracks[nested]
            let score = scoreCompatibility(left: left, right: right)
            if score <= 0 { continue }
            let ordered = orderedPair(left, right)
            pairs.append(
                ShufflePair(
                    left: ordered.left,
                    right: ordered.right,
                    score: score,
                    tempoDelta: abs(left.bpm - right.bpm),
                    keyDelta: keyDistance(left.keyClass, right.keyClass),
                    durationRatio: min(left.duration, right.duration) / max(max(left.duration, right.duration), 1)
                )
            )
        }
    }

    pairs.sort {
        if $0.score != $1.score { return $0.score > $1.score }
        if $0.tempoDelta != $1.tempoDelta { return $0.tempoDelta < $1.tempoDelta }
        return $0.keyDelta < $1.keyDelta
    }
    return pairs
}

private func scoreCompatibility(left: ShuffleTrack, right: ShuffleTrack) -> Double {
    let tempoDelta = abs(left.bpm - right.bpm)
    let keyDelta = keyDistance(left.keyClass, right.keyClass)
    let durationMin = min(left.duration, right.duration)
    let durationMax = max(max(left.duration, right.duration), 1)
    let durationRatio = durationMin / durationMax

    let tempoScore = clamp(1 - (Double(tempoDelta) / 24), min: 0, max: 1)
    let keyScore = clamp(1 - (Double(keyDelta) / 6), min: 0, max: 1)
    let durationScore = clamp(durationRatio, min: 0, max: 1)
    return (tempoScore * 60) + (keyScore * 30) + (durationScore * 10)
}

private func orderedPair(_ left: ShuffleTrack, _ right: ShuffleTrack) -> (left: ShuffleTrack, right: ShuffleTrack) {
    if left.bpm != right.bpm {
        return left.bpm < right.bpm ? (left, right) : (right, left)
    }

    let leftKey = left.keyClass ?? 99
    let rightKey = right.keyClass ?? 99
    if leftKey != rightKey {
        return leftKey < rightKey ? (left, right) : (right, left)
    }

    return left.title.localizedCaseInsensitiveCompare(right.title) != .orderedDescending ? (left, right) : (right, left)
}

private func keyDistance(_ left: Int?, _ right: Int?) -> Int {
    guard let left, let right else { return 6 }
    let delta = abs(left - right) % 12
    return min(delta, 12 - delta)
}

private func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
    Swift.max(lower, Swift.min(upper, value))
}

private func parseKeyClass(_ value: String) -> Int? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let lowered = trimmed.lowercased()
    let root: String
    if lowered.count >= 2 {
        let prefix = String(lowered.prefix(2))
        if ["ab", "bb", "db", "eb", "gb"].contains(prefix) {
            root = prefix
        } else if ["c#", "d#", "f#", "g#", "a#"].contains(prefix) {
            root = prefix
        } else {
            root = String(lowered.prefix(1))
        }
    } else {
        root = String(lowered.prefix(1))
    }

    switch root {
    case "c": return 0
    case "c#", "db": return 1
    case "d": return 2
    case "d#", "eb": return 3
    case "e": return 4
    case "f": return 5
    case "f#", "gb": return 6
    case "g": return 7
    case "g#", "ab": return 8
    case "a": return 9
    case "a#", "bb": return 10
    case "b", "cb": return 11
    default: return nil
    }
}

private extension ShuffleTrack {
    var keyClass: Int? {
        parseKeyClass(key)
    }
}

private extension Double {
    var toOneDecimal: String {
        String(format: "%.1f", self)
    }

    var toPercent: String {
        String(format: "%.0f%%", self * 100)
    }
}
