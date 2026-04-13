import Foundation

enum ProjectPinStore {
    static func loadPinnedProjectIDs(
        for userKey: String,
        defaults: UserDefaults = .standard
    ) -> [String] {
        let generalizedPins = HomePinStore.pinnedProjectIDs(for: userKey, defaults: defaults)
        if !generalizedPins.isEmpty {
            return generalizedPins
        }

        let pinnedProjects = loadAll(defaults: defaults)
        return normalizedProjectIDs(pinnedProjects[userKey] ?? [])
    }

    static func isPinned(
        projectID: String,
        for userKey: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        loadPinnedProjectIDs(for: userKey, defaults: defaults).contains(projectID)
    }

    static func togglePin(
        projectID: String,
        for userKey: String,
        defaults: UserDefaults = .standard
    ) {
        let trimmed = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        HomePinStore.togglePin(
            HomePinRecord(
                kind: .project,
                value: trimmed,
                title: "Pinned Project",
                subtitle: "Project",
                ownerUsername: nil,
                service: nil
            ),
            for: userKey,
            defaults: defaults
        )

        var pinnedProjects = loadAll(defaults: defaults)
        var projectIDs = normalizedProjectIDs(pinnedProjects[userKey] ?? [])

        if let index = projectIDs.firstIndex(of: projectID) {
            projectIDs.remove(at: index)
        } else {
            if let normalizedProjectID = normalizedProjectID(projectID) {
                projectIDs.append(normalizedProjectID)
            }
        }

        pinnedProjects[userKey] = projectIDs
        save(pinnedProjects, defaults: defaults)
    }

    static func loadLegacyPinnedProjectIDs(
        for userKey: String,
        defaults: UserDefaults = .standard
    ) -> [String] {
        let pinnedProjects = loadAll(defaults: defaults)
        return normalizedProjectIDs(pinnedProjects[userKey] ?? [])
    }

    private static func loadAll(defaults: UserDefaults) -> [String: [String]] {
        guard let data = defaults.data(forKey: AppStorageKeys.pinnedHomeProjects) else {
            return [:]
        }

        let decoded = (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
        return decoded.reduce(into: [String: [String]]()) { result, entry in
            let normalizedUserKey = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedUserKey.isEmpty else { return }
            let normalizedProjectIDs = normalizedProjectIDs(entry.value)
            if !normalizedProjectIDs.isEmpty {
                result[normalizedUserKey] = normalizedProjectIDs
            }
        }
    }

    private static func save(_ pinnedProjects: [String: [String]], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(pinnedProjects) else { return }
        defaults.set(data, forKey: AppStorageKeys.pinnedHomeProjects)
    }

    private static func normalizedProjectIDs(_ projectIDs: [String]) -> [String] {
        var seen = Set<String>()
        return projectIDs.compactMap { projectID in
            guard let normalizedProjectID = normalizedProjectID(projectID) else { return nil }
            guard seen.insert(normalizedProjectID).inserted else { return nil }
            return normalizedProjectID
        }
    }

    private static func normalizedProjectID(_ projectID: String) -> String? {
        let trimmed = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
