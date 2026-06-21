import AVFoundation
import Foundation
import OnnxRuntimeBindings

private let modelDownloadBaseURL = URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-spleeter-2stems/resolve/main/")!

enum Stem: String, CaseIterable, Identifiable, Hashable {
    case drums
    case vocals
    case bass
    case melody

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drums: return "Drums"
        case .vocals: return "Vocals"
        case .bass: return "Bass"
        case .melody: return "Melody"
        }
    }

    var symbolName: String {
        switch self {
        case .drums: return "circle.grid.cross"
        case .vocals: return "mic"
        case .bass: return "waveform.path.ecg"
        case .melody: return "music.note"
        }
    }
}

struct TempoEstimate: Equatable {
    var bpm: Double
    var confidence: Double
    var beatOffset: TimeInterval
    var measureOffset: TimeInterval
}

struct StemPlaybackControl: Equatable {
    var volume: Float = 0.8
    var isMuted = false
    var isHeadphones = false
}

struct StemLoop: Equatable {
    var selectedIndex: Int?
    var start: TimeInterval
    var end: TimeInterval

    static let inactive = StemLoop(selectedIndex: nil, start: 0, end: 0)

    var isActive: Bool {
        selectedIndex != nil && end > start
    }
}

enum LoopMonitorMode: String, CaseIterable, Identifiable {
    case mix
    case solo

    var id: String { rawValue }
}

struct SampleTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let fileName: String
}

struct StemSplitResult {
    let sourceURL: URL
    let title: String
    let duration: TimeInterval
    let sampleRate: Double
    let tempo: TempoEstimate
    let buffers: [Stem: AVAudioPCMBuffer]
    let overview: [Stem: [Float]]
}

private struct ModelSessions: @unchecked Sendable {
    let vocals: ORTSession
    let accompaniment: ORTSession
}

private final class ModelCache {
    private let lock = NSLock()
    private var cachedSessions: ModelSessions?
    private var loadingTask: Task<ModelSessions, Error>?

    func sessions(progress: @escaping @Sendable (Double, String) -> Void) async throws -> ModelSessions {
        lock.lock()
        if let cachedSessions {
            lock.unlock()
            return cachedSessions
        }
        if let loadingTask {
            lock.unlock()
            return try await loadingTask.value
        }

        let task = Task {
            try await NativeStemSplitter.loadModelSessions(progress: progress)
        }
        loadingTask = task
        lock.unlock()

        do {
            let sessions = try await task.value
            lock.lock()
            cachedSessions = sessions
            loadingTask = nil
            lock.unlock()
            return sessions
        } catch {
            lock.lock()
            loadingTask = nil
            lock.unlock()
            throw error
        }
    }
}

enum StemSplitterError: LocalizedError {
    case unreadableAudio
    case unsupportedFormat
    case unableToCreateBuffer

    var errorDescription: String? {
        switch self {
        case .unreadableAudio:
            return "Stemacle could not read that audio file."
        case .unsupportedFormat:
            return "Stemacle needs PCM audio after iOS decodes the file."
        case .unableToCreateBuffer:
            return "Stemacle could not prepare the native stem buffers."
        }
    }
}

final class NativeStemSplitter: @unchecked Sendable {
    private struct AudioFrameData {
        var left: [Float]
        var right: [Float]
        var mono: [Float]
        var sampleRate: Double
    }

    private struct Spectrogram {
        var real: [[Float]]
        var imaginary: [[Float]]
        var frameCount: Int
    }

    private struct HpssResult {
        var harmonicReal: [[Float]]
        var harmonicImaginary: [[Float]]
        var percussiveReal: [[Float]]
        var percussiveImaginary: [[Float]]
    }

    private struct SpectralSplit {
        var lowReal: [[Float]]
        var lowImaginary: [[Float]]
        var highReal: [[Float]]
        var highImaginary: [[Float]]
    }

    private struct TempoCandidate {
        var lag: Int
        var rawBpm: Double
        var bpm: Double
        var score: Double
    }

    private let fftSize = 4096
    private let hopSize = 1024
    private let modelBins = 1024
    private let segmentFrames = 512
    private let nativeSpectralDurationLimit: TimeInterval = 45
    private var totalBins: Int { (fftSize / 2) + 1 }

    private let bpmMin = 60.0
    private let bpmMax = 240.0
    private let bpmFallback = 120.0
    private let bpmPreferredMin = 80.0
    private let bpmPreferredMax = 180.0
    private let tempoMinConfidence = 0.04
    private static let modelCache = ModelCache()

    func split(audioAt url: URL, progress: @escaping @Sendable (Double, String) -> Void = { _, _ in }) async throws -> StemSplitResult {
        let task = Task.detached(priority: .userInitiated) { [self] in
            try await performSplit(audioAt: url, progress: progress)
        }

        return try await withTaskCancellationHandler(operation: {
            try await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    private func performSplit(
        audioAt url: URL,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> StemSplitResult {
        try Task.checkCancellation()
        progress(0.03, "Reading audio with AVFoundation")
        let source = try readAudio(url)
        let duration = Double(source.mono.count) / source.sampleRate

        try Task.checkCancellation()
        progress(0.08, "Audio decoded. Tempo mapped.")
        let tempo = estimateTempo(source.mono, sampleRate: source.sampleRate)

        try Task.checkCancellation()
        let sessions = try await Self.modelCache.sessions(progress: progress)
        let stemSamples = try modelBackedSplit(
            source: source,
            duration: duration,
            sessions: sessions,
            progress: progress
        )

        try Task.checkCancellation()
        progress(0.9, "Preparing native buffers")
        var buffers: [Stem: AVAudioPCMBuffer] = [:]
        var overview: [Stem: [Float]] = [:]
        for stem in Stem.allCases {
            try Task.checkCancellation()
            guard let samples = stemSamples[stem] else { continue }
            let prepared = trimOrPad(samples, count: source.mono.count)
            buffers[stem] = try makeBuffer(samples: prepared, sampleRate: source.sampleRate)
            overview[stem] = spectralOverview(prepared, buckets: 192)
        }

        progress(1.0, "Stems ready")
        return StemSplitResult(
            sourceURL: url,
            title: url.deletingPathExtension().lastPathComponent,
            duration: duration,
            sampleRate: source.sampleRate,
            tempo: tempo,
            buffers: buffers,
            overview: overview
        )
    }

    private func modelBackedSplit(
        source: AudioFrameData,
        duration: TimeInterval,
        sessions: ModelSessions,
        progress: @escaping @Sendable (Double, String) -> Void
    ) throws -> [Stem: [Float]] {
        try Task.checkCancellation()
        let window = hann(fftSize)

        progress(0.10, "Computing left spectrogram")
        let leftSpectrogram = stft(source.left, window: window) { fraction in
            progress(0.10 + (0.12 * fraction), "Computing left spectrogram")
        }

        try Task.checkCancellation()
        progress(0.22, "Computing right spectrogram")
        let rightSpectrogram = stft(source.right, window: window) { fraction in
            progress(0.22 + (0.12 * fraction), "Computing right spectrogram")
        }

        let frameCount = leftSpectrogram.frameCount
        let binCount = totalBins

        try Task.checkCancellation()
        progress(0.34, "Measuring left channel")
        let leftMagnitude = buildMagnitude(leftSpectrogram) { fraction in
            progress(0.34 + (0.04 * fraction), "Measuring left channel")
        }

        try Task.checkCancellation()
        progress(0.38, "Measuring right channel")
        let rightMagnitude = buildMagnitude(rightSpectrogram) { fraction in
            progress(0.38 + (0.04 * fraction), "Measuring right channel")
        }

        try Task.checkCancellation()
        progress(0.44, "Separating vocals with local model")
        let vocalMask = try buildVocalMask(
            leftMagnitude: leftMagnitude,
            rightMagnitude: rightMagnitude,
            frameCount: frameCount,
            sessions: sessions
        ) { fraction in
            progress(0.44 + (0.24 * fraction), "Separating vocals with local model")
        }

        progress(0.70, "Applying masks")
        var vocalReal = emptyRows(frameCount: frameCount, binCount: binCount)
        var vocalImaginary = emptyRows(frameCount: frameCount, binCount: binCount)
        var accompanimentReal = emptyRows(frameCount: frameCount, binCount: binCount)
        var accompanimentImaginary = emptyRows(frameCount: frameCount, binCount: binCount)
        let maskStride = max(1, frameCount / 24)
        for frame in 0..<frameCount {
            for bin in 0..<binCount {
                let monoReal = (leftSpectrogram.real[frame][bin] + rightSpectrogram.real[frame][bin]) * 0.5
                let monoImaginary = (leftSpectrogram.imaginary[frame][bin] + rightSpectrogram.imaginary[frame][bin]) * 0.5
                let mask = bin < modelBins ? vocalMask[(frame * modelBins) + bin] : 0
                vocalReal[frame][bin] = monoReal * mask
                vocalImaginary[frame][bin] = monoImaginary * mask
                accompanimentReal[frame][bin] = monoReal * (1 - mask)
                accompanimentImaginary[frame][bin] = monoImaginary * (1 - mask)
            }
            if frame % maskStride == 0 || frame == frameCount - 1 {
                try Task.checkCancellation()
                progress(0.70 + (0.04 * Double(frame + 1) / Double(frameCount)), "Applying masks")
            }
        }

        try Task.checkCancellation()
        let separated = hpss(
            realRows: accompanimentReal,
            imaginaryRows: accompanimentImaginary,
            frameCount: frameCount,
            binCount: binCount
        ) { fraction, message in
            progress(0.74 + (0.08 * fraction), message)
        }

        try Task.checkCancellation()
        progress(0.83, "Extracting bass")
        let bassAndMelody = lowPassSpectrogram(
            realRows: separated.harmonicReal,
            imaginaryRows: separated.harmonicImaginary,
            frameCount: frameCount,
            binCount: binCount,
            cutoffHz: 300,
            sampleRate: source.sampleRate
        )

        let targetCount = max(1, Int(ceil(duration * source.sampleRate)))

        try Task.checkCancellation()
        progress(0.86, "Synthesizing drums")
        let drums = trimOrPad(istft(
            realRows: separated.percussiveReal,
            imaginaryRows: separated.percussiveImaginary,
            frameCount: frameCount,
            window: window
        ) { fraction in
            progress(0.86 + (0.03 * fraction), "Synthesizing drums")
        }, count: targetCount)

        try Task.checkCancellation()
        progress(0.89, "Synthesizing vocals")
        let vocals = trimOrPad(istft(
            realRows: vocalReal,
            imaginaryRows: vocalImaginary,
            frameCount: frameCount,
            window: window
        ) { fraction in
            progress(0.89 + (0.03 * fraction), "Synthesizing vocals")
        }, count: targetCount)

        try Task.checkCancellation()
        progress(0.92, "Synthesizing bass")
        let bass = trimOrPad(istft(
            realRows: bassAndMelody.lowReal,
            imaginaryRows: bassAndMelody.lowImaginary,
            frameCount: frameCount,
            window: window
        ) { fraction in
            progress(0.92 + (0.03 * fraction), "Synthesizing bass")
        }, count: targetCount)

        try Task.checkCancellation()
        progress(0.95, "Synthesizing melody")
        let melody = trimOrPad(istft(
            realRows: bassAndMelody.highReal,
            imaginaryRows: bassAndMelody.highImaginary,
            frameCount: frameCount,
            window: window
        ) { fraction in
            progress(0.95 + (0.03 * fraction), "Synthesizing melody")
        }, count: targetCount)

        return [
            .drums: drums,
            .vocals: vocals,
            .bass: bass,
            .melody: melody,
        ]
    }

    fileprivate static func loadModelSessions(progress: @escaping @Sendable (Double, String) -> Void) async throws -> ModelSessions {
        progress(0.10, "Opening vocals model")
        let env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        let options = try ORTSessionOptions()
        try options.setLogSeverityLevel(ORTLoggingLevel.warning)
        try options.setIntraOpNumThreads(1)

        let vocalsURL = try await downloadModelFile(
            named: "vocals.onnx",
            remoteURL: modelDownloadBaseURL.appendingPathComponent("vocals.onnx"),
            progress: { percent, message in
                progress(0.10 + (0.32 * percent), message)
            }
        )
        progress(0.44, "Preparing vocals model")
        let vocals = try ORTSession(env: env, modelPath: vocalsURL.path, sessionOptions: options)

        progress(0.52, "Opening accompaniment model")
        let accompanimentURL = try await downloadModelFile(
            named: "accompaniment.onnx",
            remoteURL: modelDownloadBaseURL.appendingPathComponent("accompaniment.onnx"),
            progress: { percent, message in
                progress(0.52 + (0.40 * percent), message)
            }
        )
        progress(0.94, "Preparing accompaniment model")
        let accompaniment = try ORTSession(env: env, modelPath: accompanimentURL.path, sessionOptions: options)

        progress(1.0, "Separation models ready")
        return ModelSessions(vocals: vocals, accompaniment: accompaniment)
    }

    private static func downloadModelFile(
        named: String,
        remoteURL: URL,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> URL {
        let directory = try modelCacheDirectory()
        let localURL = directory.appendingPathComponent(named)
        if FileManager.default.fileExists(atPath: localURL.path) {
            progress(1.0, "Loaded cached \(named)")
            return localURL
        }

        progress(0.05, "Downloading \(named)")
        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StemSplitterError.unreadableAudio
        }
        try data.write(to: localURL, options: .atomic)
        progress(1.0, "Downloaded \(named)")
        return localURL
    }

    private static func modelCacheDirectory() throws -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = baseDirectory.appendingPathComponent("Stemacle/Model Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func readAudio(_ url: URL) throws -> AudioFrameData {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCapacity = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            throw StemSplitterError.unableToCreateBuffer
        }
        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData else {
            throw StemSplitterError.unsupportedFormat
        }

        let frames = Int(buffer.frameLength)
        guard frames > 0 else { throw StemSplitterError.unreadableAudio }

        let channelCount = max(1, Int(format.channelCount))
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        var mono = [Float](repeating: 0, count: frames)

        for index in 0..<frames {
            let leftSample = channelData[0][index]
            let rightSample = channelData[min(1, channelCount - 1)][index]
            left[index] = leftSample
            right[index] = rightSample
            mono[index] = (leftSample + rightSample) * 0.5
        }

        return AudioFrameData(left: left, right: right, mono: mono, sampleRate: format.sampleRate)
    }

    func estimateTempo(_ samples: [Float], sampleRate: Double) -> TempoEstimate {
        guard samples.count > Int(sampleRate * 5), sampleRate > 0 else {
            return tempoFallback()
        }

        let frame = max(1, Int(sampleRate * 0.03))
        let hop = max(1, Int(sampleRate * 0.01))
        let frameCount = max(0, (samples.count - frame) / hop)
        guard frameCount > 8 else {
            return tempoFallback()
        }

        var onset = [Double](repeating: 0, count: frameCount)
        var smoothed = 0.0
        var previous = 0.0
        var total = 0.0
        for frameIndex in 0..<frameCount {
            let base = frameIndex * hop
            var rms = 0.0
            for sampleIndex in 0..<frame {
                let sample = Double(samples[base + sampleIndex])
                rms += sample * sample
            }
            rms = sqrt(rms / Double(frame))
            smoothed = (smoothed * 0.84) + (rms * 0.16)
            let delta = smoothed - previous
            onset[frameIndex] = max(0, delta)
            previous = smoothed
            total += onset[frameIndex]
        }

        guard total > 0 else {
            return tempoFallback()
        }

        let mean = onset.reduce(0, +) / Double(onset.count)
        var energy = 0.0
        for value in onset {
            let delta = value - mean
            energy += delta * delta
        }
        guard energy >= 1e-10 else {
            return tempoFallback()
        }

        let hopSeconds = Double(hop) / sampleRate
        let minLag = max(1, Int(round((60 / bpmMax) / hopSeconds)))
        let maxLag = max(minLag + 1, Int(floor((60 / bpmMin) / hopSeconds)))
        let cappedMaxLag = min(maxLag, frameCount - 2)
        guard minLag < cappedMaxLag else {
            return tempoFallback()
        }

        var candidates: [TempoCandidate] = []
        var bestScore = -Double.infinity
        var bestLag = -1
        for lag in minLag...cappedMaxLag {
            var cross = 0.0
            var a2 = 0.0
            var b2 = 0.0
            for index in lag..<frameCount {
                let a = onset[index] - mean
                let b = onset[index - lag] - mean
                cross += a * b
                a2 += a * a
                b2 += b * b
            }
            let score = cross / sqrt((a2 * b2) + 1e-12)
            var bpm = 60 / (Double(lag) * hopSeconds)
            let rawBpm = bpm
            while bpm < bpmMin { bpm *= 2 }
            while bpm > bpmMax { bpm /= 2 }
            candidates.append(TempoCandidate(lag: lag, rawBpm: rawBpm, bpm: bpm, score: score))
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }

        guard bestScore.isFinite, bestLag > 0, bestScore >= tempoMinConfidence else {
            return tempoFallback(confidence: max(0, bestScore))
        }

        let selected = chooseTempoCandidate(candidates)
        var bestOffset = 0
        var bestOffsetScore = -Double.infinity
        for offset in 0..<selected.lag {
            var score = 0.0
            var index = offset
            while index < frameCount {
                score += onset[index]
                index += selected.lag
            }
            if score > bestOffsetScore {
                bestOffsetScore = score
                bestOffset = offset
            }
        }

        let beatOffset = Double(bestOffset) * hopSeconds
        let measureOffset = estimateMeasureOffset(
            onset: onset,
            frameCount: frameCount,
            beatLag: selected.lag,
            beatOffsetFrame: bestOffset,
            hopSeconds: hopSeconds
        )

        return TempoEstimate(
            bpm: min(bpmMax, max(bpmMin, selected.bpm)),
            confidence: selected.score,
            beatOffset: beatOffset,
            measureOffset: measureOffset
        )
    }

    private func tempoFallback(confidence: Double = 0) -> TempoEstimate {
        TempoEstimate(bpm: bpmFallback, confidence: confidence, beatOffset: 0, measureOffset: 0)
    }

    private func chooseTempoCandidate(_ candidates: [TempoCandidate]) -> TempoCandidate {
        let sorted = candidates
            .filter { $0.score.isFinite && $0.bpm.isFinite && $0.lag > 0 }
            .sorted { $0.score > $1.score }
        guard let best = sorted.first else {
            return TempoCandidate(lag: 1, rawBpm: bpmFallback, bpm: bpmFallback, score: 0)
        }
        if best.bpm < bpmPreferredMin || best.bpm > bpmPreferredMax {
            if let preferred = sorted.first(where: {
                $0.bpm >= bpmPreferredMin &&
                $0.bpm <= bpmPreferredMax &&
                $0.score >= best.score * 0.85
            }) {
                return preferred
            }
        }
        return best
    }

    private func onsetScoreAt(_ onset: [Double], frameCount: Int, offset: Int, stride: Int) -> Double {
        var score = 0.0
        var count = 0.0
        var index = offset
        while index < frameCount {
            score += onset[index]
            if index > 0 { score += onset[index - 1] * 0.5 }
            if index + 1 < frameCount { score += onset[index + 1] * 0.5 }
            count += 1
            index += stride
        }
        return count > 0 ? score / count : 0
    }

    private func estimateMeasureOffset(
        onset: [Double],
        frameCount: Int,
        beatLag: Int,
        beatOffsetFrame: Int,
        hopSeconds: Double
    ) -> TimeInterval {
        let beatOffset = Double(beatOffsetFrame) * hopSeconds
        let measureLag = beatLag * 4
        guard measureLag < frameCount else {
            return beatOffset
        }

        var phases: [(offset: TimeInterval, score: Double)] = []
        for phase in 0..<4 {
            let offsetFrame = beatOffsetFrame + (phase * beatLag)
            phases.append((
                offset: Double(offsetFrame) * hopSeconds,
                score: onsetScoreAt(onset, frameCount: frameCount, offset: offsetFrame, stride: measureLag)
            ))
        }
        phases.sort { $0.score > $1.score }

        guard let best = phases.first else { return beatOffset }
        let second = phases.dropFirst().first?.score ?? 0
        let total = phases.reduce(0) { $0 + $1.score }
        let share = total > 0 ? best.score / total : 0
        let confidence = best.score > 0 ? (best.score - second) / best.score : 0
        if confidence >= 0.12, share >= 0.36 {
            return best.offset
        }
        return beatOffset
    }

    private func hann(_ count: Int) -> [Float] {
        guard count > 0 else { return [] }
        var window = [Float](repeating: 0, count: count)
        for index in 0..<count {
            window[index] = Float(0.5 - (0.5 * cos((2 * Double.pi * Double(index)) / Double(count))))
        }
        return window
    }

    private func stft(_ signal: [Float], window: [Float], onProgress: ((Double) -> Void)? = nil) -> Spectrogram {
        let frameCount = max(1, signal.count > fftSize ? ((signal.count - fftSize) / hopSize) + 1 : 1)
        let binCount = totalBins
        var realRows: [[Float]] = []
        var imaginaryRows: [[Float]] = []
        realRows.reserveCapacity(frameCount)
        imaginaryRows.reserveCapacity(frameCount)

        var frameReal = [Float](repeating: 0, count: fftSize)
        var frameImaginary = [Float](repeating: 0, count: fftSize)
        let stride = max(1, frameCount / 24)

        for frame in 0..<frameCount {
            let start = frame * hopSize
            for index in 0..<fftSize {
                let sampleIndex = start + index
                frameReal[index] = (sampleIndex < signal.count ? signal[sampleIndex] : 0) * window[index]
                frameImaginary[index] = 0
            }
            fftIP(real: &frameReal, imaginary: &frameImaginary)
            realRows.append(Array(frameReal.prefix(binCount)))
            imaginaryRows.append(Array(frameImaginary.prefix(binCount)))
            if frame % stride == 0 || frame == frameCount - 1 {
                onProgress?(Double(frame + 1) / Double(frameCount))
            }
        }

        return Spectrogram(real: realRows, imaginary: imaginaryRows, frameCount: frameCount)
    }

    private func buildMagnitude(_ spectrogram: Spectrogram, onProgress: ((Double) -> Void)? = nil) -> [[Float]] {
        var magnitude: [[Float]] = []
        magnitude.reserveCapacity(spectrogram.frameCount)
        let stride = max(1, spectrogram.frameCount / 24)
        for frame in 0..<spectrogram.frameCount {
            var row = [Float](repeating: 0, count: modelBins)
            for bin in 0..<modelBins {
                row[bin] = hypotf(spectrogram.real[frame][bin], spectrogram.imaginary[frame][bin])
            }
            magnitude.append(row)
            if frame % stride == 0 || frame == spectrogram.frameCount - 1 {
                onProgress?(Double(frame + 1) / Double(spectrogram.frameCount))
            }
        }
        return magnitude
    }

    private func buildVocalMask(
        leftMagnitude: [[Float]],
        rightMagnitude: [[Float]],
        frameCount: Int,
        sessions: ModelSessions,
        onProgress: ((Double) -> Void)? = nil
    ) throws -> [Float] {
        var mask = [Float](repeating: 0, count: frameCount * modelBins)
        let segmentCount = max(1, Int(ceil(Double(frameCount) / Double(segmentFrames))))
        let stride = max(1, segmentCount / 12)
        let inputShape: [NSNumber] = [
            NSNumber(value: 2),
            NSNumber(value: 1),
            NSNumber(value: segmentFrames),
            NSNumber(value: modelBins),
        ]

        for segment in 0..<segmentCount {
            var segmentData = [Float](repeating: 0, count: 2 * segmentFrames * modelBins)
            let segmentBase = segment * segmentFrames
            for frameIndex in 0..<segmentFrames {
                let frame = segmentBase + frameIndex
                guard frame < frameCount else { break }
                let leftBase = frameIndex * modelBins
                let rightBase = (segmentFrames + frameIndex) * modelBins
                for bin in 0..<modelBins {
                    segmentData[leftBase + bin] = leftMagnitude[frame][bin]
                    segmentData[rightBase + bin] = rightMagnitude[frame][bin]
                }
            }

            let vocalsOutput = try runModel(session: sessions.vocals, inputData: segmentData, inputShape: inputShape)
            let accompanimentOutput = try runModel(session: sessions.accompaniment, inputData: segmentData, inputShape: inputShape)

            for frameIndex in 0..<segmentFrames {
                let frame = segmentBase + frameIndex
                guard frame < frameCount else { break }
                let leftBase = frameIndex * modelBins
                let rightBase = (segmentFrames + frameIndex) * modelBins
                for bin in 0..<modelBins {
                    let vocalPower = (vocalsOutput[leftBase + bin] * vocalsOutput[leftBase + bin]) + (vocalsOutput[rightBase + bin] * vocalsOutput[rightBase + bin])
                    let accompanimentPower = (accompanimentOutput[leftBase + bin] * accompanimentOutput[leftBase + bin]) + (accompanimentOutput[rightBase + bin] * accompanimentOutput[rightBase + bin])
                    mask[(frame * modelBins) + bin] = vocalPower / (vocalPower + accompanimentPower + 1e-10)
                }
            }

            if segment % stride == 0 || segment == segmentCount - 1 {
                onProgress?(Double(segment + 1) / Double(segmentCount))
            }
        }
        return mask
    }

    private func runModel(
        session: ORTSession,
        inputData: [Float],
        inputShape: [NSNumber]
    ) throws -> [Float] {
        let inputBytes = inputData.withUnsafeBufferPointer { buffer -> NSMutableData in
            guard let baseAddress = buffer.baseAddress else {
                return NSMutableData()
            }
            return NSMutableData(bytes: baseAddress, length: buffer.count * MemoryLayout<Float>.size)
        }
        let inputValue = try ORTValue(
            tensorData: inputBytes,
            elementType: ORTTensorElementDataType.float,
            shape: inputShape
        )
        let outputs = try session.run(
            withInputs: ["x": inputValue],
            outputNames: Set(["y"]),
            runOptions: nil
        )
        guard let outputValue = outputs["y"] else {
            throw StemSplitterError.unableToCreateBuffer
        }
        let outputBytes = try outputValue.tensorData()
        let outputData = Data(bytes: outputBytes.bytes, count: outputBytes.length)
        return outputData.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
    }

    private func istft(
        realRows: [[Float]],
        imaginaryRows: [[Float]],
        frameCount: Int,
        window: [Float],
        onProgress: ((Double) -> Void)? = nil
    ) -> [Float] {
        let length = ((frameCount - 1) * hopSize) + fftSize
        var output = [Float](repeating: 0, count: length)
        var normalization = [Float](repeating: 0, count: length)
        var frameReal = [Float](repeating: 0, count: fftSize)
        var frameImaginary = [Float](repeating: 0, count: fftSize)
        let binCount = totalBins
        let stride = max(1, frameCount / 24)

        for frame in 0..<frameCount {
            for index in 0..<fftSize {
                frameReal[index] = 0
                frameImaginary[index] = 0
            }
            for bin in 0..<binCount {
                frameReal[bin] = realRows[frame][bin]
                frameImaginary[bin] = imaginaryRows[frame][bin]
            }
            if binCount > 2 {
                for bin in 1..<(binCount - 1) {
                    frameReal[fftSize - bin] = frameReal[bin]
                    frameImaginary[fftSize - bin] = -frameImaginary[bin]
                }
            }
            ifftIP(real: &frameReal, imaginary: &frameImaginary)

            let start = frame * hopSize
            for index in 0..<fftSize {
                output[start + index] += frameReal[index] * window[index]
                normalization[start + index] += window[index] * window[index]
            }

            if frame % stride == 0 || frame == frameCount - 1 {
                onProgress?(Double(frame + 1) / Double(frameCount))
            }
        }

        for index in 0..<length where normalization[index] > 1e-8 {
            output[index] /= normalization[index]
        }
        return output
    }

    private func hpss(
        realRows: [[Float]],
        imaginaryRows: [[Float]],
        frameCount: Int,
        binCount: Int,
        onProgress: ((Double, String) -> Void)? = nil
    ) -> HpssResult {
        var magnitude = [Float](repeating: 0, count: frameCount * binCount)
        let stride = max(1, frameCount / 18)
        for frame in 0..<frameCount {
            for bin in 0..<binCount {
                let real = realRows[frame][bin]
                let imaginary = imaginaryRows[frame][bin]
                magnitude[(frame * binCount) + bin] = (real * real) + (imaginary * imaginary)
            }
            if frame % stride == 0 || frame == frameCount - 1 {
                onProgress?(0.12 * Double(frame + 1) / Double(frameCount), "Measuring rhythm and tone")
            }
        }

        let harmonic = medFilter(
            magnitude,
            frameCount: frameCount,
            binCount: binCount,
            length: 17,
            axis: "h"
        ) { fraction in
            onProgress?(0.12 + (0.38 * fraction), "Finding sustained parts")
        }

        let percussive = medFilter(
            magnitude,
            frameCount: frameCount,
            binCount: binCount,
            length: 17,
            axis: "v"
        ) { fraction in
            onProgress?(0.50 + (0.38 * fraction), "Finding drum hits")
        }

        var harmonicReal = emptyRows(frameCount: frameCount, binCount: binCount)
        var harmonicImaginary = emptyRows(frameCount: frameCount, binCount: binCount)
        var percussiveReal = emptyRows(frameCount: frameCount, binCount: binCount)
        var percussiveImaginary = emptyRows(frameCount: frameCount, binCount: binCount)

        for frame in 0..<frameCount {
            for bin in 0..<binCount {
                let harmonicPower = harmonic[(frame * binCount) + bin]
                let percussivePower = percussive[(frame * binCount) + bin]
                let denominator = harmonicPower + percussivePower + 1e-8
                harmonicReal[frame][bin] = realRows[frame][bin] * harmonicPower / denominator
                harmonicImaginary[frame][bin] = imaginaryRows[frame][bin] * harmonicPower / denominator
                percussiveReal[frame][bin] = realRows[frame][bin] * percussivePower / denominator
                percussiveImaginary[frame][bin] = imaginaryRows[frame][bin] * percussivePower / denominator
            }
            if frame % stride == 0 || frame == frameCount - 1 {
                onProgress?(0.88 + (0.12 * Double(frame + 1) / Double(frameCount)), "Finishing drum split")
            }
        }

        return HpssResult(
            harmonicReal: harmonicReal,
            harmonicImaginary: harmonicImaginary,
            percussiveReal: percussiveReal,
            percussiveImaginary: percussiveImaginary
        )
    }

    private func medFilter(
        _ spectrogram: [Float],
        frameCount: Int,
        binCount: Int,
        length: Int,
        axis: String,
        onProgress: ((Double) -> Void)? = nil
    ) -> [Float] {
        var output = [Float](repeating: 0, count: frameCount * binCount)
        let half = length / 2
        var windowSamples = [Float](repeating: 0, count: length)

        if axis == "h" {
            let stride = max(1, binCount / 18)
            for bin in 0..<binCount {
                for frame in 0..<frameCount {
                    for index in 0..<length {
                        let sampleFrame = frame - half + index
                        windowSamples[index] = sampleFrame >= 0 && sampleFrame < frameCount ? spectrogram[(sampleFrame * binCount) + bin] : 0
                    }
                    windowSamples.sort()
                    output[(frame * binCount) + bin] = windowSamples[half]
                }
                if bin % stride == 0 || bin == binCount - 1 {
                    onProgress?(Double(bin + 1) / Double(binCount))
                }
            }
        } else {
            let stride = max(1, frameCount / 18)
            for frame in 0..<frameCount {
                for bin in 0..<binCount {
                    for index in 0..<length {
                        let sampleBin = bin - half + index
                        windowSamples[index] = sampleBin >= 0 && sampleBin < binCount ? spectrogram[(frame * binCount) + sampleBin] : 0
                    }
                    windowSamples.sort()
                    output[(frame * binCount) + bin] = windowSamples[half]
                }
                if frame % stride == 0 || frame == frameCount - 1 {
                    onProgress?(Double(frame + 1) / Double(frameCount))
                }
            }
        }

        return output
    }

    private func lowPassSpectrogram(
        realRows: [[Float]],
        imaginaryRows: [[Float]],
        frameCount: Int,
        binCount: Int,
        cutoffHz: Double,
        sampleRate: Double
    ) -> SpectralSplit {
        let cutoff = min(binCount, max(0, Int(round(cutoffHz / (sampleRate / Double(fftSize))))))
        var lowReal = realRows.map { $0 }
        var lowImaginary = imaginaryRows.map { $0 }
        var highReal = realRows.map { $0 }
        var highImaginary = imaginaryRows.map { $0 }

        for frame in 0..<frameCount {
            if cutoff < binCount {
                for bin in cutoff..<binCount {
                    lowReal[frame][bin] = 0
                    lowImaginary[frame][bin] = 0
                }
            }
            if cutoff > 0 {
                for bin in 0..<cutoff {
                    highReal[frame][bin] = 0
                    highImaginary[frame][bin] = 0
                }
            }
        }

        return SpectralSplit(
            lowReal: lowReal,
            lowImaginary: lowImaginary,
            highReal: highReal,
            highImaginary: highImaginary
        )
    }

    private func lowPassSamples(_ input: [Float], cutoff: Double, sampleRate: Double) -> [Float] {
        guard !input.isEmpty, cutoff > 0, sampleRate > 0 else { return input }
        let dt = 1 / sampleRate
        let rc = 1 / (2 * Double.pi * cutoff)
        let alpha = Float(dt / (rc + dt))
        var output = [Float](repeating: 0, count: input.count)
        output[0] = input[0]
        for index in 1..<input.count {
            output[index] = output[index - 1] + alpha * (input[index] - output[index - 1])
        }
        return output
    }

    private func highPassSamples(_ input: [Float], cutoff: Double, sampleRate: Double) -> [Float] {
        guard !input.isEmpty else { return [] }
        let low = lowPassSamples(input, cutoff: cutoff, sampleRate: sampleRate)
        return zip(input, low).map { limitSample($0 - $1) }
    }

    private func bandLimitSamples(_ input: [Float], lowCut: Double, highCut: Double, sampleRate: Double) -> [Float] {
        highPassSamples(
            lowPassSamples(input, cutoff: highCut, sampleRate: sampleRate),
            cutoff: lowCut,
            sampleRate: sampleRate
        )
    }

    private func normalizeSamples(_ input: [Float], ceiling: Float) -> [Float] {
        let peak = input.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > ceiling, peak > 0 else { return input }
        let gain = ceiling / peak
        return input.map { limitSample($0 * gain) }
    }

    private func normalizeSamplesInPlace(_ input: inout [Float], peak: Float, ceiling: Float) {
        guard peak > ceiling, peak > 0 else { return }
        let gain = ceiling / peak
        for index in input.indices {
            input[index] = limitSample(input[index] * gain)
        }
    }

    private func lowPassAlpha(cutoff: Double, sampleRate: Double) -> Float {
        guard cutoff > 0, sampleRate > 0 else { return 1 }
        let dt = 1 / sampleRate
        let rc = 1 / (2 * Double.pi * cutoff)
        return Float(dt / (rc + dt))
    }

    private func makeBuffer(samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw StemSplitterError.unableToCreateBuffer
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for index in samples.indices {
            channel[index] = samples[index]
        }
        return buffer
    }

    private func spectralOverview(_ input: [Float], buckets: Int) -> [Float] {
        guard !input.isEmpty, buckets > 0 else { return [] }
        var values = [Float](repeating: 0, count: buckets)
        for bucket in 0..<buckets {
            let start = bucket * input.count / buckets
            let end = max(start + 1, (bucket + 1) * input.count / buckets)
            var peak: Float = 0
            var rms: Float = 0
            var count: Float = 0
            for index in start..<min(end, input.count) {
                let value = abs(input[index])
                peak = max(peak, value)
                rms += value * value
                count += 1
            }
            rms = sqrt(rms / max(1, count))
            let combined = max(peak, rms)
            values[bucket] = log1p(combined * 14)
        }
        let sorted = values.sorted()
        let referenceIndex = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * 0.92)))
        let reference = max(sorted[referenceIndex], 1e-6)
        return values.map { min(1, max(0, $0 / reference)) }
    }

    private func emptyRows(frameCount: Int, binCount: Int) -> [[Float]] {
        (0..<frameCount).map { _ in [Float](repeating: 0, count: binCount) }
    }

    private func trimOrPad(_ samples: [Float], count: Int) -> [Float] {
        if samples.count == count { return samples }
        if samples.count > count { return Array(samples.prefix(count)) }
        var output = samples
        output.append(contentsOf: repeatElement(0, count: count - samples.count))
        return output
    }

    private func fftIP(real: inout [Float], imaginary: inout [Float]) {
        let count = real.count
        guard count > 1 else { return }

        var j = 0
        for i in 1..<count {
            var bit = count >> 1
            while (j & bit) != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                real.swapAt(i, j)
                imaginary.swapAt(i, j)
            }
        }

        var length = 2
        while length <= count {
            let angle = -2 * Double.pi / Double(length)
            let baseReal = Float(cos(angle))
            let baseImaginary = Float(sin(angle))
            var start = 0
            while start < count {
                var wr: Float = 1
                var wi: Float = 0
                for offset in 0..<(length >> 1) {
                    let even = start + offset
                    let odd = even + (length >> 1)
                    let tReal = (wr * real[odd]) - (wi * imaginary[odd])
                    let tImaginary = (wr * imaginary[odd]) + (wi * real[odd])
                    real[odd] = real[even] - tReal
                    imaginary[odd] = imaginary[even] - tImaginary
                    real[even] += tReal
                    imaginary[even] += tImaginary
                    let nextReal = (wr * baseReal) - (wi * baseImaginary)
                    wi = (wr * baseImaginary) + (wi * baseReal)
                    wr = nextReal
                }
                start += length
            }
            length <<= 1
        }
    }

    private func ifftIP(real: inout [Float], imaginary: inout [Float]) {
        for index in imaginary.indices {
            imaginary[index] = -imaginary[index]
        }
        fftIP(real: &real, imaginary: &imaginary)
        let count = Float(real.count)
        for index in real.indices {
            real[index] /= count
            imaginary[index] = -imaginary[index] / count
        }
    }

    private func limitSample(_ value: Float) -> Float {
        min(1, max(-1, value))
    }
}
