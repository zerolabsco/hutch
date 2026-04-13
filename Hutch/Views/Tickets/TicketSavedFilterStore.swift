import Foundation

struct TicketListFilterState: Codable, Hashable, Sendable {
    var status: TicketFilter
    var labelIDs: [Int]

    init(status: TicketFilter = .open, labelIDs: [Int] = []) {
        self.status = status
        self.labelIDs = Array(Set(labelIDs)).sorted()
    }

    var isDefault: Bool {
        status == .open && labelIDs.isEmpty
    }
}

struct SavedTicketFilter: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let state: TicketListFilterState
    let createdAt: Date
}

enum TicketSavedFilterStore {
    static func loadCurrentState(
        for trackerID: String,
        defaults: UserDefaults = .standard
    ) -> TicketListFilterState {
        let allStates = loadStates(defaults: defaults)
        if let savedState = allStates[trackerID] {
            return savedState
        }

        if let legacyRawValue = defaults.string(forKey: legacyStatusKey(for: trackerID)),
           let status = TicketFilter(rawValue: legacyRawValue) {
            return TicketListFilterState(status: status)
        }

        return TicketListFilterState()
    }

    static func saveCurrentState(
        _ state: TicketListFilterState,
        for trackerID: String,
        defaults: UserDefaults = .standard
    ) {
        var allStates = loadStates(defaults: defaults)
        allStates[trackerID] = state
        save(allStates, key: AppStorageKeys.ticketFilterState, defaults: defaults)
        defaults.removeObject(forKey: legacyStatusKey(for: trackerID))
    }

    static func loadSavedFilters(
        for trackerID: String,
        defaults: UserDefaults = .standard
    ) -> [SavedTicketFilter] {
        let allFilters: [String: [SavedTicketFilter]] = loadDictionary(
            key: AppStorageKeys.ticketSavedFilters,
            defaults: defaults
        )
        return allFilters[trackerID] ?? []
    }

    static func saveFilter(
        named name: String,
        state: TicketListFilterState,
        for trackerID: String,
        defaults: UserDefaults = .standard,
        now: Date = .now
    ) -> SavedTicketFilter? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        var allFilters: [String: [SavedTicketFilter]] = loadDictionary(
            key: AppStorageKeys.ticketSavedFilters,
            defaults: defaults
        )
        var trackerFilters = allFilters[trackerID] ?? []
        trackerFilters.removeAll {
            $0.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }

        let savedFilter = SavedTicketFilter(
            id: UUID(),
            name: trimmedName,
            state: state,
            createdAt: now
        )
        trackerFilters.insert(savedFilter, at: 0)
        allFilters[trackerID] = trackerFilters
        save(allFilters, key: AppStorageKeys.ticketSavedFilters, defaults: defaults)
        return savedFilter
    }

    static func deleteFilter(
        id: SavedTicketFilter.ID,
        for trackerID: String,
        defaults: UserDefaults = .standard
    ) {
        var allFilters: [String: [SavedTicketFilter]] = loadDictionary(
            key: AppStorageKeys.ticketSavedFilters,
            defaults: defaults
        )
        var trackerFilters = allFilters[trackerID] ?? []
        trackerFilters.removeAll { $0.id == id }
        allFilters[trackerID] = trackerFilters
        save(allFilters, key: AppStorageKeys.ticketSavedFilters, defaults: defaults)
    }

    private static func loadStates(defaults: UserDefaults) -> [String: TicketListFilterState] {
        loadDictionary(key: AppStorageKeys.ticketFilterState, defaults: defaults)
    }

    private static func loadDictionary<T: Decodable>(
        key: String,
        defaults: UserDefaults
    ) -> [String: T] {
        guard let data = defaults.data(forKey: key) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: T].self, from: data)
        } catch {
            defaults.removeObject(forKey: key)
            return [:]
        }
    }

    private static func save<T: Encodable>(
        _ value: [String: T],
        key: String,
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func legacyStatusKey(for trackerID: String) -> String {
        "ticketFilter_\(trackerID)"
    }
}
