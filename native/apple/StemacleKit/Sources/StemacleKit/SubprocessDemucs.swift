import Foundation

#if os(macOS)

/// Configuration for shelling out to the real Demucs (htdemucs) via
/// `models/separate.py`. Mirrors the Rust `DemucsConfig` in
/// `native/desktop/src/demucs.rs` so both surfaces behave identically.
///
/// Env vars:
///   STEMACLE_DEMUCS_PYTHON  – python interpreter (default: repo venv)
///   STEMACLE_DEMUCS_SCRIPT  – separate.py path   (default: repo models/separate.py)
///   STEMACLE_DEMUCS_MODEL   – model name         (default: htdemucs)
public struct SubprocessDemucsConfig: Sendable {
    public let python: URL
    public let script: URL
    public let model: String

    public var qualityLabel: String { model }

    public static func fromEnv() -> SubprocessDemucsConfig {
        let repo = repoRoot()
        let python = ProcessInfo.processInfo.environment["STEMACLE_DEMUCS_PYTHON"]
            .flatMap { URL(fileURLWithPath: $0) }
            ?? repo.appendingPathComponent("models/.venv-models/bin/python")
        let script = ProcessInfo.processInfo.environment["STEMACLE_DEMUCS_SCRIPT"]
            .flatMap { URL(fileURLWithPath: $0) }
            ?? repo.appendingPathComponent("models/separate.py")
        let model = ProcessInfo.processInfo.environment["STEMACLE_DEMUCS_MODEL"]
            ?? "htdemucs"
        return SubprocessDemucsConfig(python: python, script: script, model: model)
    }

    /// Whether the runtime is present. When false callers use the DSP fallback.
    public func available() -> Bool {
        FileManager.default.fileExists(atPath: python.path) &&
        FileManager.default.fileExists(atPath: script.path)
    }

    /// Shell out to htdemucs and return the four mono stems.
    /// Writes a temporary WAV, calls separate.py, reads back four WAVs.
    public func separate(left: [Float], right: [Float], sampleRate: Int) throws -> [String: [Float]] {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("stemacle-subprocess-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let inWav = tmp.appendingPathComponent("mix.wav")
        try encodeWav(left: left, right: right, sampleRate: sampleRate)
            .write(to: inWav)

        let outDir = tmp.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = python
        proc.arguments = [script.path, inWav.path, outDir.path, "--model", model]
        let pipe = Pipe()
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let errMsg = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "Stemacle", code: 20,
                          userInfo: [NSLocalizedDescriptionKey: "demucs failed: \(errMsg)"])
        }

        var out: [String: [Float]] = [:]
        for stem in ["drums", "vocals", "bass", "melody"] {
            let path = outDir.appendingPathComponent("\(stem).wav")
            guard let data = try? Data(contentsOf: path) else {
                throw NSError(domain: "Stemacle", code: 21,
                              userInfo: [NSLocalizedDescriptionKey: "missing stem \(stem)"])
            }
            // Demucs outputs stereo; decodeWavMono averages channels.
            out[stem] = decodeWavMono(data)
        }
        return out
    }
}

private func repoRoot() -> URL {
    // When running from the Xcode app bundle, walk up from the bundle's Resources
    // to find the repo root (models/ sibling of native/). For tests & CLI, fall
    // back to the working directory or a compile-time path.
    if let bundle = Bundle.main.resourceURL {
        // app bundle: Contents/Resources → …/native/apple/… → repo root
        var url = bundle
        for _ in 0..<6 {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("models/separate.py").path) {
                return url
            }
        }
    }
    // Fallback: assume CWD is somewhere under the repo
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}

#endif
