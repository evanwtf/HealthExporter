import Foundation

/// The last exports, newest first. `SettingsManager` stores it as JSON.
nonisolated struct ExportHistory: Codable, Equatable, Sendable {
    /// The history keeps this many entries. A new entry removes the oldest.
    static let maxEntries = 10

    private(set) var entries: [ExportHistoryEntry]

    init(entries: [ExportHistoryEntry] = []) {
        self.entries = Array(entries.prefix(Self.maxEntries))
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    /// The newest entry.
    var latest: ExportHistoryEntry? {
        entries.first
    }

    /// Puts `entry` first and removes the entries after the cap.
    mutating func add(_ entry: ExportHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }

    mutating func clear() {
        entries.removeAll()
    }

    /// Only a successful save in the file picker adds an entry. A failure adds
    /// nothing. A cancel does not call `onCompletion`, so it adds nothing too.
    static func shouldRecord(saveResult: Result<URL, any Error>) -> Bool {
        if case .success = saveResult {
            return true
        }
        return false
    }

    /// The JSON that `SettingsManager` stores.
    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Reads stored JSON. A missing or bad value gives an empty history, so a
    /// damaged value never stops the app.
    static func decoded(from data: Data?) -> ExportHistory {
        guard let data, let history = try? JSONDecoder().decode(ExportHistory.self, from: data) else {
            return ExportHistory()
        }
        return ExportHistory(entries: history.entries)
    }
}
