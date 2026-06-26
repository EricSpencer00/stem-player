import Foundation

// MARK: - URLSession abstraction (enables mock injection in tests)

public protocol URLSessionProtocol: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
    func upload(for request: URLRequest, from body: Data) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - StemServerClient

/// Client for the Stemacle separation queue server (`server/app.py`), which runs
/// the real htdemucs. Gives iOS full-quality stems without on-device inference:
/// upload audio → poll the job → download four WAV stems.
///
/// The base URL is read from UserDefaults key `stemacle.serverURL` (settable in
/// Settings). When unset the app falls back to the on-device DSP path.
public struct StemServerClient: Sendable {
    public let baseURL: URL
    public let model: String
    private let session: any URLSessionProtocol

    /// Quality label shown in the Library card (matches the model name).
    public var qualityLabel: String { model }

    public init(baseURL: URL, model: String = "htdemucs",
                session: (any URLSessionProtocol)? = nil) {
        self.baseURL = baseURL
        self.model = model
        self.session = session ?? URLSession.shared
    }

    /// Return a configured client from UserDefaults, or nil when not set.
    public static func configured() -> StemServerClient? {
        guard let s = UserDefaults.standard.string(forKey: "stemacle.serverURL"),
              !s.isEmpty, let url = URL(string: s)
        else { return nil }
        let model = UserDefaults.standard.string(forKey: "stemacle.serverModel") ?? "htdemucs"
        return StemServerClient(baseURL: url, model: model)
    }

    // MARK: - Job lifecycle

    public struct JobStatus: Decodable, Sendable {
        public let status: String
        public let stems: [String]
        public let error: String?
        public let progress: Int?
    }

    /// Upload stereo PCM as a WAV and return the new job id.
    public func submit(left: [Float], right: [Float], sampleRate: Int) async throws -> String {
        let wav = encodeWav(left: left, right: right, sampleRate: sampleRate)
        var req = URLRequest(url: baseURL.appendingPathComponent("separate"))
        req.httpMethod = "POST"
        let boundary = "stemacle-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"mix.wav\"\r\n"
            .data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        let (data, _) = try await session.upload(for: req, from: body)
        struct Submit: Decodable { let job_id: String }
        return try JSONDecoder().decode(Submit.self, from: data).job_id
    }

    public func status(_ jobID: String) async throws -> JobStatus {
        let url = baseURL.appendingPathComponent("jobs").appendingPathComponent(jobID)
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(JobStatus.self, from: data)
    }

    /// Poll until done, then download and decode all four stems to mono Float.
    /// `onProgress` receives 0…1 while the job runs.
    public func awaitStems(
        _ jobID: String,
        pollSeconds: UInt64 = 1,
        onProgress: @MainActor @escaping (Double) -> Void = { _ in }
    ) async throws -> [String: [Float]] {
        while true {
            let s = try await status(jobID)
            await onProgress(Double(s.progress ?? 0) / 100.0)
            if s.status == "done" { break }
            if s.status == "error" {
                throw NSError(domain: "Stemacle", code: 10,
                              userInfo: [NSLocalizedDescriptionKey: s.error ?? "server error"])
            }
            if pollSeconds > 0 {
                try await Task.sleep(nanoseconds: pollSeconds * 1_000_000_000)
            }
        }
        var out: [String: [Float]] = [:]
        for stem in ["drums", "vocals", "bass", "melody"] {
            let url = baseURL
                .appendingPathComponent("jobs")
                .appendingPathComponent(jobID)
                .appendingPathComponent(stem)
            let (data, _) = try await session.data(from: url)
            out[stem] = decodeWavMono(data)
        }
        return out
    }
}

// MARK: - WAV codec (16-bit PCM, public so tests can call them directly)

public func encodeWav(left: [Float], right: [Float], sampleRate: Int) -> Data {
    let n = min(left.count, right.count)
    let bytesPerSample = 2, channels = 2
    let dataLen = n * channels * bytesPerSample
    var d = Data(capacity: 44 + dataLen)
    func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
    d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + dataLen))
    d.append("WAVE".data(using: .ascii)!)
    d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(UInt16(channels))
    u32(UInt32(sampleRate)); u32(UInt32(sampleRate * channels * bytesPerSample))
    u16(UInt16(channels * bytesPerSample)); u16(16)
    d.append("data".data(using: .ascii)!); u32(UInt32(dataLen))
    for i in 0..<n {
        for ch in [left, right] {
            let s = max(-1, min(1, ch[i]))
            var v = Int16(s * 32767).littleEndian
            withUnsafeBytes(of: &v) { d.append(contentsOf: $0) }
        }
    }
    return d
}

public func decodeWavMono(_ data: Data) -> [Float] {
    let b = [UInt8](data)
    guard b.count > 44, b[0] == 0x52 else { return [] } // 'R'
    var pos = 12, channels = 1, bits = 16
    var dataStart = 44, dataLen = b.count - 44
    func rd32(_ o: Int) -> Int { Int(b[o]) | Int(b[o+1])<<8 | Int(b[o+2])<<16 | Int(b[o+3])<<24 }
    func rd16(_ o: Int) -> Int { Int(b[o]) | Int(b[o+1])<<8 }
    while pos + 8 <= b.count {
        let id = String(bytes: b[pos..<pos+4], encoding: .ascii) ?? ""
        let size = rd32(pos + 4)
        if id == "fmt " { channels = rd16(pos + 10); bits = rd16(pos + 22) }
        if id == "data" { dataStart = pos + 8; dataLen = size; break }
        pos += 8 + size + (size & 1)
    }
    let bytesPerSample = bits / 8
    let frame = bytesPerSample * channels
    guard frame > 0 else { return [] }
    let frames = min(dataLen, b.count - dataStart) / frame
    var out = [Float](repeating: 0, count: frames)
    for f in 0..<frames {
        let frameStart = dataStart + f * frame
        var sum = 0.0 as Float
        for ch in 0..<channels {
            let o = frameStart + ch * bytesPerSample
            guard o + 1 < b.count else { continue }
            let s = Int16(bitPattern: UInt16(b[o]) | UInt16(b[o + 1]) << 8)
            sum += Float(s) / 32768.0
        }
        out[f] = sum / Float(channels)
    }
    return out
}
