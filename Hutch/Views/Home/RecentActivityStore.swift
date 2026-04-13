import Foundation

enum RecentActivityKind: String, Codable, Sendable {
    case repository
    case ticket
    case build
}

struct RecentActivityEntry: Codable, Hashable, Identifiable, Sendable {
    let kind: RecentActivityKind
    let title: String
    let viewedAt: Date
    let repositoryOwner: String?
    let repositoryName: String?
    let repositoryService: SRHTService?
    let ticketOwnerUsername: String?
    let ticketTrackerName: String?
    let ticketId: Int?
    let buildJobId: Int?

    var id: String {
        switch kind {
        case .repository:
            let service = repositoryService?.rawValue ?? SRHTService.git.rawValue
            return "repo:\(service):\(repositoryOwner ?? "")/\(repositoryName ?? "")"
        case .ticket:
            return "ticket:\(ticketOwnerUsername ?? "")/\(ticketTrackerName ?? "")#\(ticketId ?? 0)"
        case .build:
            return "build:\(buildJobId ?? 0)"
        }
    }

    var detailText: String {
        switch kind {
        case .repository:
            let serviceName = repositoryService?.displayName ?? "Repository"
            return "\(serviceName) • Viewed \(viewedAt.relativeDescription)"
        case .ticket:
            return "Ticket • Viewed \(viewedAt.relativeDescription)"
        case .build:
            return "Build • Viewed \(viewedAt.relativeDescription)"
        }
    }
}

enum RecentActivityStore {
    private static let maximumEntries = 5

    static func load(defaults: UserDefaults) -> [RecentActivityEntry] {
        guard let data = defaults.data(forKey: AppStorageKeys.recentActivity) else {
            return []
        }

        do {
            return try JSONDecoder().decode([RecentActivityEntry].self, from: data)
        } catch {
            defaults.removeObject(forKey: AppStorageKeys.recentActivity)
            return []
        }
    }

    static func recordRepository(
        _ repository: RepositorySummary,
        defaults: UserDefaults,
        now: Date = .now
    ) {
        record(
            RecentActivityEntry(
                kind: .repository,
                title: "\(repository.owner.canonicalName)/\(repository.name)",
                viewedAt: now,
                repositoryOwner: repository.owner.canonicalName.srhtUsername,
                repositoryName: repository.name,
                repositoryService: repository.service,
                ticketOwnerUsername: nil,
                ticketTrackerName: nil,
                ticketId: nil,
                buildJobId: nil
            ),
            defaults: defaults
        )
    }

    static func recordTicket(
        ownerUsername: String,
        trackerName: String,
        ticketId: Int,
        title: String,
        defaults: UserDefaults,
        now: Date = .now
    ) {
        record(
            RecentActivityEntry(
                kind: .ticket,
                title: "#\(ticketId) \(title)",
                viewedAt: now,
                repositoryOwner: nil,
                repositoryName: nil,
                repositoryService: nil,
                ticketOwnerUsername: ownerUsername,
                ticketTrackerName: trackerName,
                ticketId: ticketId,
                buildJobId: nil
            ),
            defaults: defaults
        )
    }

    static func recordBuild(
        jobId: Int,
        title: String,
        defaults: UserDefaults,
        now: Date = .now
    ) {
        record(
            RecentActivityEntry(
                kind: .build,
                title: title,
                viewedAt: now,
                repositoryOwner: nil,
                repositoryName: nil,
                repositoryService: nil,
                ticketOwnerUsername: nil,
                ticketTrackerName: nil,
                ticketId: nil,
                buildJobId: jobId
            ),
            defaults: defaults
        )
    }

    private static func record(_ entry: RecentActivityEntry, defaults: UserDefaults) {
        var entries = load(defaults: defaults)
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)

        if entries.count > maximumEntries {
            entries = Array(entries.prefix(maximumEntries))
        }

        save(entries, defaults: defaults)
    }

    private static func save(_ entries: [RecentActivityEntry], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: AppStorageKeys.recentActivity)
    }
}
