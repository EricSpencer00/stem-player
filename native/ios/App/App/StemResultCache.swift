import AVFoundation
import Foundation

/// Persists separated stems per source track so reopening a library item (or a
/// bundled sample) does not re-run the expensive on-device separation. Stems are
/// written as compact AAC `.m4a` files next to a small JSON sidecar that records
/// tempo, duration, sample rate, and the spectrogram overview.
///
/// Everything lives under Application Support — local-first, no uploads. Caching
/// is strictly best-effort: any read inconsistency returns `nil` so the caller
/// falls back to a fresh split, and any write failure is swallowed.
struct StemResultCache: Sendable {
    private struct Meta: Codable {
        var title: String
        var duration: TimeInterval
        var sampleRate: Double
        var bpm: Double
        var confidence: Double
        var beatOffset: Double
        var measureOffset: Double
        var overview: [String: [Float]]
    }

    /// Returns a reconstructed split result if a complete cache exists for `key`,
    /// otherwise `nil`. A missing stem, metadata, or unreadable buffer all count
    /// as a miss so the caller re-separates rather than playing partial audio.
    func cachedResult(forKey key: String, sourceURL: URL) -> StemSplitResult? {
        let dir = directory(forKey: key)
        let metaURL = dir.appendingPathComponent("meta.json")
        guard
            let data = try? Data(contentsOf: metaURL),
            let meta = try? JSONDecoder().decode(Meta.self, from: data)
        else { return nil }

        var buffers: [Stem: AVAudioPCMBuffer] = [:]
        for stem in Stem.allCases {
            let url = dir.appendingPathComponent("\(stem.rawValue).m4a")
            guard let buffer = readBuffer(at: url), buffer.frameLength > 0 else { return nil }
            buffers[stem] = buffer
        }

        var overview: [Stem: [Float]] = [:]
        for stem in Stem.allCases {
            overview[stem] = meta.overview[stem.rawValue] ?? []
        }

        let tempo = TempoEstimate(
            bpm: meta.bpm,
            confidence: meta.confidence,
            beatOffset: meta.beatOffset,
            measureOffset: meta.measureOffset
        )

        return StemSplitResult(
            sourceURL: sourceURL,
            title: meta.title,
            duration: meta.duration,
            sampleRate: meta.sampleRate,
            tempo: tempo,
            buffers: buffers,
            overview: overview
        )
    }

    /// Writes every stem buffer plus a metadata sidecar for `key`. Best-effort.
    func store(_ result: StemSplitResult, forKey key: String) {
        let dir = directory(forKey: key)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for stem in Stem.allCases {
                guard let buffer = result.buffers[stem] else { continue }
                try writeBuffer(buffer, to: dir.appendingPathComponent("\(stem.rawValue).m4a"))
            }

            var overview: [String: [Float]] = [:]
            for stem in Stem.allCases {
                overview[stem.rawValue] = result.overview[stem] ?? []
            }
            let meta = Meta(
                title: result.title,
                duration: result.duration,
                sampleRate: result.sampleRate,
                bpm: result.tempo.bpm,
                confidence: result.tempo.confidence,
                beatOffset: result.tempo.beatOffset,
                measureOffset: result.tempo.measureOffset,
                overview: overview
            )
            let data = try JSONEncoder().encode(meta)
            try data.write(to: dir.appendingPathComponent("meta.json"), options: [.atomic])
        } catch {
            // Caching is best-effort; the next open simply re-runs separation.
            try? FileManager.default.removeItem(at: dir)
        }
    }

    private func writeBuffer(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: buffer.format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    private func readBuffer(at url: URL) -> AVAudioPCMBuffer? {
        guard
            FileManager.default.fileExists(atPath: url.path),
            let file = try? AVAudioFile(forReading: url)
        else { return nil }

        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        do {
            try file.read(into: buffer)
            return buffer
        } catch {
            return nil
        }
    }

    private func directory(forKey key: String) -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root
            .appendingPathComponent("Stemacle/Stem Cache", isDirectory: true)
            .appendingPathComponent(sanitize(key), isDirectory: true)
    }

    private func sanitize(_ key: String) -> String {
        let allowed = CharacterSet.alphanumerics
        var result = ""
        for scalar in key.unicodeScalars {
            result.append(allowed.contains(scalar) ? Character(scalar) : "-")
        }
        return result.isEmpty ? "track" : result
    }
}
