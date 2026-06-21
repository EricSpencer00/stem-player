import AVFoundation
import Darwin
import Foundation

final class StemAudioEngine {
    private let synchronizedStartDelay: TimeInterval = 0.018
    private let engine = AVAudioEngine()
    private var players: [Stem: AVAudioPlayerNode] = [:]
    private var mixers: [Stem: AVAudioMixerNode] = [:]
    private var buffers: [Stem: AVAudioPCMBuffer] = [:]
    private var scheduledBuffers: [AVAudioPCMBuffer] = []
    private var startDate: Date?
    private var startOffset: TimeInterval = 0

    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false

    /// Called on the main queue when the system interrupts playback (phone call,
    /// Siri, another app taking the audio route). The view model uses this to drop
    /// its `isPlaying` state so the transport UI stays truthful.
    var onInterruption: (() -> Void)?
    private var interruptionObserver: NSObjectProtocol?

    init() {
        configureAudioSession()
        configureGraph()
        registerInterruptionObserver()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    func load(_ result: StemSplitResult) throws {
        stop()
        buffers = result.buffers
        duration = result.duration
        configurePlayerFormats()
        try startEngineIfNeeded()
    }

    func play(
        from offset: TimeInterval,
        controls: [Stem: StemPlaybackControl],
        loops: [Stem: StemLoop],
        globalMute: Bool,
        headphonesStem: Stem?,
        loopMonitorMode: LoopMonitorMode
    ) throws {
        guard !buffers.isEmpty else { return }
        stopPlayers()
        try startEngineIfNeeded()
        updateMix(controls: controls, globalMute: globalMute, headphonesStem: headphonesStem)

        for stem in Stem.allCases {
            guard let player = players[stem], let buffer = buffers[stem] else { continue }
            schedule(buffer: buffer, on: player, from: offset, loop: loops[stem] ?? .inactive)
        }

        let startTime = synchronizedStartTime(after: synchronizedStartDelay)
        for stem in Stem.allCases {
            players[stem]?.play(at: startTime)
        }

        startOffset = min(max(0, offset), duration)
        startDate = Date().addingTimeInterval(synchronizedStartDelay)
        isPlaying = true
    }

    func pause() -> TimeInterval {
        let offset = currentOffset()
        stopPlayers()
        startOffset = offset
        startDate = nil
        isPlaying = false
        return offset
    }

    func stop() {
        stopPlayers()
        startOffset = 0
        startDate = nil
        isPlaying = false
    }

    func seek(
        to offset: TimeInterval,
        controls: [Stem: StemPlaybackControl],
        loops: [Stem: StemLoop],
        globalMute: Bool,
        headphonesStem: Stem?,
        loopMonitorMode: LoopMonitorMode
    ) throws {
        let clamped = min(max(0, offset), duration)
        if isPlaying {
            try play(
                from: clamped,
                controls: controls,
                loops: loops,
                globalMute: globalMute,
                headphonesStem: headphonesStem,
                loopMonitorMode: loopMonitorMode
            )
        } else {
            startOffset = clamped
        }
    }

    func reschedule(
        stems: Set<Stem>,
        controls: [Stem: StemPlaybackControl],
        loops: [Stem: StemLoop],
        globalMute: Bool,
        headphonesStem: Stem?,
        loopMonitorMode: LoopMonitorMode
    ) throws {
        guard !buffers.isEmpty else { return }
        let activeStems = Set(stems.filter { players[$0] != nil && buffers[$0] != nil })
        guard !activeStems.isEmpty else { return }

        let offset = currentOffset()
        updateMix(controls: controls, globalMute: globalMute, headphonesStem: headphonesStem)
        startOffset = min(max(0, offset), duration)

        guard isPlaying else {
            return
        }

        try startEngineIfNeeded()
        let reschedulingEveryStem = Stem.allCases.allSatisfy { activeStems.contains($0) }
        let startDelay = synchronizedStartDelay
        let startTime = synchronizedStartTime(after: startDelay)
        let scheduleOffset = reschedulingEveryStem ? offset : min(duration, offset + startDelay)

        for stem in Stem.allCases where activeStems.contains(stem) {
            guard let player = players[stem], let buffer = buffers[stem] else { continue }
            player.stop()
            player.reset()
            schedule(buffer: buffer, on: player, from: scheduleOffset, loop: loops[stem] ?? .inactive)
        }

        for stem in Stem.allCases where stems.contains(stem) {
            players[stem]?.play(at: startTime)
        }

        startDate = reschedulingEveryStem ? Date().addingTimeInterval(startDelay) : Date()
        isPlaying = true
    }

    func currentOffset() -> TimeInterval {
        guard isPlaying, let startDate else { return startOffset }
        return min(duration, max(0, startOffset + Date().timeIntervalSince(startDate)))
    }

    func updateMix(
        controls: [Stem: StemPlaybackControl],
        globalMute: Bool,
        headphonesStem: Stem?
    ) {
        for stem in Stem.allCases {
            let control = controls[stem] ?? StemPlaybackControl()
            var volume = control.volume
            if globalMute || control.isMuted {
                volume = 0
            }
            if let headphonesStem, headphonesStem != stem {
                volume = 0
            }
            mixers[stem]?.outputVolume = volume
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // `.playback` makes Stemacle audible even with the ring/silent switch on
            // and keeps sound alive while the screen locks (paired with the `audio`
            // UIBackgroundMode in Info.plist).
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch {
            // A failed session config should not crash playback setup; the engine
            // still attempts to start and surfaces errors through normal play paths.
        }
    }

    private func registerInterruptionObserver() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        if type == .began {
            stopPlayers()
            isPlaying = false
            onInterruption?()
        }
    }

    private func configureGraph() {
        for stem in Stem.allCases {
            let player = AVAudioPlayerNode()
            let mixer = AVAudioMixerNode()
            players[stem] = player
            mixers[stem] = mixer
            engine.attach(player)
            engine.attach(mixer)
            engine.connect(mixer, to: engine.mainMixerNode, format: nil)
            mixer.outputVolume = 0.8
        }
    }

    private func configurePlayerFormats() {
        if engine.isRunning {
            engine.stop()
        }

        for stem in Stem.allCases {
            guard let player = players[stem],
                  let mixer = mixers[stem],
                  let buffer = buffers[stem] else {
                continue
            }
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: mixer, format: buffer.format)
        }
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            try? AVAudioSession.sharedInstance().setActive(true, options: [])
            try engine.start()
        }
    }

    private func stopPlayers() {
        for player in players.values {
            player.stop()
            player.reset()
        }
        scheduledBuffers.removeAll()
    }

    private func schedule(buffer: AVAudioPCMBuffer, on player: AVAudioPlayerNode, from offset: TimeInterval, loop: StemLoop) {
        let sampleRate = buffer.format.sampleRate
        let frameLength = AVAudioFramePosition(buffer.frameLength)
        guard frameLength > 0 else { return }

        let startFrame = min(max(0, AVAudioFramePosition(offset * sampleRate)), frameLength - 1)

        if loop.isActive {
            let loopStart = min(max(0, AVAudioFramePosition(loop.start * sampleRate)), frameLength - 1)
            let loopEnd = min(max(loopStart + 1, AVAudioFramePosition(loop.end * sampleRate)), frameLength)
            let firstStart = wrappedLoopStartFrame(startFrame: startFrame, loopStart: loopStart, loopEnd: loopEnd)
            let firstCount = AVAudioFrameCount(max(1, loopEnd - firstStart))
            let loopCount = AVAudioFrameCount(max(1, loopEnd - loopStart))
            let looping = AVAudioPlayerNodeBufferOptions.loops
            if let firstBuffer = segmentBuffer(from: buffer, startFrame: firstStart, frameCount: firstCount) {
                queue(firstBuffer, on: player)
            }
            if let loopBuffer = segmentBuffer(from: buffer, startFrame: loopStart, frameCount: loopCount) {
                queue(loopBuffer, on: player, options: looping)
            }
            return
        }

        let remaining = AVAudioFrameCount(max(1, frameLength - startFrame))
        if let tailBuffer = segmentBuffer(from: buffer, startFrame: startFrame, frameCount: remaining) {
            queue(tailBuffer, on: player)
        }
    }

    private func wrappedLoopStartFrame(
        startFrame: AVAudioFramePosition,
        loopStart: AVAudioFramePosition,
        loopEnd: AVAudioFramePosition
    ) -> AVAudioFramePosition {
        let loopLength = max(1, loopEnd - loopStart)
        guard startFrame >= loopStart else {
            return loopStart
        }
        if startFrame >= loopEnd {
            return loopStart + ((startFrame - loopStart) % loopLength)
        }
        return startFrame
    }

    private func queue(
        _ buffer: AVAudioPCMBuffer,
        on player: AVAudioPlayerNode,
        options: AVAudioPlayerNodeBufferOptions = []
    ) {
        scheduledBuffers.append(buffer)
        player.scheduleBuffer(buffer, at: nil, options: options)
    }

    private func segmentBuffer(
        from buffer: AVAudioPCMBuffer,
        startFrame: AVAudioFramePosition,
        frameCount: AVAudioFrameCount
    ) -> AVAudioPCMBuffer? {
        let safeStart = max(0, Int(startFrame))
        let safeCount = max(1, min(Int(frameCount), Int(buffer.frameLength) - safeStart))
        guard safeCount > 0,
              let segment = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(safeCount)),
              let source = buffer.floatChannelData,
              let destination = segment.floatChannelData else {
            return nil
        }

        segment.frameLength = AVAudioFrameCount(safeCount)
        let channels = Int(buffer.format.channelCount)
        for channel in 0..<channels {
            destination[channel].update(from: source[channel].advanced(by: safeStart), count: safeCount)
        }
        return segment
    }

    private func synchronizedStartTime(after delay: TimeInterval) -> AVAudioTime {
        AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: delay))
    }
}
