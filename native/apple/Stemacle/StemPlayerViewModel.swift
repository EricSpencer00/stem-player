import AVFoundation
import Combine
import Foundation
import StemacleKit

/// Drives the Stemacle player UI: decodes a file, runs separation on the shared
/// Rust core, and exposes transport + per-stem state to SwiftUI.
@MainActor
final class StemPlayerViewModel: ObservableObject {
    let stems = ["drums", "vocals", "bass", "melody"]

    @Published var status: String = "Drop or choose a track"
    @Published var isProcessing = false
    @Published var isReady = false
    @Published var isPlaying = false
    @Published var bpm: Float = 120
    @Published var duration: Double = 0

    @Published var volumes: [String: Float] = [:]
    @Published var muted: Set<String> = []
    @Published var soloed: Set<String> = []
    /// Selected loop length per stem in bars (nil = no loop). Matches LOOP_BARS.
    @Published var loopBars: [String: Float] = [:]

    private let engine = StemAudioEngine()
    private var split: StemSplit?

    init() {
        for stem in stems { volumes[stem] = 0.8 }
    }

    /// Decode `url` to 44.1 kHz stereo, separate on the Rust core, load the engine.
    func loadFile(_ url: URL) async {
        isProcessing = true
        isReady = false
        status = "Decoding…"
        defer { isProcessing = false }

        do {
            let (left, right) = try decodeStereo44k(url)
            status = "Separating…"
            // Hop heavy work off the main actor.
            let result: StemSplit? = await Task.detached(priority: .userInitiated) {
                Stemacle.separate(left: left, right: right, sampleRate: 44100)
            }.value
            guard let result else {
                status = "Could not separate this file"
                return
            }
            split = result
            bpm = result.bpm
            var dict: [String: [Float]] = [:]
            for (name, samples) in result.ordered { dict[name] = samples }
            engine.load(stems: dict)
            duration = engine.durationSeconds
            isReady = true
            status = "Ready · \(Int(result.bpm)) BPM"
        } catch {
            status = "Load failed: \(error.localizedDescription)"
        }
    }

    // MARK: Transport

    func togglePlay() {
        guard isReady else { return }
        do {
            if isPlaying {
                engine.pause()
                isPlaying = false
            } else {
                try engine.play(from: 0)
                applyMixing()
                isPlaying = true
            }
        } catch {
            status = "Playback error: \(error.localizedDescription)"
        }
    }

    func stop() {
        engine.stop()
        isPlaying = false
    }

    // MARK: Per-stem controls

    func setVolume(_ stem: String, _ value: Float) {
        volumes[stem] = value
        applyMixing()
    }

    func toggleMute(_ stem: String) {
        if muted.contains(stem) { muted.remove(stem) } else { muted.insert(stem) }
        applyMixing()
    }

    func toggleSolo(_ stem: String) {
        if soloed.contains(stem) { soloed.remove(stem) } else { soloed.insert(stem) }
        applyMixing()
    }

    /// Set a per-stem loop length (bars), snapped against the detected grid.
    func setLoop(_ stem: String, bars: Float?) {
        loopBars[stem] = bars
    }

    private func applyMixing() {
        engine.applyMixing(volumes: volumes, muted: muted, soloed: soloed)
    }

    // MARK: Decoding

    /// Decode any AVFoundation-readable file to two 44.1 kHz mono Float arrays.
    private func decodeStereo44k(_ url: URL) throws -> (left: [Float], right: [Float]) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: StemAudioEngine.sampleRate,
            channels: 2,
            interleaved: false
        )!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
            throw NSError(domain: "Stemacle", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format"])
        }

        let ratio = target.sampleRate / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(file.length) * ratio) + 4096
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw NSError(domain: "Stemacle", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Out of memory decoding"])
        }

        var finished = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if finished {
                outStatus.pointee = .endOfStream
                return nil
            }
            let frames: AVAudioFrameCount = 16384
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)
            else {
                outStatus.pointee = .endOfStream
                return nil
            }
            do {
                try file.read(into: buf)
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
            if buf.frameLength == 0 {
                finished = true
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            return buf
        }

        var error: NSError?
        converter.convert(to: out, error: &error, withInputFrom: inputBlock)
        if let error { throw error }

        let n = Int(out.frameLength)
        let chans = out.floatChannelData!
        let left = Array(UnsafeBufferPointer(start: chans[0], count: n))
        let right = target.channelCount > 1
            ? Array(UnsafeBufferPointer(start: chans[1], count: n))
            : left
        return (left, right)
    }
}
