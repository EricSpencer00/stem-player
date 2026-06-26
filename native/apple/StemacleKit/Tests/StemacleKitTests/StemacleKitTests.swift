import XCTest
import Foundation
@testable import StemacleKit

// MARK: - Mock URLSession

/// Test double for URLSession. Supports single responses, ordered sequences
/// (last entry repeats), and injected network errors per URL path suffix.
final class MockStemSession: @unchecked Sendable {
    private struct Rule {
        let suffix: String
        var results: [Result<Data, Error>]
        var idx: Int = 0

        mutating func next() throws -> Data {
            let r = results[min(idx, results.count - 1)]
            idx += 1
            switch r {
            case .success(let d): return d
            case .failure(let e): throw e
            }
        }
    }
    private var rules: [Rule] = []
    private(set) var lastUploadedBody: Data?

    // Single-response registration.
    func register(suffix: String, json: String) {
        register(suffix: suffix, data: Data(json.utf8))
    }
    func register(suffix: String, data: Data) {
        rules.append(Rule(suffix: suffix, results: [.success(data)]))
    }

    // Ordered sequence: first call returns jsons[0], second jsons[1], etc.;
    // last entry repeats for all subsequent calls.
    func registerSequence(suffix: String, jsons: [String]) {
        let results = jsons.map { Result<Data, Error>.success(Data($0.utf8)) }
        rules.append(Rule(suffix: suffix, results: results))
    }

    // Inject a URLError for the given path.
    func registerNetworkError(suffix: String,
                               error: Error = URLError(.networkConnectionLost)) {
        rules.append(Rule(suffix: suffix, results: [.failure(error)]))
    }

    private func next(for url: URL) throws -> Data {
        let path = url.path
        guard let idx = rules.indices.first(where: { path.hasSuffix(rules[$0].suffix) }) else {
            throw URLError(.badURL)
        }
        return try rules[idx].next()
    }
}

extension MockStemSession: URLSessionProtocol {
    func data(from url: URL) async throws -> (Data, URLResponse) {
        let d = try next(for: url)
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (d, resp)
    }

    func upload(for request: URLRequest, from body: Data) async throws -> (Data, URLResponse) {
        lastUploadedBody = body
        let d = try next(for: request.url!)
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200,
                                   httpVersion: nil, headerFields: nil)!
        return (d, resp)
    }
}

// MARK: - WAV helpers

/// Build a minimal valid 16-bit PCM mono WAV for `frames` silent frames at 44100 Hz.
private func makeSilentWav(frames: Int) -> Data {
    let dataLen = frames * 2
    var d = Data(capacity: 44 + dataLen)
    func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
    d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + dataLen))
    d.append("WAVE".data(using: .ascii)!)
    d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
    u32(44100); u32(88200); u16(2); u16(16)
    d.append("data".data(using: .ascii)!); u32(UInt32(dataLen))
    d.append(Data(count: dataLen))
    return d
}

/// Build a minimal valid 16-bit PCM **stereo** WAV for `frames` silent frames.
private func makeSilentStereoWav(frames: Int) -> Data {
    let dataLen = frames * 4 // 2ch × 2 bytes
    var d = Data(capacity: 44 + dataLen)
    func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
    d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + dataLen))
    d.append("WAVE".data(using: .ascii)!)
    d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(2) // stereo
    u32(44100); u32(176400); u16(4); u16(16)
    d.append("data".data(using: .ascii)!); u32(UInt32(dataLen))
    d.append(Data(count: dataLen))
    return d
}

// MARK: - Test class

final class StemacleKitTests: XCTestCase {

    // -------------------------------------------------------------------------
    // MARK: Core separation (existing)
    // -------------------------------------------------------------------------

    func testSeparateProducesFourAlignedStems() {
        let fftSize = 4096, hop = 1024
        let len = fftSize + 60 * hop
        let mono = (0..<len).map { i -> Float in
            sinf(0.02 * Float(i)) * 0.5 + sinf(0.2 * Float(i)) * 0.2
        }
        guard let split = Stemacle.separate(left: mono, right: mono, sampleRate: 44100) else {
            return XCTFail("separation returned nil")
        }
        XCTAssertGreaterThan(split.drums.count, 0)
        XCTAssertEqual(split.vocals.count, split.drums.count)
        XCTAssertEqual(split.bass.count, split.drums.count)
        XCTAssertEqual(split.melody.count, split.drums.count)
        XCTAssertTrue(split.bpm >= 60 && split.bpm <= 240, "bpm \(split.bpm)")
        XCTAssertEqual(split.ordered.map(\.name), ["drums", "vocals", "bass", "melody"])
    }

    func testInvalidInputReturnsNil() {
        XCTAssertNil(Stemacle.separate(left: [], right: [], sampleRate: 44100))
        XCTAssertNil(Stemacle.separate(left: [1, 2], right: [1], sampleRate: 44100))
    }

    // -------------------------------------------------------------------------
    // MARK: Loop contract (existing)
    // -------------------------------------------------------------------------

    func testLoopContractMatchesCore() {
        XCTAssertEqual(Stemacle.measureLength(bpm: 120), 2.0, accuracy: 1e-5)
        let end = Stemacle.snapLoopEnd(
            bpm: 120, measureOffset: 0, beatOffset: 0, duration: 60,
            currentSec: 2.6, loopLength: 2.0)
        XCTAssertEqual(end, 4.0, accuracy: 1e-4)
        let r = Stemacle.loopRange(
            bpm: 120, measureOffset: 0, beatOffset: 0, duration: 3,
            currentSec: 2.5, loopLength: 4.0)
        XCTAssertFalse(r.fits)
        let a = Stemacle.audibleStemTime(
            transportSec: 5.5, loopStart: 2.0, loopEnd: 4.0, active: true, duration: 60)
        XCTAssertEqual(a, 3.5, accuracy: 1e-4)
    }

    func testDetectedTempoGridSnapsAndWrapsLoopPlayback() {
        let bpm: Float = 100
        let measure = Stemacle.measureLength(bpm: bpm)
        XCTAssertEqual(measure, 2.4, accuracy: 1e-4)
        let quarterMeasure = measure * 0.25
        let r = Stemacle.loopRange(
            bpm: bpm, measureOffset: 0.25, beatOffset: 0.25,
            duration: 30, currentSec: 3.0, loopLength: quarterMeasure)
        XCTAssertTrue(r.fits)
        XCTAssertEqual(r.start, 2.65, accuracy: 1e-4)
        XCTAssertEqual(r.end, 3.25, accuracy: 1e-4)
        let audible = Stemacle.audibleStemTime(
            transportSec: 7.55, loopStart: r.start, loopEnd: r.end,
            active: true, duration: 30)
        XCTAssertEqual(audible, 2.75, accuracy: 1e-4)
    }

    func testCorruptTempoMetadataFallsBackToFiniteLoopGrid() {
        XCTAssertEqual(Stemacle.measureLength(bpm: .nan), 2.0, accuracy: 1e-4)
        let r = Stemacle.loopRange(
            bpm: .nan, measureOffset: .nan, beatOffset: .nan,
            duration: 30, currentSec: 3.0, loopLength: .nan)
        XCTAssertTrue(r.fits)
        XCTAssertEqual(r.start, 2.0, accuracy: 1e-4)
        XCTAssertEqual(r.end, 4.0, accuracy: 1e-4)
    }

    // -------------------------------------------------------------------------
    // MARK: StemServerClient — quality label
    // -------------------------------------------------------------------------

    func testServerClientQualityLabelDefaultsToHtdemucs() {
        let client = StemServerClient(baseURL: URL(string: "http://localhost:8008")!)
        XCTAssertEqual(client.qualityLabel, "htdemucs")
    }

    func testServerClientQualityLabelMatchesConfiguredModel() {
        let client = StemServerClient(baseURL: URL(string: "http://localhost:8008")!,
                                      model: "htdemucs_ft")
        XCTAssertEqual(client.qualityLabel, "htdemucs_ft")
    }

    // -------------------------------------------------------------------------
    // MARK: StemServerClient — happy-path polling
    // -------------------------------------------------------------------------

    func testServerClientMockPollingReturnsAllFourStems() async throws {
        let session = MockStemSession()
        let client = StemServerClient(baseURL: URL(string: "http://stemtest:8008")!,
                                      session: session)
        session.register(suffix: "/separate",
                         json: #"{"job_id":"t1","status":"processing","model":"htdemucs"}"#)
        session.register(suffix: "/jobs/t1",
                         json: #"{"status":"done","stems":["drums","vocals","bass","melody"],"error":null,"progress":100}"#)
        let wav = makeSilentWav(frames: 441)
        for stem in ["drums", "vocals", "bass", "melody"] {
            session.register(suffix: "/jobs/t1/\(stem)", data: wav)
        }
        let stems = try await client.awaitStems("t1", pollSeconds: 0)
        XCTAssertEqual(Set(stems.keys), ["drums", "vocals", "bass", "melody"])
        for (_, samples) in stems { XCTAssertGreaterThan(samples.count, 0) }
    }

    /// Multi-step poll: server returns "processing" twice then "done".
    func testServerClientPollingRetryUntilDone() async throws {
        let session = MockStemSession()
        let client = StemServerClient(baseURL: URL(string: "http://stemtest:8008")!,
                                      session: session)
        session.register(suffix: "/separate",
                         json: #"{"job_id":"t2","status":"processing","model":"htdemucs"}"#)
        session.registerSequence(suffix: "/jobs/t2", jsons: [
            #"{"status":"processing","stems":[],"error":null,"progress":25}"#,
            #"{"status":"processing","stems":[],"error":null,"progress":66}"#,
            #"{"status":"done","stems":["drums","vocals","bass","melody"],"error":null,"progress":100}"#
        ])
        let wav = makeSilentWav(frames: 441)
        for stem in ["drums", "vocals", "bass", "melody"] {
            session.register(suffix: "/jobs/t2/\(stem)", data: wav)
        }
        let stems = try await client.awaitStems("t2", pollSeconds: 0)
        XCTAssertEqual(Set(stems.keys), ["drums", "vocals", "bass", "melody"])
    }

    /// `onProgress` receives a value for every poll response, in ascending order.
    func testServerClientProgressCallbackFiresWithCorrectValues() async throws {
        let session = MockStemSession()
        let client = StemServerClient(baseURL: URL(string: "http://stemtest:8008")!,
                                      session: session)
        session.register(suffix: "/separate",
                         json: #"{"job_id":"t3","status":"processing","model":"htdemucs"}"#)
        session.registerSequence(suffix: "/jobs/t3", jsons: [
            #"{"status":"processing","stems":[],"error":null,"progress":42}"#,
            #"{"status":"done","stems":["drums","vocals","bass","melody"],"error":null,"progress":100}"#
        ])
        let wav = makeSilentWav(frames: 441)
        for stem in ["drums", "vocals", "bass", "melody"] {
            session.register(suffix: "/jobs/t3/\(stem)", data: wav)
        }
        var progressValues: [Double] = []
        let _ = try await client.awaitStems("t3", pollSeconds: 0) { p in
            progressValues.append(p)
        }
        XCTAssertEqual(progressValues.count, 2, "expected progress for each poll")
        XCTAssertEqual(progressValues[0], 0.42, accuracy: 1e-6)
        XCTAssertEqual(progressValues[1], 1.0,  accuracy: 1e-6)
    }

    // -------------------------------------------------------------------------
    // MARK: StemServerClient — error propagation
    // -------------------------------------------------------------------------

    /// Server reports job failure with a message → awaitStems throws that message.
    func testServerClientThrowsWhenServerReportsJobError() async throws {
        let session = MockStemSession()
        let client = StemServerClient(baseURL: URL(string: "http://stemtest:8008")!,
                                      session: session)
        session.register(suffix: "/jobs/terr",
                         json: #"{"status":"error","stems":[],"error":"OOM on GPU","progress":0}"#)
        do {
            let _ = try await client.awaitStems("terr", pollSeconds: 0)
            XCTFail("expected throw")
        } catch let err as NSError {
            XCTAssertTrue(err.localizedDescription.contains("OOM on GPU"),
                          "expected server message, got: \(err.localizedDescription)")
        }
    }

    /// Server reports failure with error:null → throws generic "server error".
    func testServerClientThrowsGenericMessageWhenServerErrorIsNil() async throws {
        let session = MockStemSession()
        let client = StemServerClient(baseURL: URL(string: "http://stemtest:8008")!,
                                      session: session)
        session.register(suffix: "/jobs/tnull",
                         json: #"{"status":"error","stems":[],"error":null,"progress":0}"#)
        do {
            let _ = try await client.awaitStems("tnull", pollSeconds: 0)
            XCTFail("expected throw")
        } catch let err as NSError {
            XCTAssertTrue(err.localizedDescription.contains("server error"),
                          "expected 'server error' fallback, got: \(err.localizedDescription)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: StemServerClient — network failure propagation
    // -------------------------------------------------------------------------

    /// A network error during submit is rethrown to the caller.
    func testServerClientSubmitNetworkFailureRethrows() async throws {
        let session = MockStemSession()
        let client = StemServerClient(baseURL: URL(string: "http://stemtest:8008")!,
                                      session: session)
        session.registerNetworkError(suffix: "/separate")
        do {
            let _ = try await client.submit(left: [0.0], right: [0.0], sampleRate: 44100)
            XCTFail("expected network error to be rethrown")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    /// A network error during status polling is rethrown to the caller.
    func testServerClientStatusPollNetworkFailureRethrows() async throws {
        let session = MockStemSession()
        let client = StemServerClient(baseURL: URL(string: "http://stemtest:8008")!,
                                      session: session)
        session.registerNetworkError(suffix: "/jobs/tnet")
        do {
            let _ = try await client.awaitStems("tnet", pollSeconds: 0)
            XCTFail("expected network error to be rethrown")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    /// A network error while downloading a stem WAV is rethrown.
    func testServerClientStemDownloadNetworkFailureRethrows() async throws {
        let session = MockStemSession()
        let client = StemServerClient(baseURL: URL(string: "http://stemtest:8008")!,
                                      session: session)
        session.register(suffix: "/jobs/tdl",
                         json: #"{"status":"done","stems":["drums","vocals","bass","melody"],"error":null,"progress":100}"#)
        session.registerNetworkError(suffix: "/jobs/tdl/drums") // first stem fails
        do {
            let _ = try await client.awaitStems("tdl", pollSeconds: 0)
            XCTFail("expected network error to be rethrown")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: StemServerClient — configured() factory
    // -------------------------------------------------------------------------

    func testServerClientConfiguredReturnsNilWhenUrlNotSet() {
        UserDefaults.standard.removeObject(forKey: "stemacle.serverURL")
        XCTAssertNil(StemServerClient.configured())
    }

    func testServerClientConfiguredReturnsNilForEmptyUrl() {
        UserDefaults.standard.set("", forKey: "stemacle.serverURL")
        defer { UserDefaults.standard.removeObject(forKey: "stemacle.serverURL") }
        XCTAssertNil(StemServerClient.configured())
    }

    func testServerClientConfiguredReturnsClientWithCorrectBaseUrl() {
        UserDefaults.standard.set("http://myserver:9000", forKey: "stemacle.serverURL")
        defer { UserDefaults.standard.removeObject(forKey: "stemacle.serverURL") }
        let client = StemServerClient.configured()
        XCTAssertNotNil(client)
        XCTAssertEqual(client?.baseURL.absoluteString, "http://myserver:9000")
    }

    func testServerClientConfiguredReadsModelFromUserDefaults() {
        UserDefaults.standard.set("http://myserver:9000", forKey: "stemacle.serverURL")
        UserDefaults.standard.set("htdemucs_ft", forKey: "stemacle.serverModel")
        defer {
            UserDefaults.standard.removeObject(forKey: "stemacle.serverURL")
            UserDefaults.standard.removeObject(forKey: "stemacle.serverModel")
        }
        XCTAssertEqual(StemServerClient.configured()?.qualityLabel, "htdemucs_ft")
    }

    // -------------------------------------------------------------------------
    // MARK: WAV codec
    // -------------------------------------------------------------------------

    func testWavCodecRoundTrip() {
        let left: [Float] = [0.5, -0.25, 0.1, 0.0]
        let right: [Float] = [0.3, -0.1, 0.4, 0.2]
        let wav = encodeWav(left: left, right: right, sampleRate: 44100)
        let mono = decodeWavMono(wav)
        XCTAssertEqual(mono.count, left.count)
        for i in 0..<left.count {
            let expected = (left[i] + right[i]) / 2
            XCTAssertEqual(mono[i], expected, accuracy: 1.0 / 32768.0 * 2)
        }
    }

    func testDecodeWavMonoReturnsEmptyForEmptyData() {
        XCTAssertTrue(decodeWavMono(Data()).isEmpty)
    }

    func testDecodeWavMonoReturnsEmptyForCorruptData() {
        XCTAssertTrue(decodeWavMono(Data("not a wav file".utf8)).isEmpty)
        XCTAssertTrue(decodeWavMono(Data(repeating: 0xFF, count: 100)).isEmpty)
    }

    /// `decodeWavMono` handles a stereo (2-channel) WAV by averaging channels.
    func testDecodeWavMonoAveragesStereoChannels() {
        // Build a stereo WAV: left = 0x4000 (≈0.5), right = 0x0000 (0.0)
        // Expected mono average ≈ 0.25
        var d = Data(capacity: 44 + 4)
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func i16(_ v: Int16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + 4)); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(2) // stereo
        u32(44100); u32(176400); u16(4); u16(16)
        d.append("data".data(using: .ascii)!); u32(4)
        i16(0x4000); i16(0x0000) // left ≈ 0.5, right = 0.0
        let mono = decodeWavMono(d)
        XCTAssertEqual(mono.count, 1)
        XCTAssertEqual(Double(mono[0]), 0.25, accuracy: 1.0 / 32768.0 * 2)
    }

    /// `encodeWav` with an empty signal produces a valid 44-byte WAV header with no samples.
    func testEncodeWavWithEmptyInputIsValid() {
        let wav = encodeWav(left: [], right: [], sampleRate: 44100)
        XCTAssertEqual(wav.count, 44, "expected header-only WAV")
        // Should decode back to empty
        XCTAssertTrue(decodeWavMono(wav).isEmpty)
    }

    /// `encodeWav` clamps samples outside [-1, 1] before converting to Int16.
    func testEncodeWavClampsOutOfRangeValues() {
        let left: [Float] = [2.0, -3.5]   // way above/below ±1
        let right: [Float] = [1.5, -1.5]
        let wav = encodeWav(left: left, right: right, sampleRate: 44100)
        let mono = decodeWavMono(wav)
        XCTAssertEqual(mono.count, 2)
        // Clamped ±1 → Int16(±32767) → decoded ≈ ±1
        for sample in mono {
            XCTAssertLessThanOrEqual(abs(sample), 1.0 + 1.0/32768.0,
                                     "sample \(sample) exceeds clamped range")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: SubprocessDemucsConfig (macOS only)
    // -------------------------------------------------------------------------

    #if os(macOS)
    func testSubprocessDemucsConfigResolvesDefaultPaths() {
        let cfg = SubprocessDemucsConfig.fromEnv()
        XCTAssertTrue(cfg.script.lastPathComponent == "separate.py",
                      "expected separate.py, got \(cfg.script.lastPathComponent)")
        XCTAssertEqual(cfg.model, "htdemucs")
        XCTAssertEqual(cfg.qualityLabel, "htdemucs")
        let _ = cfg.available()
    }

    /// Direct init with custom paths lets unit tests control the config.
    func testSubprocessDemucsConfigPublicInitSetsFields() {
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        let script = URL(fileURLWithPath: "/tmp/separate.py")
        let cfg = SubprocessDemucsConfig(python: python, script: script, model: "mdx_extra")
        XCTAssertEqual(cfg.python.path, "/usr/bin/python3")
        XCTAssertEqual(cfg.script.path, "/tmp/separate.py")
        XCTAssertEqual(cfg.model, "mdx_extra")
        XCTAssertEqual(cfg.qualityLabel, "mdx_extra")
    }

    /// `available()` is false when the python path does not exist on disk.
    func testSubprocessDemucsUnavailableWhenPythonMissing() {
        let cfg = SubprocessDemucsConfig(
            python: URL(fileURLWithPath: "/nonexistent/python3"),
            script: URL(fileURLWithPath: "/nonexistent/separate.py"),
            model: "htdemucs")
        XCTAssertFalse(cfg.available())
    }

    /// `available()` is true when both python and script exist.
    func testSubprocessDemucsAvailableWhenPathsExist() throws {
        // /usr/bin/python3 ships with macOS; use it as a stand-in for "some python".
        guard FileManager.default.fileExists(atPath: "/usr/bin/python3") else {
            throw XCTSkip("/usr/bin/python3 not present on this machine")
        }
        // Create a temp script so both paths are real.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("stemacle_test_separate_\(UUID().uuidString).py")
        try "".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cfg = SubprocessDemucsConfig(
            python: URL(fileURLWithPath: "/usr/bin/python3"),
            script: tmp,
            model: "htdemucs")
        XCTAssertTrue(cfg.available())
    }

    /// `qualityLabel` reflects the model name from init.
    func testSubprocessDemucsQualityLabelMatchesModel() {
        let cfg = SubprocessDemucsConfig(
            python: URL(fileURLWithPath: "/tmp/python"),
            script: URL(fileURLWithPath: "/tmp/separate.py"),
            model: "htdemucs_ft")
        XCTAssertEqual(cfg.qualityLabel, "htdemucs_ft")
    }
    #endif
}
