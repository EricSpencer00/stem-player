#if os(iOS)
import Foundation
import OnnxRuntimeBindings
import StemacleKit

/// On-device **neural** separation using the Spleeter 2-stem ONNX models — the
/// same models the web gold master runs via onnxruntime-web, giving iOS the
/// quality the pure-DSP `CoherenceSeparator` fallback could never match.
///
/// The model only produces the vocal/accompaniment soft-mask; that mask is then
/// handed to the shared Rust DSP core (`Stemacle.separate(…, mask:)` →
/// mask → HPSS → low-pass → ISTFT), so stem routing stays byte-for-byte
/// identical across every surface. This mirrors `separateAudio`'s
/// `if(vSess&&aSess)` branch in `app/index.html`.
///
/// Models are bundled under `Resources/models/` (fetched by
/// `scripts/fetch-ios-models.sh`). If they are missing, `init?` fails and the
/// caller falls back to the DSP separator.
final class SpleeterSeparator {
    /// Spleeter's fixed time-frame count per inference segment (web `SEG_FRAMES`).
    private static let segFrames = 512

    private let env: ORTEnv
    private let vocals: ORTSession
    private let accompaniment: ORTSession

    /// Bundled model URLs, or nil if either is missing.
    static func modelURLs() -> (vocals: URL, accompaniment: URL)? {
        func find(_ name: String) -> URL? {
            Bundle.main.url(forResource: name, withExtension: "onnx", subdirectory: "models")
                ?? Bundle.main.url(forResource: name, withExtension: "onnx")
        }
        guard let v = find("vocals"), let a = find("accompaniment") else { return nil }
        return (v, a)
    }

    static var isAvailable: Bool { modelURLs() != nil }

    init?() {
        guard let urls = Self.modelURLs() else { return nil }
        do {
            let env = try ORTEnv(loggingLevel: .warning)
            let opts = try ORTSessionOptions()
            self.env = env
            self.vocals = try ORTSession(env: env, modelPath: urls.vocals.path, sessionOptions: opts)
            self.accompaniment = try ORTSession(env: env, modelPath: urls.accompaniment.path, sessionOptions: opts)
        } catch {
            return nil
        }
    }

    /// Separate one stereo window into four stems using the neural mask. Returns
    /// nil on any failure so the caller can fall back to the DSP separator.
    func separate(left: [Float], right: [Float], sampleRate: UInt32) -> StemSplit? {
        guard let mags = Stemacle.magnitudes(left: left, right: right) else { return nil }
        let frames = mags.frames
        let bins = Stemacle.modelBins
        let seg = Self.segFrames
        var mask = [Float](repeating: 0, count: frames * bins)
        // Segment input tensor: [2, 1, seg, bins], channel-major (L block, R block).
        var segData = [Float](repeating: 0, count: 2 * seg * bins)
        let shape: [NSNumber] = [2, 1, NSNumber(value: seg), NSNumber(value: bins)]
        let nSeg = (frames + seg - 1) / seg

        do {
            for s in 0..<nSeg {
                for i in segData.indices { segData[i] = 0 }
                for fr in 0..<seg {
                    let f = s * seg + fr
                    if f >= frames { break }
                    let baseL = fr * bins
                    let baseR = (seg + fr) * bins
                    let src = f * bins
                    for b in 0..<bins {
                        segData[baseL + b] = mags.magL[src + b]
                        segData[baseR + b] = mags.magR[src + b]
                    }
                }
                let ve = try run(vocals, segData, shape)
                let ae = try run(accompaniment, segData, shape)
                for fr in 0..<seg {
                    let f = s * seg + fr
                    if f >= frames { break }
                    let bL = fr * bins
                    let bR = (seg + fr) * bins
                    let dst = f * bins
                    for b in 0..<bins {
                        let vp = ve[bL + b] * ve[bL + b] + ve[bR + b] * ve[bR + b]
                        let ap = ae[bL + b] * ae[bL + b] + ae[bR + b] * ae[bR + b]
                        mask[dst + b] = (vp / (vp + ap + 1e-10)) * Stemacle.vocalMaskWeight(bin: b)
                    }
                }
            }
        } catch {
            return nil
        }
        return Stemacle.separate(left: left, right: right, sampleRate: sampleRate, mask: mask)
    }

    /// Run a session on the `[2,1,seg,bins]` magnitude tensor, returning `y` flat.
    private func run(_ session: ORTSession, _ data: [Float], _ shape: [NSNumber]) throws -> [Float] {
        let tensor = NSMutableData(bytes: data, length: data.count * MemoryLayout<Float>.stride)
        let input = try ORTValue(tensorData: tensor, elementType: .float, shape: shape)
        let outputs = try session.run(withInputs: ["x": input],
                                      outputNames: ["y"],
                                      runOptions: nil)
        guard let y = outputs["y"] else {
            throw NSError(domain: "Spleeter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "model produced no output"])
        }
        let raw = try y.tensorData() as Data
        return raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
#endif
