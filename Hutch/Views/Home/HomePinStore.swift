import Foundation

enum HomePinKind: String, Codable, Sendable {
    case project
    case repository
    case tracker
    case mailingList
    case user
}

struct HomePinRecord: Codable, Hashable, Identifiable, Sendable {
    let kind: HomePinKind
    let value: String
    let title: String
    let subtitle: String
    let ownerUsername: String?
    let service: SRHTService?

    var id: String {
        switch kind {
        case .project:
            return "\(kind.rawValue):\(value)"
        case .repository:
            return "\(kind.rawValue):\(service?.rawValue ?? "git"):\(ownerUsername ?? "")/\(value)"
        case .tracker, .mailingList:
            return "\(kind.rawValue):\(ownerUsername ?? "")/\(value)"
        case .user:
            return "\(kind.rawValue):\(ownerUsername ?? value)"
        }
    }

    static func project(_ project: Project) -> HomePinRecord {
        HomePinRecord(
            kind: .project,
            value: project.id,
            title: project.displayName,
            subtitle: "Project",
            ownerUsername: nil,
            service: nil
        )
    }

    static func repository(_ repository: RepositorySummary) -> HomePinRecord {
        HomePinRecord(
            kind: .repository,
            value: repository.name,
            title: repository.name,
            subtitle: repository.service == .hg ? "Mercurial Repo" : "Git Repo",
            ownerUsername: repository.owner.canonicalName.srhtUsername,
            service: repository.service
        )
    }

    static func tracker(_ tracker: TrackerSummary) -> HomePinRecord {
        HomePinRecord(
            kind: .tracker,
            value: tracker.name,
            title: tracker.name,
            subtitle: "Tracker",
            ownerUsername: tracker.owner.canonicalName.srhtUsername,
            service: nil
        )
    }

    static func mailingList(_ mailingList: InboxMailingListReference) -> HomePinRecord {
        HomePinRecord(
            kind: .mailingList,
            value: mailingList.rid,
            title: mailingList.name,
            subtitle: "Mailing List",
            ownerUsername: mailingList.owner.canonicalName.srhtUsername,
            service: nil
        )
    }

    static func user(_ user: User) -> HomePinRecord {
        HomePinRecord(
            kind: .user,
            value: user.username,
            title: user.canonicalName,
            subtitle: "User",
            ownerUsername: user.username,
            service: nil
        )
    }
}

enum HomePinStore {
    static func loadPins(
        for userKey: String,
        defaults: UserDefaults = .standard
    ) -> [HomePinRecord] {
        let normalizedUserKey = normalizedUserKey(userKey)
        guard !normalizedUserKey.isEmpty else { return [] }

        let storedPins = loadAll(defaults: defaults)
        if let storedPinsForUser = storedPins[normalizedUserKey] {
            return normalizedPins(storedPinsForUser)
        }

        let legacyProjectIDs = ProjectPinStore.loadLegacyPinnedProjectIDs(for: normalizedUserKey, defaults: defaults)
        guard !legacyProjectIDs.isEmpty else { return [] }

        let migratedPins = legacyProjectIDs.map {
            HomePinRecord(
                kind: .project,
                value: $0,
                title: "Pinned Project",
                subtitle: "Project",
                ownerUsername: nil,
                service: nil
            )
        }
        savePins(migratedPins, for: normalizedUserKey, defaults: defaults)
        return migratedPins
    }

    static func isPinned(
        _ pin: HomePinRecord,
        for userKey: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        loadPins(for: userKey, defaults: defaults).contains(pin)
    }

    static func togglePin(
        _ pin: HomePinRecord,
        for userKey: String,
        defaults: UserDefaults = .standard
    ) {
        let normalizedUserKey = normalizedUserKey(userKey)
        guard !normalizedUserKey.isEmpty else { return }

        var pinsByUser = loadAll(defaults: defaults)
        var pins = normalizedPins(pinsByUser[normalizedUserKey] ?? loadPins(for: normalizedUserKey, defaults: defaults))

        if let index = pins.firstIndex(of: pin) {
            pins.remove(at: index)
        } else {
            pins.append(pin)
        }

        pinsByUser[normalizedUserKey] = pins
        saveAll(pinsByUser, defaults: defaults)
    }

    static func pinnedProjectIDs(
        for userKey: String,
        defaults: UserDefaults = .standard
    ) -> [String] {
        loadPins(for: userKey, defaults: defaults)
            .filter { $0.kind == .project }
            .map(\.value)
    }

    private static func loadAll(defaults: UserDefaults) -> [String: [HomePinRecord]] {
        guard let data = defaults.data(forKey: AppStorageKeys.pinnedHomeItems) else {
            return [:]
        }

        let decoded = (try? JSONDecoder().decode([String: [HomePinRecord]].self, from: data)) ?? [:]
        return decoded.reduce(into: [String: [HomePinRecord]]()) { result, entry in
            let key = normalizedUserKey(entry.key)
            guard !key.isEmpty else { return }
            let pins = normalizedPins(entry.value)
            if !pins.isEmpty {
                result[key] = pins
            }
        }
    }

    private static func savePins(_ pins: [HomePinRecord], for userKey: String, defaults: UserDefaults) {
        var allPins = loadAll(defaults: defaults)
        allPins[userKey] = normalizedPins(pins)
        saveAll(allPins, defaults: defaults)
    }

    private static func saveAll(_ pinsByUser: [String: [HomePinRecord]], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(pinsByUser) else { return }
        defaults.set(data, forKey: AppStorageKeys.pinnedHomeItems)
    }

    private static func normalizedPins(_ pins: [HomePinRecord]) -> [HomePinRecord] {
        var seen = Set<String>()
        return pins.compactMap { pin in
            let title = pin.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = pin.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pin.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !subtitle.isEmpty, !value.isEmpty else { return nil }

            let normalized = HomePinRecord(
                kind: pin.kind,
                value: value,
                title: title,
                subtitle: subtitle,
                ownerUsername: pin.ownerUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
                service: pin.service
            )
            guard seen.insert(normalized.id).inserted else { return nil }
            return normalized
        }
    }

    private static func normalizedUserKey(_ userKey: String) -> String {
        userKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
