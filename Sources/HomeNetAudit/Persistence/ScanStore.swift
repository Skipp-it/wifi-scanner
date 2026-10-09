import Foundation

/// Persists scan snapshots as individual JSON files in the app's Documents
/// directory. One file per snapshot keeps writes cheap and deletes trivial.
final class ScanStore {

    private let directory: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @discardableResult
    func save(_ snapshot: ScanSnapshot) -> Bool {
        let url = directory.appendingPathComponent("\(snapshot.id.uuidString).json")
        do {
            try encoder.encode(snapshot).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// All snapshots, newest first.
    func loadAll() -> [ScanSnapshot] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(ScanSnapshot.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    func delete(_ snapshot: ScanSnapshot) {
        let url = directory.appendingPathComponent("\(snapshot.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    func deleteAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
