import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var rawText: String
    var cleanedText: String?    // nil when cleanup was off or failed
    var appName: String?        // frontmost app at paste time
    var audioFileName: String?  // set when saveAudio is on
}

final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    static let shared = HistoryStore()

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Whisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private var fileURL: URL { Self.directory.appendingPathComponent("history.json") }

    /// Where saved WAV recordings live. Respects a user-chosen custom folder
    /// (Output settings -> Browse); falls back to Application Support.
    static var audioDirectory: URL {
        if let custom = SettingsStore.shared.settings.recordingsDirectory {
            let url = URL(fileURLWithPath: custom, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let dir = directory.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Deletes saved WAV files older than the configured retention window.
    /// No-op when retention is set to Forever.
    func pruneExpiredAudio() {
        guard let days = SettingsStore.shared.settings.recordingRetention.days else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let dir = Self.audioDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files {
            guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    init() { load() }

    func add(_ entry: HistoryEntry) {
        DispatchQueue.main.async {
            self.entries.insert(entry, at: 0)
            self.persist()
        }
    }

    func clear() {
        entries = []
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() {
        // Off the hot path: pipeline calls add() after paste already happened.
        let snapshot = entries
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: self.fileURL, options: .atomic)
            }
        }
    }
}
