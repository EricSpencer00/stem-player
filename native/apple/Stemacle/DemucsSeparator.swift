#if os(iOS)
import Foundation
import OnnxRuntimeBindings
import StemacleKit

/// On-device **HT-Demucs** separation — a hybrid transformer that outputs the
/// four stem *waveforms directly* (no mask, no HPSS heuristic), the current
/// state of the art and a step beyond the Spleeter mask path. It's a faithful
/// port of the reference `infer.py` for `StemSplitio/htdemucs-onnx`:
///
///   input  "mix"   [1, 2, 343980]  (7.8 s stereo @ 44.1 kHz, float32)
///   output "stems" [1, 4, 2, 343980]  (drums, bass, other, vocals)
///
/// The track window is processed in 7.8 s segments with 25% triangular
/// overlap-add. Demucs "other" maps to our "melody" stem. Stems are downmixed to
/// mono to match the engine. Runs on the CoreML execution provider when
/// available (essential for acceptable speed), falling back to CPU.
///
/// The model (`htdemucs_fp16weights.onnx`, ~166 MB) is optional: if it isn't
/// present, `init?` fails and the caller falls back to Spleeter / DSP.
final class DemucsSeparator {
    private static let sampleRate: Double = 44100
    private static let nSamples = 343980            // 7.8 s
    private static let overlap = nSamples / 4       // 25%
    private static let stride = nSamples - overlap
    /// Demucs source order (drums, bass, other, vocals) → our stem names.
    private static let sourceToStem = ["drums", "bass", "melody", "vocals"]

    private let env: ORTEnv
    private let session: ORTSession

    static func modelURL() -> URL? {
        func find(_ name: String) -> URL? {
            Bundle.main.url(forResource: name, withExtension: "onnx", subdirectory: "models")
                ?? Bundle.main.url(forResource: name, withExtension: "onnx")
        }
        return find("htdemucs_fp16weights") ?? find("htdemucs")
    }

    static var isAvailable: Bool { modelURL() != nil }

    init?() {
        guard let url = Self.modelURL() else { return nil }
        do {
            let env = try ORTEnv(loggingLevel: .warning)
            let opts = try ORTSessionOptions()
            try opts.setGraphOptimizationLevel(.all)
            // CoreML (ANE/GPU) is essential for acceptable speed; fall back to CPU.
            try? opts.appendCoreMLExecutionProvider(with: ORTCoreMLExecutionProviderOptions())
            self.env = env
            self.session = try ORTSession(env: env, modelPath: url.path, sessionOptions: opts)
        } catch {
            return nil
        }
    }

    /// Separate a stereo window into four mono stems (drums/bass/melody/vocals),
    /// full window length, via 7.8 s overlap-add. Returns nil on failure.
    func separate(left: [Float], right: [Float]) -> [String: [Float]]? {
        let total = min(left.count, right.count)
        guard total > 0 else { return nil }
        let n = Self.nSamples, ov = Self.overlap, stride = Self.stride
        let window = Self.triangleWindow(n: n, overlap: ov)
        let shape: [NSNumber] = [1, 2, NSNumber(value: n)]

        var acc = [[Float]](repeating: [Float](repeating: 0, count: total), count: 4)
        var weight = [Float](repeating: 0, count: total)
        var seg = [Float](repeating: 0, count: 2 * n)  // planar (2, n)

        var start = 0
        do {
            while start < total {
                let end = min(start + n, total)
                let clen = end - start
                for i in seg.indices { seg[i] = 0 }
                for k in 0..<clen {
                    seg[k] = left[start + k]        // channel 0 block
                    seg[n + k] = right[start + k]   // channel 1 block
                }
                let stems = try run(seg, shape)     // flat [4][2][n]
                for src in 0..<4 {
                    let base = src * 2 * n
                    for t in 0..<clen {
                        let l = stems[base + t]
                        let r = stems[base + n + t]
                        acc[src][start + t] += 0.5 * (l + r) * window[t]
                    }
                }
                for t in 0..<clen { weight[start + t] += window[t] }
                if end == total { break }
                start += stride
            }
        } catch {
            return nil
        }

        var out: [String: [Float]] = [:]
        for src in 0..<4 {
            var s = acc[src]
            for t in 0..<total { s[t] /= max(weight[t], 1e-8) }
            out[Self.sourceToStem[src]] = s
        }
        return out
    }

    private func run(_ data: [Float], _ shape: [NSNumber]) throws -> [Float] {
        let tensor = NSMutableData(bytes: data, length: data.count * MemoryLayout<Float>.stride)
        let input = try ORTValue(tensorData: tensor, elementType: .float, shape: shape)
        let outputs = try session.run(withInputs: ["mix": input],
                                      outputNames: ["stems"],
                                      runOptions: nil)
        guard let y = outputs["stems"] else {
            throw NSError(domain: "Demucs", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no stems output"])
        }
        let raw = try y.tensorData() as Data
        return raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// Reference `_make_window`: linear fade-in over the first `overlap` samples,
    /// mirror fade-out over the last `overlap`; flat 1.0 in between.
    private static func triangleWindow(n: Int, overlap: Int) -> [Float] {
        var w = [Float](repeating: 1, count: n)
        guard overlap > 1 else { return w }
        for i in 0..<overlap {
            let f = Float(i) / Float(overlap - 1)  // linspace(0, 1, overlap)
            w[i] = f
            w[n - 1 - i] = f
        }
        return w
    }
}
#endif
