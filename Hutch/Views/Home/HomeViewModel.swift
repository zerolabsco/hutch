import Foundation

private struct HomeJobsResponse: Decodable, Sendable {
    let jobs: HomeJobsPage
}

private struct HomeJobsPage: Decodable, Sendable {
    let results: [HomeJobPayload]
}

private struct HomeTrackersResponse: Decodable, Sendable {
    let trackers: HomeTrackersPage
}

private struct HomeTrackersPage: Decodable, Sendable {
    let results: [TrackerSummary]
    let cursor: String?
}

private struct HomeTrackerTicketsResponse: Decodable, Sendable {
    let user: HomeTrackerTicketsUser
}

private struct HomeTrackerTicketsUser: Decodable, Sendable {
    let tracker: HomeTrackerTicketsTracker
}

private struct HomeTrackerTicketsTracker: Decodable, Sendable {
    let tickets: HomeTrackerTicketsPage
}

private struct HomeTrackerTicketsPage: Decodable, Sendable {
    let results: [HomeTicketPayload]
}

private struct HomeInboxSubscriptionsResponse: Decodable, Sendable {
    let subscriptions: HomeInboxSubscriptionPage
}

private struct HomeInboxSubscriptionPage: Decodable, Sendable {
    let results: [HomeInboxSubscription]
    let cursor: String?
}

private struct HomeInboxSubscription: Decodable, Sendable {
    let list: InboxMailingListReference?
}

private struct HomeInboxListThreadsResponse: Decodable, Sendable {
    let list: HomeInboxMailingListThreads
}

private struct HomeInboxMailingListThreads: Decodable, Sendable {
    let threads: HomeInboxThreadPage
}

private struct HomeInboxThreadPage: Decodable, Sendable {
    let results: [HomeInboxThreadPayload]
}

private struct HomeInboxThreadPayload: Decodable, Sendable {
    let updated: Date
    let subject: String
}

private struct HomeTicketPayload: Decodable, Sendable {
    let id: Int
    let title: String
    let status: TicketStatus
    let resolution: TicketResolution?
    let created: Date
    let submitter: Entity
    let labels: [TicketLabel]
    let assignees: [Entity]

    enum CodingKeys: String, CodingKey {
        case id
        case title = "subject"
        case status
        case resolution
        case created
        case submitter
        case labels
        case assignees
    }

    var ticketSummary: TicketSummary {
        TicketSummary(
            id: id,
            title: title,
            status: status,
            resolution: resolution,
            created: created,
            submitter: submitter,
            labels: labels,
            assignees: assignees
        )
    }
}

struct HomeAssignedTicket: Identifiable, Hashable, Sendable {
    let trackerId: Int
    let trackerRid: String
    let trackerName: String
    let ownerCanonicalName: String
    let ticket: TicketSummary

    var id: String {
        "\(trackerRid)#\(ticket.id)"
    }

    var ownerUsername: String {
        if ownerCanonicalName.hasPrefix("~") {
            return String(ownerCanonicalName.dropFirst())
        }
        return ownerCanonicalName
    }
}

struct HomeBuildItem: Identifiable, Hashable, Sendable {
    let job: JobSummary
    let repositoryName: String?
    let repositoryOwner: String?

    var id: Int { job.id }

    var repositoryDisplayName: String? {
        guard let repositoryName else { return nil }
        if let repositoryOwner {
            return "\(repositoryOwner)/\(repositoryName)"
        }
        return repositoryName
    }
}

@Observable
@MainActor
final class HomeViewModel {
    private(set) var projects: [Project] = []
    private(set) var failedBuilds: [HomeBuildItem] = []
    private(set) var assignedTickets: [HomeAssignedTicket] = []
    private(set) var recentBuilds: [HomeBuildItem] = []
    private(set) var hasUnreadInboxThreads = false
    private(set) var isLoadingProjects = false
    private(set) var isLoadingFailedBuilds = false
    private(set) var isLoadingAssignedTickets = false
    private(set) var isLoadingRecentBuilds = false
    private(set) var failedBuildsError: String?
    private(set) var assignedTicketsError: String?
    private(set) var recentBuildsError: String?

    private let currentUser: User
    private let client: SRHTClient
    private let projectService: ProjectService
    private let ticketFetchConcurrencyLimit = 6
    private let inboxUnreadConcurrencyLimit = 4
    private let inboxUnreadThreadPreviewLimit = 10

    private static let jobsQuery = """
    query jobs {
        jobs {
            results {
                id
                created
                updated
                status
                note
                tags
                visibility
                image
                tasks { name status }
                manifest
            }
        }
    }
    """

    private static let trackersQuery = """
    query trackers($cursor: Cursor) {
        trackers(cursor: $cursor) {
            results {
                id
                rid
                name
                description
                visibility
                updated
                owner { canonicalName }
            }
            cursor
        }
    }
    """

    private static let trackerTicketsQuery = """
    query tickets($owner: String!, $tracker: String!) {
        user(username: $owner) {
            tracker(name: $tracker) {
                tickets {
                    results {
                        id
                        subject
                        status
                        resolution
                        created
                        submitter { canonicalName }
                        labels { id name backgroundColor foregroundColor }
                        assignees { canonicalName }
                    }
                }
            }
        }
    }
    """

    private static let inboxSubscriptionsQuery = """
    query inboxSubscriptions($cursor: Cursor) {
        subscriptions(cursor: $cursor) {
            results {
                ... on MailingListSubscription {
                    list {
                        id
                        rid
                        name
                        owner { canonicalName }
                    }
                }
            }
            cursor
        }
    }
    """

    private static let inboxListThreadsQuery = """
    query inboxListThreads($rid: ID!) {
        list(rid: $rid) {
            threads {
                results {
                    updated
                    subject
                }
            }
        }
    }
    """

    init(currentUser: User, client: SRHTClient) {
        self.currentUser = currentUser
        self.client = client
        self.projectService = ProjectService(client: client)
    }

    func loadDashboard() async {
        isLoadingProjects = true
        isLoadingFailedBuilds = true
        isLoadingAssignedTickets = true
        isLoadingRecentBuilds = true
        failedBuildsError = nil
        assignedTicketsError = nil
        recentBuildsError = nil

        async let projectsTask = loadProjects()
        async let jobsTask = loadRecentJobs()
        async let assignedTicketsTask = loadAssignedTickets()
        async let inboxUnreadTask = loadInboxUnreadState()

        let projectsResult = await projectsTask
        switch projectsResult {
        case .success(let projects):
            self.projects = projects
        case .failure:
            self.projects = []
        }
        isLoadingProjects = false

        let recentJobsResult = await jobsTask

        switch recentJobsResult {
        case .success(let recentJobs):
            let buildItems = Self.buildItems(from: recentJobs)
            self.recentBuilds = buildItems
            self.failedBuilds = Self.failedBuilds(from: buildItems)
            self.failedBuildsError = nil
            self.recentBuildsError = nil
        case .failure(let error):
            self.recentBuilds = []
            self.failedBuilds = []
            self.failedBuildsError = error.localizedDescription
            self.recentBuildsError = error.localizedDescription
        }
        isLoadingFailedBuilds = false
        isLoadingRecentBuilds = false

        let assignedTicketsResult = await assignedTicketsTask

        switch assignedTicketsResult {
        case .success(let assignedTickets):
            self.assignedTickets = assignedTickets
            self.assignedTicketsError = nil
        case .failure(let error):
            self.assignedTickets = []
            self.assignedTicketsError = error.localizedDescription
        }
        isLoadingAssignedTickets = false

        hasUnreadInboxThreads = (await inboxUnreadTask) ?? false
    }

    private func loadProjects() async -> Result<[Project], Error> {
        do {
            return .success(try await projectService.fetchProjects())
        } catch {
            return .failure(error)
        }
    }

    private func loadRecentJobs() async -> Result<[HomeJobPayload], Error> {
        do {
            let response = try await client.execute(
                service: .builds,
                query: Self.jobsQuery,
                responseType: HomeJobsResponse.self
            )
            return .success(response.jobs.results)
        } catch {
            return .failure(error)
        }
    }

    private func loadInboxUnreadState() async -> Bool? {
        do {
            return try await fetchHasUnreadInboxThreads()
        } catch {
            return nil
        }
    }

    private func fetchHasUnreadInboxThreads() async throws -> Bool {
        let mailingLists = try await fetchInboxMailingLists()
        guard !mailingLists.isEmpty else { return false }

        var startIndex = mailingLists.startIndex
        while startIndex < mailingLists.endIndex {
            let endIndex = mailingLists.index(
                startIndex,
                offsetBy: inboxUnreadConcurrencyLimit,
                limitedBy: mailingLists.endIndex
            ) ?? mailingLists.endIndex
            let batch = Array(mailingLists[startIndex..<endIndex])

            let batchHasUnread = await withTaskGroup(of: Bool.self) { group in
                for mailingList in batch {
                    group.addTask {
                        (try? await self.fetchHasUnreadThreads(for: mailingList)) ?? false
                    }
                }

                for await hasUnread in group {
                    if hasUnread {
                        group.cancelAll()
                        return true
                    }
                }
                return false
            }

            if batchHasUnread {
                return true
            }

            startIndex = endIndex
        }

        return false
    }

    private func fetchInboxMailingLists() async throws -> [InboxMailingListReference] {
        var subscriptions: [HomeInboxSubscription] = []
        var cursor: String?

        while true {
            var variables: [String: any Sendable] = [:]
            if let cursor {
                variables["cursor"] = cursor
            }

            let response = try await client.execute(
                service: .lists,
                query: Self.inboxSubscriptionsQuery,
                variables: variables.isEmpty ? nil : variables,
                responseType: HomeInboxSubscriptionsResponse.self
            )

            subscriptions.append(contentsOf: response.subscriptions.results)
            guard let nextCursor = response.subscriptions.cursor else {
                break
            }
            cursor = nextCursor
        }

        var seen = Set<String>()
        return subscriptions.compactMap(\.list).filter { seen.insert($0.rid).inserted }
    }

    private func fetchHasUnreadThreads(for mailingList: InboxMailingListReference) async throws -> Bool {
        let response = try await client.execute(
            service: .lists,
            query: Self.inboxListThreadsQuery,
            variables: ["rid": mailingList.rid],
            responseType: HomeInboxListThreadsResponse.self
        )

        return response.list.threads.results.prefix(inboxUnreadThreadPreviewLimit).contains { thread in
            let normalizedSubject = thread.subject
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^(?:(?:re|fwd?)\s*:\s*)+"#, with: "", options: [.regularExpression, .caseInsensitive])
                .lowercased()
            let threadID = "\(mailingList.rid)#\(normalizedSubject)"
            return InboxReadStateStore.isUnread(threadID: threadID, lastActivityAt: thread.updated)
        }
    }

    private func loadAssignedTickets() async -> Result<[HomeAssignedTicket], Error> {
        do {
            let trackers = try await fetchAllTrackers()
            let tickets = try await fetchAssignedTickets(for: trackers)
                .sorted { $0.ticket.created > $1.ticket.created }
            return .success(tickets)
        } catch {
            return .failure(error)
        }
    }

    private func fetchAllTrackers() async throws -> [TrackerSummary] {
        var allTrackers: [TrackerSummary] = []
        var cursor: String?

        while true {
            var variables: [String: any Sendable] = [:]
            if let cursor {
                variables["cursor"] = cursor
            }

            let response = try await client.execute(
                service: .todo,
                query: Self.trackersQuery,
                variables: variables.isEmpty ? nil : variables,
                responseType: HomeTrackersResponse.self
            )

            allTrackers.append(contentsOf: response.trackers.results)
            guard let nextCursor = response.trackers.cursor else {
                break
            }
            cursor = nextCursor
        }

        return allTrackers
    }

    private func fetchAssignedTickets(for trackers: [TrackerSummary]) async throws -> [HomeAssignedTicket] {
        guard !trackers.isEmpty else { return [] }

        var assignedTickets: [HomeAssignedTicket] = []
        var startIndex = trackers.startIndex

        while startIndex < trackers.endIndex {
            let endIndex = trackers.index(startIndex, offsetBy: ticketFetchConcurrencyLimit, limitedBy: trackers.endIndex) ?? trackers.endIndex
            let batch = Array(trackers[startIndex..<endIndex])

            let batchTickets = try await withThrowingTaskGroup(of: [HomeAssignedTicket].self) { group in
                for tracker in batch {
                    group.addTask {
                        try await self.fetchAssignedTickets(for: tracker)
                    }
                }

                var ticketsForBatch: [HomeAssignedTicket] = []
                for try await tickets in group {
                    ticketsForBatch.append(contentsOf: tickets)
                }
                return ticketsForBatch
            }

            assignedTickets.append(contentsOf: batchTickets)
            startIndex = endIndex
        }

        return assignedTickets
    }

    private func fetchAssignedTickets(for tracker: TrackerSummary) async throws -> [HomeAssignedTicket] {
        let response = try await client.execute(
            service: .todo,
            query: Self.trackerTicketsQuery,
            variables: [
                "owner": tracker.owner.canonicalName.hasPrefix("~")
                    ? String(tracker.owner.canonicalName.dropFirst())
                    : tracker.owner.canonicalName,
                "tracker": tracker.name
            ],
            responseType: HomeTrackerTicketsResponse.self
        )

        return response.user.tracker.tickets.results.compactMap { payload in
            guard payload.status.isOpen else {
                return nil
            }
            guard payload.assignees.contains(where: { Self.matchesCurrentUserAssignee($0, currentUser: currentUser) }) else {
                return nil
            }

            return HomeAssignedTicket(
                trackerId: tracker.id,
                trackerRid: tracker.rid,
                trackerName: tracker.name,
                ownerCanonicalName: tracker.owner.canonicalName,
                ticket: payload.ticketSummary
            )
        }
    }

    nonisolated static func buildItems(from jobs: [HomeJobPayload]) -> [HomeBuildItem] {
        jobs.map { job in
            let repository = primaryRepositoryReference(in: job.manifest)
            return HomeBuildItem(
                job: job.jobSummary,
                repositoryName: repository?.name,
                repositoryOwner: repository?.ownerCanonicalName
            )
        }
    }

    nonisolated static func failedBuilds(from builds: [HomeBuildItem]) -> [HomeBuildItem] {
        builds.filter { build in
            switch build.job.status {
            case .failed, .timeout:
                true
            default:
                false
            }
        }
    }

    nonisolated static func failedBuilds(from jobs: [HomeJobPayload]) -> [HomeBuildItem] {
        failedBuilds(from: buildItems(from: jobs))
    }

    nonisolated static func matchesCurrentUserAssignee(_ entity: Entity, currentUser: User) -> Bool {
        let assigneeCanonical = normalizedCanonicalName(entity.canonicalName)
        let currentCanonical = normalizedCanonicalName(currentUser.canonicalName)
        if assigneeCanonical == currentCanonical {
            return true
        }

        let assigneeUsername = normalizedUsername(entity.canonicalName)
        let currentUsername = normalizedUsername(currentUser.username)
        return assigneeUsername == currentUsername
    }

    nonisolated static func primaryRepositoryReference(in manifest: String?) -> (ownerCanonicalName: String, name: String)? {
        guard let manifest else { return nil }
        let pattern = #"(?:https://|ssh://(?:git|hg)@|(?:git|hg)@)(?:git|hg)\.sr\.ht[:/]([~][^/\s]+)/([^\s"'#]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(manifest.startIndex..<manifest.endIndex, in: manifest)
        guard let match = regex.firstMatch(in: manifest, options: [], range: nsRange),
              let ownerRange = Range(match.range(at: 1), in: manifest),
              let nameRange = Range(match.range(at: 2), in: manifest) else {
            return nil
        }

        let owner = String(manifest[ownerRange])
        var name = String(manifest[nameRange])
        if let suffixRange = name.range(of: ".git", options: [.backwards, .anchored]) {
            name.removeSubrange(suffixRange)
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !name.isEmpty else { return nil }
        return (owner, name)
    }

    private nonisolated static func normalizedCanonicalName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.hasPrefix("~") {
            return trimmed
        }
        return "~\(trimmed)"
    }

    private nonisolated static func normalizedUsername(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("~") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }
}
struct HomeJobPayload: Decodable, Sendable {
    let id: Int
    let created: Date
    let updated: Date
    let status: JobStatus
    let note: String?
    let tags: [String]
    let visibility: Visibility?
    let image: String?
    let tasks: [JobTaskSummary]
    let manifest: String?

    nonisolated var jobSummary: JobSummary {
        JobSummary(
            id: id,
            created: created,
            updated: updated,
            status: status,
            note: note,
            tags: tags,
            visibility: visibility,
            image: image,
            tasks: tasks
        )
    }
}
