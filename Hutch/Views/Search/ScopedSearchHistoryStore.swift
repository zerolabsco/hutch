import Foundation

struct ScopedSearchHistoryEntry: Codable, Hashable, Identifiable, Sendable {
    let scopeID: String
    let query: String
    let createdAt: Date

    var id: String {
        "\(scopeID):\(query.lowercased())"
    }
}

enum ScopedSearchHistoryStore {
    private static let maximumEntriesPerScope = 8

    static func load(scopeID: String, defaults: UserDefaults = .standard) -> [ScopedSearchHistoryEntry] {
        loadAll(defaults: defaults)[scopeID] ?? []
    }

    static func record(
        query: String,
        scopeID: String,
        defaults: UserDefaults = .standard,
        now: Date = .now
    ) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return }

        var allEntries = loadAll(defaults: defaults)
        var scopeEntries = allEntries[scopeID] ?? []
        scopeEntries.removeAll {
            $0.query.compare(normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        scopeEntries.insert(
            ScopedSearchHistoryEntry(scopeID: scopeID, query: normalizedQuery, createdAt: now),
            at: 0
        )
        allEntries[scopeID] = Array(scopeEntries.prefix(maximumEntriesPerScope))
        save(allEntries, defaults: defaults)
    }

    static func clear(scopeID: String, defaults: UserDefaults = .standard) {
        var allEntries = loadAll(defaults: defaults)
        allEntries.removeValue(forKey: scopeID)
        save(allEntries, defaults: defaults)
    }

    private static func loadAll(defaults: UserDefaults) -> [String: [ScopedSearchHistoryEntry]] {
        guard let data = defaults.data(forKey: AppStorageKeys.scopedSearchHistory) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: [ScopedSearchHistoryEntry]].self, from: data)
        } catch {
            defaults.removeObject(forKey: AppStorageKeys.scopedSearchHistory)
            return [:]
        }
    }

    private static func save(_ entries: [String: [ScopedSearchHistoryEntry]], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: AppStorageKeys.scopedSearchHistory)
    }
}
