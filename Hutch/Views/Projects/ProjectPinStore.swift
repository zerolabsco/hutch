import Foundation

enum ProjectPinStore {
    static func loadPinnedProjectIDs(
        for userKey: String,
        defaults: UserDefaults = .standard
    ) -> [String] {
        let pinnedProjects = loadAll(defaults: defaults)
        return pinnedProjects[userKey] ?? []
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
        var pinnedProjects = loadAll(defaults: defaults)
        var projectIDs = pinnedProjects[userKey] ?? []

        if let index = projectIDs.firstIndex(of: projectID) {
            projectIDs.remove(at: index)
        } else {
            projectIDs.append(projectID)
        }

        pinnedProjects[userKey] = projectIDs
        save(pinnedProjects, defaults: defaults)
    }

    private static func loadAll(defaults: UserDefaults) -> [String: [String]] {
        guard let data = defaults.data(forKey: AppStorageKeys.pinnedHomeProjects) else {
            return [:]
        }

        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    private static func save(_ pinnedProjects: [String: [String]], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(pinnedProjects) else { return }
        defaults.set(data, forKey: AppStorageKeys.pinnedHomeProjects)
    }
}
