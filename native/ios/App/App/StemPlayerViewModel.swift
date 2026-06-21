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

struct LevelMeterBands: Equatable {
    var bass: Double
    var treble: Double
    var wave: Double
}

enum StemLibrarySort: String, CaseIterable, Identifiable, Codable {
    case recent
    case name
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return "Recent"
        case .name:
            return "Name"
        case .status:
            return "Status"
        }
    }
}

enum StemLibraryFilter: String, CaseIterable, Identifiable, Codable {
    case all
    case ready
    case queued
    case processing
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .ready:
            return "Ready"
        case .queued:
            return "Queued"
        case .processing:
            return "Processing"
        case .failed:
            return "Failed"
        }
    }
}

struct StemLibraryItem: Identifiable, Codable, Equatable {
    enum Status: String, CaseIterable, Identifiable, Codable {
        case queued
        case processing
        case ready
        case failed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .queued:
                return "Queued"
            case .processing:
                return "Processing"
            case .ready:
                return "Ready"
            case .failed:
                return "Failed"
            }
        }

        var symbolName: String {
            switch self {
            case .queued:
                return "clock"
            case .processing:
                return "arrow.triangle.2.circlepath"
            case .ready:
                return "checkmark.circle"
            case .failed:
                return "exclamationmark.triangle"
            }
        }
    }

    let id: String
    var title: String
    var sourceName: String
    var fileName: String
    var addedAt: Date
    var lastOpenedAt: Date?
    var status: Status
    var statusMessage: String
    var duration: TimeInterval?
    var lastUpdatedAt: Date
}

@MainActor
final class StemPlayerViewModel: ObservableObject {
    @Published var title = "Drop a track"
    @Published var status = "Import audio or open the local library"
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
    @Published var librarySort: StemLibrarySort = .recent
    @Published var libraryFilter: StemLibraryFilter = .all
    @Published private(set) var libraryItems: [StemLibraryItem] = []

    /// Mirrors the "Prefer solo loop monitoring" setting. Synced from the view so
    /// new track loads default to the monitor mode the user actually wants.
    var preferSoloLoopMonitor = false

    /// Set true after enough successful splits to ask for an App Store rating at a
    /// genuinely happy moment. The view observes this and drives the native prompt.
    @Published var shouldRequestReview = false

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
    private let stemCache = StemResultCache()
    private var timer: Timer?
    private var loadTask: Task<Void, Never>?
    private var activeLoadID = UUID()
    private let libraryDirectoryName = "Stemacle Library"
    private let successfulSplitCountKey = "stemacle.successfulSplitCount"
    private let reviewedVersionKey = "stemacle.reviewedVersion"

    private var successfulSplitCount: Int {
        get { UserDefaults.standard.integer(forKey: successfulSplitCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: successfulSplitCountKey) }
    }

    init() {
        loadLibraryItems()
        audioEngine.onInterruption = { [weak self] in
            guard let self else { return }
            self.isPlaying = false
            self.stopTimer()
            self.status = "Paused (interrupted)"
        }
    }

    func loadSample(_ sample: SampleTrack) {
        guard let url = Bundle.main.url(forResource: sample.fileName, withExtension: "mp3", subdirectory: "public/samples") else {
            status = "Sample is missing from the iOS bundle"
            return
        }
        load(audioAt: url, persistToLibrary: false, displayTitle: sample.title, sourceName: sample.detail, cacheKey: "sample-\(sample.fileName)")
    }

    func load(audioAt url: URL, persistToLibrary: Bool = true, displayTitle: String? = nil, sourceName: String? = nil, cacheKey: String? = nil) {
        stop()
        loadTask?.cancel()
        let loadID = UUID()
        activeLoadID = loadID
        resetTrackStateForNewFile()
        isProcessing = true
        isReady = false
        progress = 0
        let resolvedTitle = displayTitle ?? url.deletingPathExtension().lastPathComponent
        let resolvedSource = sourceName ?? url.lastPathComponent
        title = resolvedTitle
        status = persistToLibrary ? "Preparing local import and split" : "Loading on-device splitter"
        let pendingImport = persistToLibrary ? createPendingLibraryImport(title: resolvedTitle, sourceName: resolvedSource) : nil

        loadTask = Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let audioURL: URL
                if let pendingImport {
                    await MainActor.run {
                        guard self.activeLoadID == loadID else { return }
                        self.status = "Importing audio into the local library"
                    }
                    audioURL = try copyIntoLibrary(from: url, fileName: pendingImport.fileName)
                    await MainActor.run {
                        self.updateLibraryItem(pendingImport.id) { item in
                            item.status = .processing
                            item.statusMessage = "Importing and splitting"
                            item.lastUpdatedAt = Date()
                        }
                    }
                } else {
                    audioURL = url
                }

                let resolvedCacheKey = cacheKey ?? pendingImport?.fileName
                let result: StemSplitResult
                let servedFromCache: Bool
                if let resolvedCacheKey, let cached = await loadCachedResult(key: resolvedCacheKey, sourceURL: audioURL) {
                    guard self.activeLoadID == loadID else { return }
                    self.status = "Loading cached stems"
                    self.progress = 0.92
                    result = cached
                    servedFromCache = true
                } else {
                    result = try await splitter.split(audioAt: audioURL) { percent, message in
                        Task { @MainActor in
                            guard self.activeLoadID == loadID else { return }
                            self.progress = percent
                            self.status = message
                        }
                    }
                    if let resolvedCacheKey {
                        await storeResult(result, key: resolvedCacheKey)
                    }
                    servedFromCache = false
                }
                try Task.checkCancellation()
                guard activeLoadID == loadID else { return }
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
                if let pendingImport {
                    updateLibraryItem(pendingImport.id) { item in
                        item.title = result.title
                        item.status = .ready
                        item.statusMessage = "Ready at \(Int(result.tempo.bpm.rounded())) bpm"
                        item.duration = result.duration
                        item.lastOpenedAt = Date()
                        item.lastUpdatedAt = Date()
                    }
                }
                rememberProject(result.title)
                StemacleHaptics.success()
                if !servedFromCache {
                    maybeRequestReview()
                }
            } catch is CancellationError {
                guard activeLoadID == loadID else { return }
                isProcessing = false
                isReady = false
                status = "Load cancelled"
                if let pendingImport {
                    updateLibraryItem(pendingImport.id) { item in
                        item.status = .queued
                        item.statusMessage = "Import cancelled"
                        item.lastUpdatedAt = Date()
                    }
                }
            } catch {
                guard activeLoadID == loadID else { return }
                isProcessing = false
                isReady = false
                status = error.localizedDescription
                StemacleHaptics.failure()
                if let pendingImport {
                    updateLibraryItem(pendingImport.id) { item in
                        item.status = .failed
                        item.statusMessage = error.localizedDescription
                        item.lastUpdatedAt = Date()
                    }
                }
            }
        }
    }

    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        activeLoadID = UUID()
        isProcessing = false
        isReady = false
        progress = 0
        status = "Load cancelled"
    }

    func togglePlay() {
        StemacleHaptics.transport()
        isPlaying ? pause() : play()
    }

    func play() {
        guard isReady else {
            status = isProcessing ? "Still preparing the current track" : "Choose a track before playback"
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
        if isPlaying {
            play()
        } else {
            updateMix()
        }
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
        StemacleHaptics.tap()
        controls[stem]?.isMuted.toggle()
        updateMix()
    }

    func toggleGlobalMute() {
        StemacleHaptics.tap()
        globalMuted.toggle()
        updateMix()
    }

    func setHeadphones(stem: Stem?) {
        StemacleHaptics.toggle()
        let next = headphonesStem == stem ? nil : stem
        setAuditionStem(next)
    }

    func setLoopMonitorMode(_ mode: LoopMonitorMode) {
        StemacleHaptics.toggle()
        loopMonitorMode = mode
        if mode == .mix {
            setAuditionStem(nil)
        } else {
            setAuditionStem(effectiveHeadphonesStem())
        }
    }

    func applyLoop(stem: Stem, index: Int) {
        guard isReady else {
            status = "Choose a track before looping"
            return
        }
        StemacleHaptics.loopEngaged()

        if loops[stem]?.selectedIndex == index {
            loops[stem] = .inactive
            if loopMonitorMode == .solo, headphonesStem == stem {
                setAuditionStem(firstActiveLoopStem())
            }
            updateSpectralWindow(currentTime)
            replayIfNeeded(changedStems: [stem])
            return
        }

        guard let range = loopRange(forIndex: index) else {
            loops[stem] = .inactive
            status = "Loop would run past the end"
            updateSpectralWindow(currentTime)
            replayIfNeeded(changedStems: [stem])
            return
        }

        loops[stem] = StemLoop(selectedIndex: index, start: range.start, end: range.end)
        if loopMonitorMode == .solo {
            setAuditionStem(stem)
        }
        updateSpectralWindow(currentTime)
        replayIfNeeded(changedStems: [stem])
    }

    func applyLoopToAll(index: Int) {
        guard isReady else {
            status = "Choose a track before looping"
            return
        }
        StemacleHaptics.loopEngaged()

        if Stem.allCases.allSatisfy({ loops[$0]?.selectedIndex == index }) {
            for stem in Stem.allCases {
                loops[stem] = .inactive
            }
            if loopMonitorMode == .solo {
                setAuditionStem(nil)
            }
            updateSpectralWindow(currentTime)
            replayIfNeeded(changedStems: Array(Stem.allCases))
            return
        }

        guard let range = loopRange(forIndex: index) else {
            for stem in Stem.allCases {
                loops[stem] = .inactive
            }
            if loopMonitorMode == .solo {
                setAuditionStem(nil)
            }
            status = "Linked loop would run past the end"
            updateSpectralWindow(currentTime)
            replayIfNeeded(changedStems: Array(Stem.allCases))
            return
        }

        for stem in Stem.allCases {
            loops[stem] = StemLoop(selectedIndex: index, start: range.start, end: range.end)
        }
        if loopMonitorMode == .solo {
            setAuditionStem(firstActiveLoopStem())
        }
        updateSpectralWindow(currentTime)
        replayIfNeeded(changedStems: Array(Stem.allCases))
    }

    func resetMixer() {
        controls = Dictionary(uniqueKeysWithValues: Stem.allCases.map { ($0, StemPlaybackControl()) })
        globalMuted = false
        headphonesStem = nil
        updateMix()
    }

    func clearLoops() {
        loops = Dictionary(uniqueKeysWithValues: Stem.allCases.map { ($0, StemLoop.inactive) })
        if loopMonitorMode == .solo {
            setAuditionStem(nil)
        }
        updateSpectralWindow(currentTime)
        replayIfNeeded(changedStems: Array(Stem.allCases))
    }

    /// Reads a cached split off the main thread so a big cache decode never janks
    /// the UI. Returns `nil` on any miss so the caller re-separates.
    private func loadCachedResult(key: String, sourceURL: URL) async -> StemSplitResult? {
        let cache = stemCache
        return await Task.detached(priority: .userInitiated) {
            cache.cachedResult(forKey: key, sourceURL: sourceURL)
        }.value
    }

    /// Writes a fresh split to the cache off the main thread; best-effort.
    private func storeResult(_ result: StemSplitResult, key: String) async {
        let cache = stemCache
        await Task.detached(priority: .utility) {
            cache.store(result, forKey: key)
        }.value
    }

    func didRequestReview() {
        shouldRequestReview = false
        UserDefaults.standard.set(currentAppVersion(), forKey: reviewedVersionKey)
    }

    private func maybeRequestReview() {
        let count = successfulSplitCount + 1
        successfulSplitCount = count
        let reviewedVersion = UserDefaults.standard.string(forKey: reviewedVersionKey)
        if count >= 3, reviewedVersion != currentAppVersion() {
            shouldRequestReview = true
        }
    }

    private func currentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func resetTrackStateForNewFile() {
        loops = Dictionary(uniqueKeysWithValues: Stem.allCases.map { ($0, StemLoop.inactive) })
        headphonesStem = nil
        loopMonitorMode = preferSoloLoopMonitor ? .solo : .mix
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

    func spectralValues(for stem: Stem, bucketCount: Int) -> [Float] {
        guard bucketCount > 0 else { return [] }
        guard let values = overview[stem], !values.isEmpty else { return [] }
        let safeDuration = max(0.001, duration)
        let windowStart = spectralWindow.start / safeDuration
        let windowEnd = spectralWindow.end / safeDuration
        let span = max(0.000_001, windowEnd - windowStart)

        return (0..<bucketCount).map { bucket in
            let bucketStart = windowStart + span * (Double(bucket) / Double(bucketCount))
            let bucketMiddle = windowStart + span * ((Double(bucket) + 0.5) / Double(bucketCount))
            let bucketEnd = windowStart + span * (Double(bucket + 1) / Double(bucketCount))
            return max(
                interpolatedOverviewValue(values, ratio: bucketStart),
                interpolatedOverviewValue(values, ratio: bucketMiddle),
                interpolatedOverviewValue(values, ratio: bucketEnd)
            )
        }
    }

    func levelMeterBands() -> LevelMeterBands {
        guard isReady else {
            return LevelMeterBands(bass: 0.08, treble: 0.10, wave: 0.14)
        }

        let bassEnergy = stemEnergy(stem: .bass)
        let drumEnergy = stemEnergy(stem: .drums)
        let vocalEnergy = stemEnergy(stem: .vocals)
        let melodyEnergy = stemEnergy(stem: .melody)
        let trebleEnergy = max(drumEnergy * 0.78, max(vocalEnergy * 0.48, melodyEnergy * 0.72))
        let bodyEnergy = (bassEnergy + drumEnergy + vocalEnergy + melodyEnergy) / 4

        return LevelMeterBands(
            bass: 0.08 + min(1, bassEnergy * 1.28) * 0.56,
            treble: 0.10 + min(1, trebleEnergy * 1.32) * 0.54,
            wave: isPlaying ? 0.18 + min(1, bodyEnergy * 1.65) * 0.72 : 0.14
        )
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
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
        timer?.tolerance = 0.03
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

    private func replayIfNeeded(changedStems: [Stem]? = nil) {
        if isPlaying {
            do {
                let stems = Set(changedStems ?? Array(Stem.allCases))
                try audioEngine.reschedule(
                    stems: stems,
                    controls: controls,
                    loops: loops,
                    globalMute: globalMuted,
                    headphonesStem: effectiveHeadphonesStem(),
                    loopMonitorMode: loopMonitorMode
                )
                currentTime = audioEngine.currentOffset()
                updateSpectralWindow(currentTime)
            } catch {
                status = error.localizedDescription
            }
        } else {
            updateMix()
        }
    }

    private func setAuditionStem(_ stem: Stem?) {
        headphonesStem = stem
        for candidate in Stem.allCases {
            controls[candidate]?.isHeadphones = candidate == stem
        }
        updateMix()
    }

    private func effectiveHeadphonesStem() -> Stem? {
        if let headphonesStem {
            return headphonesStem
        }
        guard loopMonitorMode == .solo else {
            return nil
        }
        return firstActiveLoopStem()
    }

    private func firstActiveLoopStem() -> Stem? {
        Stem.allCases.first { loops[$0]?.isActive == true }
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

    private func stemEnergy(stem: Stem) -> Double {
        guard let values = overview[stem], !values.isEmpty else { return 0 }
        let control = controls[stem] ?? StemPlaybackControl()
        if globalMuted || control.isMuted {
            return 0
        }
        if let headphonesStem, headphonesStem != stem {
            return 0
        }

        let safeDuration = max(0.001, duration)
        let time = audibleStemTime(stem: stem, transportSec: currentTime)
        let ratio = playbackOffset(time) / safeDuration
        let center = ratio * Double(max(0, values.count - 1))
        let start = max(0, Int(floor(center)) - 1)
        let end = min(values.count - 1, Int(ceil(center)) + 1)
        let peak = values[start...end].reduce(Float(0)) { max($0, $1) }
        let interpolated = interpolatedOverviewValue(values, ratio: ratio)
        return Double(max(peak * 0.72, interpolated)) * Double(control.volume)
    }

    private func interpolatedOverviewValue(_ values: [Float], ratio: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        if values.count == 1 { return values[0] }
        let scaled = min(1, max(0, ratio)) * Double(values.count - 1)
        let lower = Int(floor(scaled))
        let upper = min(values.count - 1, lower + 1)
        let fraction = Float(scaled - Double(lower))
        return values[lower] + (values[upper] - values[lower]) * fraction
    }

    private func updateSpectralWindow(_ time: TimeInterval? = nil) {
        spectralWindow = spectralWindowFor(time ?? currentTime)
    }

    private func rememberProject(_ name: String) {
        recentProjects.removeAll { $0 == name }
        recentProjects.insert(name, at: 0)
        recentProjects = Array(recentProjects.prefix(6))
    }

    var visibleLibraryItems: [StemLibraryItem] {
        let filtered = libraryItems.filter { item in
            switch libraryFilter {
            case .all:
                return true
            case .ready:
                return item.status == .ready
            case .queued:
                return item.status == .queued
            case .processing:
                return item.status == .processing
            case .failed:
                return item.status == .failed
            }
        }

        return filtered.sorted { left, right in
            switch librarySort {
            case .recent:
                return left.lastUpdatedAt > right.lastUpdatedAt
            case .name:
                return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            case .status:
                if left.status != right.status {
                    return left.status.sortRank < right.status.sortRank
                }
                return left.lastUpdatedAt > right.lastUpdatedAt
            }
        }
    }

    var queueLibraryItems: [StemLibraryItem] {
        libraryItems
            .filter { $0.status != .ready }
            .sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }
    }

    func openLibraryItem(_ item: StemLibraryItem) {
        let url = libraryDirectoryURL().appendingPathComponent(item.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            status = "That track is no longer available locally."
            return
        }
        load(audioAt: url, persistToLibrary: false, displayTitle: item.title, sourceName: item.sourceName, cacheKey: item.fileName)
        updateLibraryItem(item.id) { record in
            record.lastOpenedAt = Date()
            record.lastUpdatedAt = Date()
            if record.status == .failed {
                record.status = .queued
                record.statusMessage = "Reopened"
            }
        }
    }

    private func createPendingLibraryImport(title: String, sourceName: String) -> PendingLibraryImport {
        let now = Date()
        let id = UUID().uuidString
        let fileName = uniqueLibraryFileName(for: sourceName)
        let item = StemLibraryItem(
            id: id,
            title: title,
            sourceName: sourceName,
            fileName: fileName,
            addedAt: now,
            lastOpenedAt: now,
            status: .queued,
            statusMessage: "Waiting to import",
            duration: nil,
            lastUpdatedAt: now
        )
        libraryItems.insert(item, at: 0)
        persistLibraryItems()
        return PendingLibraryImport(id: id, fileName: fileName)
    }

    private func updateLibraryItem(_ id: String, mutate: (inout StemLibraryItem) -> Void) {
        guard let index = libraryItems.firstIndex(where: { $0.id == id }) else { return }
        var item = libraryItems[index]
        mutate(&item)
        libraryItems[index] = item
        persistLibraryItems()
    }

    private func loadLibraryItems() {
        guard let data = try? Data(contentsOf: libraryIndexURL()) else {
            libraryItems = []
            recentProjects = []
            return
        }
        do {
            libraryItems = try JSONDecoder().decode([StemLibraryItem].self, from: data)
            recentProjects = libraryItems.prefix(6).map { $0.title }
        } catch {
            libraryItems = []
            recentProjects = []
        }
    }

    private func persistLibraryItems() {
        do {
            try FileManager.default.createDirectory(at: libraryDirectoryURL(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(libraryItems)
            try data.write(to: libraryIndexURL(), options: [.atomic])
        } catch {
            status = error.localizedDescription
        }
    }

    private func copyIntoLibrary(from url: URL, fileName: String) throws -> URL {
        let directory = libraryDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        }
        throw NSError(domain: "StemacleLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: "The selected track could not be copied locally."])
    }

    private func libraryDirectoryURL() -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root.appendingPathComponent(libraryDirectoryName, isDirectory: true)
    }

    private func libraryIndexURL() -> URL {
        libraryDirectoryURL().appendingPathComponent("library.json")
    }

    private func uniqueLibraryFileName(for sourceName: String) -> String {
        let nsSourceName = sourceName as NSString
        let base = nsSourceName
            .deletingPathExtension
            .replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let safeBase = base.isEmpty ? "stemacle-track" : base.lowercased()
        let ext = nsSourceName.pathExtension.isEmpty ? "audio" : nsSourceName.pathExtension.lowercased()
        return "\(safeBase)-\(UUID().uuidString.prefix(8)).\(ext)"
    }
}

private struct PendingLibraryImport {
    let id: String
    let fileName: String
}

private extension StemLibraryItem.Status {
    var sortRank: Int {
        switch self {
        case .processing:
            return 0
        case .queued:
            return 1
        case .failed:
            return 2
        case .ready:
            return 3
        }
    }
}
