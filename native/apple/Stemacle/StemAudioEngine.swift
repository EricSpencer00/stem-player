import AVFoundation
import Foundation

/// Four-stem playback engine built on `AVAudioEngine`. One `AVAudioPlayerNode`
/// per stem feeds a shared mixer, giving per-stem volume, mute, and headphones
/// (solo) isolation while staying sample-aligned for the loop contract.
final class StemAudioEngine {
    static let sampleRate: Double = 44100

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    private var players: [String: AVAudioPlayerNode] = [:]
    private var buffers: [String: AVAudioPCMBuffer] = [:]

    private(set) var isPlaying = false
    private(set) var durationSeconds: Double = 0
    private var startHostTime: AVAudioFramePosition = 0

    let stems = ["drums", "vocals", "bass", "melody"]

    init() {
        for stem in stems {
            let node = AVAudioPlayerNode()
            players[stem] = node
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
    }

    /// Load mono PCM per stem (already at 44.1 kHz from the core) into buffers.
    func load(stems split: [String: [Float]]) {
        var maxFrames = 0
        for stem in stems {
            guard let samples = split[stem], !samples.isEmpty else { continue }
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
            buf.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
            }
            buffers[stem] = buf
            maxFrames = max(maxFrames, samples.count)
        }
        durationSeconds = Double(maxFrames) / Self.sampleRate
    }

    func prepare() throws {
        if !engine.isRunning {
            try engine.start()
        }
    }

    /// Start all stems from `offset` seconds, sample-synchronized.
    func play(from offset: Double = 0) throws {
        try prepare()
        let startFrame = Int(max(0, offset) * Self.sampleRate)
        for stem in stems {
            guard let node = players[stem], let buf = buffers[stem] else { continue }
            node.stop()
            guard startFrame < Int(buf.frameLength) else { continue }
            let segment = startFrame == 0 ? buf : Self.slice(buf, from: startFrame)
            node.scheduleBuffer(segment, at: nil)
            node.play()
        }
        isPlaying = true
    }

    func pause() {
        for node in players.values { node.pause() }
        isPlaying = false
    }

    func stop() {
        for node in players.values { node.stop() }
        isPlaying = false
    }

    /// Copy `[from, end)` of a mono buffer into a fresh buffer for offset playback.
    private static func slice(_ buf: AVAudioPCMBuffer, from: Int) -> AVAudioPCMBuffer {
        let count = Int(buf.frameLength) - from
        let out = AVAudioPCMBuffer(pcmFormat: buf.format, frameCapacity: AVAudioFrameCount(count))!
        out.frameLength = AVAudioFrameCount(count)
        out.floatChannelData![0].update(from: buf.floatChannelData![0] + from, count: count)
        return out
    }

    // MARK: Per-stem mixing

    func setVolume(_ stem: String, _ value: Float) {
        players[stem]?.volume = max(0, min(1, value))
    }

    /// Apply mute / solo state across all stems. When any stem is soloed, only
    /// soloed stems are audible; otherwise muted stems are silenced. Volumes are
    /// preserved (the gold master's "persistent global mute" invariant).
    func applyMixing(volumes: [String: Float], muted: Set<String>, soloed: Set<String>) {
        let anySolo = !soloed.isEmpty
        for stem in stems {
            let base = volumes[stem] ?? 0.8
            let audible = anySolo ? soloed.contains(stem) : !muted.contains(stem)
            players[stem]?.volume = audible ? max(0, min(1, base)) : 0
        }
    }
}
