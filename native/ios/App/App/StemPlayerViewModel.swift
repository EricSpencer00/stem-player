import AVFoundation
import SwiftUI

private let SPECTRAL_MIN_WINDOW_SEC: TimeInterval = 16
private let SPECTRAL_CURSOR_RATIO = 0.72
private let SPECTRAL_PAD_BEFORE_SEC: TimeInterval = 2
private let SPECTRAL_PAD_AFTER_SEC: TimeInterval = 4
private let BEATS_PER_MEASURE = 4.0

enum SpectralWindowMode: String {
    case follow
    case expanded
}

struct SpectralWindow: Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var mode: SpectralWindowMode
}

struct SpectralGridMarker: Identifiable, Equatable {
    var id: TimeInterval { time }
    var time: TimeInterval
    var label: String
    var weight: Double
}

@MainActor
final class StemPlayerViewModel: ObservableObject {
    @Published var title = "Drop a track"
    @Published var status = "Choose a sample or import audio"
    @Published var progress = 0.0
    @Published var isProcessing = false
    @Published var isReady = false
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 1
    @Published var tempo = TempoEstimate(bpm: 120, confidence: 0, beatOffset: 0, measureOffset: 0)
    @Published var controls: [Stem: StemPlaybackControl] = Dictionary(uniqueKeysWithValues: Stem.allCases.map { ($0, StemPlaybackControl()) })
    @Published var loops: [Stem: StemLoop] = Dictionary(uniqueKeysWithValues: Stem.allCases.map { ($0, StemLoop.inactive) })
    @Published var globalMuted = false
    @Published var headphonesStem: Stem?
    @Published var loopMonitorMode: LoopMonitorMode = .mix
    @Published var overview: [Stem: [Float]] = [:]
    @Published var spectralWindow = SpectralWindow(start: 0, end: SPECTRAL_MIN_WINDOW_SEC, mode: .follow)
    @Published var recentProjects: [String] = []

    let loopDurations: [(label: String, measures: Double)] = [
        ("1/4", 0.25),
        ("1/2", 0.5),
        ("1", 1.0),
        ("2", 2.0),
    ]

    let samples: [SampleTrack] = [
        SampleTrack(id: "sample-1", title: "Gentleman - cdk feat. QuianaNadine", detail: "bundled", fileName: "stem-sample-1"),
        SampleTrack(id: "sample-2", title: "Red Light Blues - Alex & UnrealDM", detail: "bundled", fileName: "stem-sample-2"),
        SampleTrack(id: "sample-3", title: "Pyramid - 7OOP3D feat. Mr Yesterday", detail: "bundled", fileName: "stem-sample-3"),
    ]

    private let splitter = NativeStemSplitter()
    private let audioEngine = StemAudioEngine()
    private var timer: Timer?

    func loadSample(_ sample: SampleTrack) {
        guard let url = Bundle.main.url(forResource: sample.fileName, withExtension: "mp3", subdirectory: "public/samples") else {
            status = "Sample is missing from the iOS bundle"
            return
        }
        load(audioAt: url)
    }

    func load(audioAt url: URL) {
        stop()
        resetTrackStateForNewFile()
        isProcessing = true
        isReady = false
        progress = 0
        title = url.deletingPathExtension().lastPathComponent
        status = "Preparing native split"

        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let result = try await splitter.split(audioAt: url) { percent, message in
                    Task { @MainActor in
                        self.progress = percent
                        self.status = message
                    }
                }
                try audioEngine.load(result)
                title = result.title
                duration = max(0.1, result.duration)
                tempo = result.tempo
                overview = result.overview
                currentTime = 0
                spectralWindow = spectralWindowFor(0)
                isProcessing = false
                isReady = true
                progress = 1
                status = "Ready at \(Int(result.tempo.bpm.rounded())) bpm"
                rememberProject(result.title)
            } catch {
                isProcessing = false
                isReady = false
                status = error.localizedDescription
            }
        }
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard isReady else {
            if let first = samples.first {
                loadSample(first)
            }
            return
        }

        do {
            try audioEngine.play(
                from: currentTime,
                controls: controls,
                loops: loops,
                globalMute: globalMuted,
                headphonesStem: effectiveHeadphonesStem(),
                loopMonitorMode: loopMonitorMode
            )
            isPlaying = true
            startTimer()
            status = "Playing"
        } catch {
            status = error.localizedDescription
        }
    }

    func pause() {
        currentTime = audioEngine.pause()
        isPlaying = false
        stopTimer()
        status = "Paused"
    }

    func stop() {
        audioEngine.stop()
        currentTime = 0
        updateSpectralWindow(0)
        isPlaying = false
        stopTimer()
    }

    func restart() {
        currentTime = 0
        updateSpectralWindow(0)
        replayIfNeeded()
    }

    func seek(to value: TimeInterval) {
        currentTime = min(max(0, value), duration)
        updateSpectralWindow(currentTime)
        do {
            try audioEngine.seek(
                to: currentTime,
                controls: controls,
                loops: loops,
                globalMute: globalMuted,
                headphonesStem: effectiveHeadphonesStem(),
                loopMonitorMode: loopMonitorMode
            )
        } catch {
            status = error.localizedDescription
        }
    }

    func setVolume(stem: Stem, value: Float) {
        controls[stem]?.volume = min(1, max(0, value))
        updateMix()
    }

    func toggleMute(stem: Stem) {
        controls[stem]?.isMuted.toggle()
        updateMix()
    }

    func toggleGlobalMute() {
        globalMuted.toggle()
        updateMix()
    }

    func setHeadphones(stem: Stem?) {
        let next = headphonesStem == stem ? nil : stem
        headphonesStem = next
        for candidate in Stem.allCases {
            controls[candidate]?.isHeadphones = candidate == next
        }
        updateMix()
    }

    func setLoopMonitorMode(_ mode: LoopMonitorMode) {
        loopMonitorMode = mode
        if mode == .mix {
            setHeadphones(stem: nil)
        }
        replayIfNeeded()
    }

    func applyLoop(stem: Stem, index: Int) {
        if loops[stem]?.selectedIndex == index {
            loops[stem] = .inactive
            updateSpectralWindow(currentTime)
            replayIfNeeded()
            return
        }

        guard let range = loopRange(forIndex: index) else {
            loops[stem] = .inactive
            status = "Loop would run past the end"
            updateSpectralWindow(currentTime)
            replayIfNeeded()
            return
        }

        loops[stem] = StemLoop(selectedIndex: index, start: range.start, end: range.end)
        updateSpectralWindow(currentTime)
        if loopMonitorMode == .solo {
            setHeadphones(stem: stem)
        } else {
            replayIfNeeded()
        }
    }

    func applyLoopToAll(index: Int) {
        if Stem.allCases.allSatisfy({ loops[$0]?.selectedIndex == index }) {
            for stem in Stem.allCases {
                loops[stem] = .inactive
            }
            updateSpectralWindow(currentTime)
            replayIfNeeded()
            return
        }

        guard let range = loopRange(forIndex: index) else {
            for stem in Stem.allCases {
                loops[stem] = .inactive
            }
            status = "Linked loop would run past the end"
            updateSpectralWindow(currentTime)
            replayIfNeeded()
            return
        }

        for stem in Stem.allCases {
            loops[stem] = StemLoop(selectedIndex: index, start: range.start, end: range.end)
        }
        updateSpectralWindow(currentTime)
        replayIfNeeded()
    }

    func resetMixer() {
        controls = Dictionary(uniqueKeysWithValues: Stem.allCases.map { ($0, StemPlaybackControl()) })
        globalMuted = false
        headphonesStem = nil
        updateMix()
    }

    func clearLoops() {
        loops = Dictionary(uniqueKeysWithValues: Stem.allCases.map { ($0, StemLoop.inactive) })
        updateSpectralWindow(currentTime)
        replayIfNeeded()
    }

    private func resetTrackStateForNewFile() {
        loops = Dictionary(uniqueKeysWithValues: Stem.allCases.map { ($0, StemLoop.inactive) })
        headphonesStem = nil
        loopMonitorMode = .mix
        for stem in Stem.allCases {
            controls[stem]?.isHeadphones = false
        }
        currentTime = 0
        spectralWindow = SpectralWindow(start: 0, end: SPECTRAL_MIN_WINDOW_SEC, mode: .follow)
    }

    func formatted(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let whole = max(0, Int(time.rounded(.down)))
        return "\(whole / 60):\(String(format: "%02d", whole % 60))"
    }

    func loopLabel(for stem: Stem) -> String {
        guard let index = loops[stem]?.selectedIndex, loopDurations.indices.contains(index) else {
            return "open"
        }
        return loopDurations[index].label
    }

    func spectralTimeFromRatio(_ ratio: Double) -> TimeInterval {
        let clamped = min(1, max(0, ratio))
        return spectralWindow.start + (spectralWindow.end - spectralWindow.start) * clamped
    }

    func cursorRatio(for stem: Stem) -> Double {
        let span = spectralWindow.end - spectralWindow.start
        guard span > 0 else { return 0 }
        return min(1, max(0, (audibleStemTime(stem: stem, transportSec: currentTime) - spectralWindow.start) / span))
    }

    func audibleStemTime(stem: Stem, transportSec: TimeInterval) -> TimeInterval {
        var audible = playbackOffset(transportSec)
        guard let loop = loops[stem], loop.isActive else {
            return audible
        }
        let loopLength = loop.end - loop.start
        if loopLength > 0, audible >= loop.end {
            audible = loop.start + ((audible - loop.start).truncatingRemainder(dividingBy: loopLength))
        }
        return playbackOffset(audible)
    }

    func spectralWindowFor(_ transportSec: TimeInterval) -> SpectralWindow {
        let safeDuration = max(0.001, duration)
        let main = min(max(0, transportSec.isFinite ? transportSec : 0), safeDuration)
        var points = [main]
        var hasActiveLoop = false

        for stem in Stem.allCases {
            points.append(audibleStemTime(stem: stem, transportSec: main))
            if let loop = loops[stem], loop.isActive {
                hasActiveLoop = true
                points.append(loop.start)
                points.append(loop.end)
            }
        }

        let minWindow = min(safeDuration, SPECTRAL_MIN_WINDOW_SEC)
        var start: TimeInterval
        var end: TimeInterval
        var mode = SpectralWindowMode.follow

        if hasActiveLoop {
            start = max(0, (points.min() ?? 0) - SPECTRAL_PAD_BEFORE_SEC)
            end = min(safeDuration, (points.max() ?? main) + SPECTRAL_PAD_AFTER_SEC)
            mode = .expanded
            if end - start < minWindow {
                let needed = minWindow - (end - start)
                start = max(0, start - needed * SPECTRAL_CURSOR_RATIO)
                end = min(safeDuration, start + minWindow)
                start = max(0, end - minWindow)
            }
        } else {
            start = main - minWindow * SPECTRAL_CURSOR_RATIO
            start = max(0, min(start, max(0, safeDuration - minWindow)))
            end = min(safeDuration, start + minWindow)
        }

        return SpectralWindow(start: start, end: max(start + 0.001, end), mode: mode)
    }

    func spectralGridMarkers() -> [SpectralGridMarker] {
        let measure = measureLength()
        guard measure.isFinite, measure > 0 else { return [] }
        let quarter = measure / BEATS_PER_MEASURE
        guard quarter > 0 else { return [] }
        let offset = min(max(0, tempo.measureOffset), max(0, measure - 0.000_001))
        let first = Int(floor((spectralWindow.start - offset) / quarter))
        var markers: [SpectralGridMarker] = []
        var index = first
        while true {
            let time = offset + Double(index) * quarter
            if time > spectralWindow.end + 0.000_001 { break }
            if time >= spectralWindow.start - 0.000_001 {
                let phase = ((index % Int(BEATS_PER_MEASURE)) + Int(BEATS_PER_MEASURE)) % Int(BEATS_PER_MEASURE)
                if phase == 0 {
                    markers.append(SpectralGridMarker(time: time, label: "1", weight: 0.42))
                } else if phase == 2 {
                    markers.append(SpectralGridMarker(time: time, label: "1/2", weight: 0.28))
                } else {
                    markers.append(SpectralGridMarker(time: time, label: "1/4", weight: 0.18))
                }
            }
            index += 1
        }
        return markers
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = self.audioEngine.currentOffset()
                self.updateSpectralWindow(self.currentTime)
                if self.currentTime >= self.duration - 0.02 {
                    self.isPlaying = false
                    self.stopTimer()
                    self.status = "Ended"
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateMix() {
        audioEngine.updateMix(
            controls: controls,
            globalMute: globalMuted,
            headphonesStem: effectiveHeadphonesStem()
        )
    }

    private func replayIfNeeded() {
        if isPlaying {
            play()
        } else {
            updateMix()
        }
    }

    private func effectiveHeadphonesStem() -> Stem? {
        if let headphonesStem {
            return headphonesStem
        }
        guard loopMonitorMode == .solo else {
            return nil
        }
        return Stem.allCases.first { loops[$0]?.isActive == true }
    }

    private func loopRange(forIndex index: Int) -> (start: TimeInterval, end: TimeInterval)? {
        guard loopDurations.indices.contains(index) else { return nil }
        let measure = measureLength()
        let length = loopDurations[index].measures * measure
        guard length > 0, duration > 0 else { return nil }
        let end = snapLoopEnd(currentTime, length: length, measure: measure)
        let start = max(0, end - length)
        guard end <= duration else { return nil }
        return (start, end)
    }

    private func measureLength() -> TimeInterval {
        max(0.25, (60 / max(tempo.bpm, 1)) * BEATS_PER_MEASURE)
    }

    private func snapLoopEnd(_ time: TimeInterval, length: TimeInterval, measure: TimeInterval) -> TimeInterval {
        guard measure > 0, length > 0 else { return 0 }
        let grid = min(measure, length)
        let offset = min(max(0, tempo.measureOffset), max(0, measure - 0.000_001))
        let boundary = offset + floor((time - offset) / grid) * grid
        let nextBoundary = boundary + grid
        let epsilon = min(0.03, grid * 0.25)
        if boundary >= 0, abs(time - boundary) <= epsilon {
            return boundary
        }
        return max(0, nextBoundary)
    }

    private func playbackOffset(_ value: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return max(0, value) }
        return min(max(0, value), duration)
    }

    private func updateSpectralWindow(_ time: TimeInterval? = nil) {
        spectralWindow = spectralWindowFor(time ?? currentTime)
    }

    private func rememberProject(_ name: String) {
        recentProjects.removeAll { $0 == name }
        recentProjects.insert(name, at: 0)
        recentProjects = Array(recentProjects.prefix(6))
    }
}
