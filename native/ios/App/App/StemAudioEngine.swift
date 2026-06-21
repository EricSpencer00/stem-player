import AVFoundation
import Foundation

final class StemAudioEngine {
    private let engine = AVAudioEngine()
    private var players: [Stem: AVAudioPlayerNode] = [:]
    private var mixers: [Stem: AVAudioMixerNode] = [:]
    private var buffers: [Stem: AVAudioPCMBuffer] = [:]
    private var scheduledBuffers: [AVAudioPCMBuffer] = []
    private var startDate: Date?
    private var startOffset: TimeInterval = 0

    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false

    init() {
        configureGraph()
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

        for stem in Stem.allCases {
            players[stem]?.play()
        }

        startOffset = min(max(0, offset), duration)
        startDate = Date()
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

    func currentOffset() -> TimeInterval {
        guard isPlaying, let startDate else { return startOffset }
        return min(duration, startOffset + Date().timeIntervalSince(startDate))
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
            let firstStart = min(max(loopStart, startFrame), loopEnd - 1)
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
            for frame in 0..<safeCount {
                destination[channel][frame] = source[channel][safeStart + frame]
            }
        }
        return segment
    }
}
