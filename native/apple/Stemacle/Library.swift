import Foundation
import StemacleKit

/// A split song persisted to disk: metadata + a cache of its four stem WAVs.
/// Backs both the Song Library and "instant re-open" (no re-separation).
struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var createdAt: Date
    var bpm: Float
    var measureOffset: Float
    var beatOffset: Float
    var duration: Double
    var quality: String      // "on-device" or the selected server model
    var sampleRate: Int
}

/// Local project store + stem cache. One JSON index (`projects.json`) plus a
/// per-project folder of `{drums,vocals,bass,melody}.wav` under Application
/// Support. Everything is in the app container, so re-open needs no file
/// permissions and works fully offline.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var projects: [Project] = []

    private let root: URL
    private let indexURL: URL

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        root = base.appendingPathComponent("Stemacle/Projects", isDirectory: true)
        indexURL = base.appendingPathComponent("Stemacle/projects.json")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    func cacheDir(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Persist a fresh split: write stem WAVs + index the project. Returns it.
    @discardableResult
    func add(title: String, stems: [String: [Float]], sampleRate: Int,
             bpm: Float, measureOffset: Float, beatOffset: Float,
             duration: Double, quality: String) -> Project {
        let project = Project(
            id: UUID(), title: title.isEmpty ? "Untitled" : title, createdAt: Date(),
            bpm: bpm, measureOffset: measureOffset, beatOffset: beatOffset,
            duration: duration, quality: quality, sampleRate: sampleRate)
        let dir = cacheDir(project.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, samples) in stems {
            try? writeWavMono(dir.appendingPathComponent("\(name).wav"), samples, sampleRate: sampleRate)
        }
        projects.insert(project, at: 0)
        save()
        return project
    }

    /// Read a project's cached stems (instant re-open). nil if the cache is gone.
    func stems(for project: Project) -> [String: [Float]]? {
        let dir = cacheDir(project.id)
        var out: [String: [Float]] = [:]
        for name in ["drums", "vocals", "bass", "melody"] {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(name).wav")) else {
                return nil
            }
            out[name] = decodeWavMono(data)
        }
        return out
    }

    func delete(_ project: Project) {
        try? FileManager.default.removeItem(at: cacheDir(project.id))
        projects.removeAll { $0.id == project.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([Project].self, from: data) else { return }
        projects = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(projects) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}

/// Write mono Float PCM as a 16-bit WAV.
func writeWavMono(_ url: URL, _ samples: [Float], sampleRate: Int) throws {
    var d = Data(capacity: 44 + samples.count * 2)
    func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
    let dataLen = samples.count * 2
    d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + dataLen)); d.append("WAVE".data(using: .ascii)!)
    d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
    u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
    d.append("data".data(using: .ascii)!); u32(UInt32(dataLen))
    for s in samples {
        var v = Int16(max(-1, min(1, s)) * 32767).littleEndian
        withUnsafeBytes(of: &v) { d.append(contentsOf: $0) }
    }
    try d.write(to: url, options: .atomic)
}
