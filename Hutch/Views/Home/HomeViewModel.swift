import Foundation
import os

private let homeLogger = Logger(subsystem: "net.cleberg.Hutch", category: "Home")

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
    let cursor: String?
}

private struct HomeInboxThreadPayload: Decodable, Sendable {
    let created: Date
    let updated: Date
    let subject: String
    let replies: Int
    let sender: Entity
    let root: HomeInboxEmailPreview
}

private struct HomeInboxEmailPreview: Decodable, Sendable {
    let id: Int
    let subject: String
    let date: Date?
    let received: Date
    let messageID: String
    let body: String
    let patch: HomeInboxPatchPreview?
}

private struct HomeInboxPatchPreview: Decodable, Sendable {
    let subject: String?
}

private struct HomeInboxUnreadSnapshot: Sendable {
    let unreadCount: Int
    let threads: [InboxThreadSummary]
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

    var requiresAttention: Bool {
        switch job.status {
        case .failed, .timeout, .running, .queued, .pending:
            true
        case .success, .cancelled:
            false
        }
    }
}

@Observable
@MainActor
final class HomeViewModel {
    nonisolated static let defaultFailedBuildLookbackDays = 7
    nonisolated static let allowedFailedBuildLookbackDays = [1, 3, 7, 14, 30]

    private(set) var projects: [Project] = []
    var assignedTickets: [HomeAssignedTicket] = []
    var recentBuilds: [HomeBuildItem] = []
    var unreadInboxThreads: [InboxThreadSummary] = []
    private(set) var systemStatusSnapshot: SystemStatusSnapshot?
    private(set) var isLoadingSystemStatus = false
    private(set) var isShowingStaleSystemStatus = false
    private(set) var systemStatusErrorMessage: String?
    private(set) var hasUnreadInboxThreads = false
    private(set) var unreadInboxThreadCount: Int?
    private(set) var isLoadingProjects = false
    private(set) var isLoadingAssignedTickets = false
    private(set) var isLoadingRecentBuilds = false
    private(set) var projectsError: String?
    private(set) var assignedTicketsError: String?
    private(set) var recentBuildsError: String?
    private(set) var lastRefreshed: Date?

    private let currentUser: User
    private let client: SRHTClient
    private let systemStatusRepository: SystemStatusRepository
    private let projectService: ProjectService
    private let ticketFetchConcurrencyLimit = 6
    private let inboxUnreadConcurrencyLimit = 4

    private var currentUserKey: String {
        currentUser.canonicalName
    }

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
    query inboxListThreads($rid: ID!, $cursor: Cursor) {
        list(rid: $rid) {
            threads(cursor: $cursor) {
                results {
                    created
                    updated
                    subject
                    replies
                    sender { canonicalName }
                    root {
                        id
                        subject
                        date
                        received
                        messageID
                        body
                        patch { subject }
                    }
                }
                cursor
            }
        }
    }
    """

    private static let updateTicketStatusMutation = """
    mutation updateTicketStatus($trackerId: Int!, $ticketId: Int!, $input: UpdateStatusInput!) {
        updateTicketStatus(trackerId: $trackerId, ticketId: $ticketId, input: $input) {
            eventType: __typename
        }
    }
    """

    private static let unassignUserMutation = """
    mutation unassignUser($trackerId: Int!, $ticketId: Int!, $userId: Int!) {
        unassignUser(trackerId: $trackerId, ticketId: $ticketId, userId: $userId) { id }
    }
    """

    private static let cancelBuildMutation = """
    mutation cancel($id: Int!) {
        cancel(jobId: $id) { id }
    }
    """

    private let defaults: UserDefaults
    private let accountID: String

    init(
        currentUser: User,
        client: SRHTClient,
        systemStatusRepository: SystemStatusRepository,
        defaults: UserDefaults,
        accountID: String
    ) {
        self.currentUser = currentUser
        self.client = client
        self.systemStatusRepository = systemStatusRepository
        self.projectService = ProjectService(client: client)
        self.defaults = defaults
        self.accountID = accountID
    }

    func loadDashboard() async {
        isLoadingProjects = true
        isLoadingAssignedTickets = true
        isLoadingRecentBuilds = true
        isLoadingSystemStatus = true
        projectsError = nil
        assignedTicketsError = nil
        recentBuildsError = nil
        isShowingStaleSystemStatus = false
        systemStatusErrorMessage = nil

        async let projectsTask = loadProjects()
        async let jobsTask = loadRecentJobs()
        async let assignedTicketsTask = loadAssignedTickets()
        async let inboxUnreadTask = loadInboxUnreadSnapshot()
        async let systemStatusTask = loadSystemStatusSnapshot()

        let projectsResult = await projectsTask
        switch projectsResult {
        case .success(let projects):
            self.projects = projects
            self.projectsError = nil
        case .failure(let error):
            self.projectsError = error.userFacingMessage
        }
        isLoadingProjects = false

        let recentJobsResult = await jobsTask

        switch recentJobsResult {
        case .success(let recentJobs):
            let buildItems = Self.buildItems(from: recentJobs)
            self.recentBuilds = buildItems
            self.recentBuildsError = nil
        case .failure(let error):
            self.recentBuilds = []
            self.recentBuildsError = error.userFacingMessage
        }
        isLoadingRecentBuilds = false

        let assignedTicketsResult = await assignedTicketsTask

        switch assignedTicketsResult {
        case .success(let assignedTickets):
            self.assignedTickets = assignedTickets
            self.assignedTicketsError = nil
        case .failure(let error):
            self.assignedTickets = []
            self.assignedTicketsError = error.userFacingMessage
        }
        isLoadingAssignedTickets = false

        let inboxUnreadSnapshot = await inboxUnreadTask
        unreadInboxThreadCount = inboxUnreadSnapshot?.unreadCount
        unreadInboxThreads = inboxUnreadSnapshot?.threads ?? []
        hasUnreadInboxThreads = (unreadInboxThreadCount ?? 0) > 0
        let systemStatusResult = await systemStatusTask
        switch systemStatusResult {
        case .success(let result):
            systemStatusSnapshot = result.value
            isShowingStaleSystemStatus = result.isStale
            systemStatusErrorMessage = result.isStale ? result.refreshErrorMessage : nil
        case .failure(let error):
            systemStatusErrorMessage = error.userFacingMessage
        }
        isLoadingSystemStatus = false
        lastRefreshed = Date()
        persistNeedsAttentionSnapshot()
        persistSystemStatusWidgetSnapshot()
    }

    /// Returns true if sufficient time has elapsed since the last dashboard refresh.
    func needsRefresh(after interval: TimeInterval = 60) -> Bool {
        guard let lastRefreshed else { return true }
        return Date().timeIntervalSince(lastRefreshed) > interval
    }

    var hasDashboardContent: Bool {
        !pinnedProjects.isEmpty || !assignedTickets.isEmpty || !recentBuilds.isEmpty || !unreadInboxThreads.isEmpty || systemStatusSnapshot != nil
    }

    var pinnedProjects: [Project] {
        let pinnedIDs = HomePinStore.pinnedProjectIDs(for: currentUserKey, defaults: defaults)
        guard !pinnedIDs.isEmpty else { return [] }

        let projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        return pinnedIDs.compactMap { projectsByID[$0] }
    }

    var hasPinnedProjects: Bool {
        !HomePinStore.loadPins(for: currentUserKey, defaults: defaults).isEmpty
    }

    var failedBuildCount: Int {
        recentFailedBuilds().count
    }

    var activeBuildCount: Int {
        recentBuilds.filter {
            switch $0.job.status {
            case .pending, .queued, .running:
                return true
            default:
                return false
            }
        }.count
    }

    var activeIncidentCount: Int {
        systemStatusSnapshot?.activeIncidents.count ?? 0
    }

    var disruptedServiceCount: Int {
        systemStatusSnapshot?.disruptedServices.count ?? 0
    }

    var needsAttentionCount: Int {
        var count = 0
        if let unreadInboxThreadCount {
            count += unreadInboxThreadCount
        }
        count += assignedTickets.count
        count += failedBuildCount
        count += activeBuildCount
        if let snapshot = systemStatusSnapshot, snapshot.hasDisruption {
            count += max(snapshot.disruptedServices.count, snapshot.activeIncidents.count)
        }
        return count
    }

    var attentionSummaryText: String {
        if needsAttentionCount == 0 {
            return "All clear"
        }
        var parts: [String] = []
        if let unreadInboxThreadCount, unreadInboxThreadCount > 0 {
            parts.append(Self.countLabel(unreadInboxThreadCount, singular: "unread thread"))
        }
        if !assignedTickets.isEmpty {
            parts.append(Self.countLabel(assignedTickets.count, singular: "assigned ticket"))
        }
        if failedBuildCount > 0 {
            parts.append(Self.countLabel(failedBuildCount, singular: "failed build"))
        }
        if activeBuildCount > 0 {
            parts.append(Self.countLabel(activeBuildCount, singular: "active build"))
        }
        if disruptedServiceCount > 0 {
            parts.append(Self.countLabel(disruptedServiceCount, singular: "service issue"))
        }
        return parts.joined(separator: " • ")
    }

    var inboxSummaryText: String {
        guard let unreadInboxThreadCount else { return "Inbox status unavailable" }
        if unreadInboxThreadCount == 0 {
            return "Inbox zero"
        }
        return "\(Self.countLabel(unreadInboxThreadCount, singular: "unread thread")) across your lists"
    }

    var ticketsSummaryText: String {
        if assignedTickets.isEmpty {
            return "No open tickets assigned to you"
        }
        return Self.countLabel(assignedTickets.count, singular: "open assigned ticket")
    }

    var buildsSummaryText: String {
        if recentBuilds.isEmpty {
            return "No recent builds"
        }
        var parts: [String] = []
        if failedBuildCount > 0 {
            parts.append(Self.countLabel(failedBuildCount, singular: "failed build"))
        }
        if activeBuildCount > 0 {
            parts.append(Self.countLabel(activeBuildCount, singular: "active build"))
        }
        if parts.isEmpty {
            return "Recent builds are clear"
        }
        return parts.joined(separator: " • ")
    }

    func recentFailedBuilds(
        lookbackDays: Int? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [HomeBuildItem] {
        Self.failedBuilds(
            in: recentBuilds,
            lookbackDays: lookbackDays ?? Self.failedBuildLookbackDays(),
            now: now,
            calendar: calendar
        )
    }

    var systemSummaryText: String {
        guard let systemStatusSnapshot else {
            return systemStatusErrorMessage ?? "System status unavailable"
        }
        if systemStatusSnapshot.hasDisruption {
            return systemStatusSnapshot.bannerSummary
        }
        return systemStatusSnapshot.overallStatusText
    }

    func resolveTicket(_ ticket: HomeAssignedTicket) async {
        let input: [String: any Sendable] = [
            "status": TicketStatus.resolved.rawValue,
            "resolution": TicketResolution.fixed.rawValue
        ]
        await performTicketStatusUpdate(ticket: ticket, input: input)
    }

    func reopenTicket(_ ticket: HomeAssignedTicket) async {
        let input: [String: any Sendable] = [
            "status": TicketStatus.reported.rawValue
        ]
        await performTicketStatusUpdate(ticket: ticket, input: input)
    }

    func unassignFromMe(_ ticket: HomeAssignedTicket) async {
        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.unassignUserMutation,
                variables: [
                    "trackerId": ticket.trackerId,
                    "ticketId": ticket.ticket.id,
                    "userId": currentUser.id
                ],
                responseType: UnassignResponse.self
            )
            assignedTickets.removeAll { $0.id == ticket.id }
            persistNeedsAttentionSnapshot()
        } catch {
            homeLogger.error("Unassign from me failed: \(error, privacy: .public)")
        }
    }

    func cancelBuild(_ build: HomeBuildItem) async {
        guard build.job.status.isCancellable else { return }

        do {
            _ = try await client.execute(
                service: .builds,
                query: Self.cancelBuildMutation,
                variables: ["id": build.job.id],
                responseType: CancelBuildResponse.self
            )
            if let index = recentBuilds.firstIndex(where: { $0.id == build.id }) {
                let updatedJob = JobSummary(
                    id: build.job.id,
                    created: build.job.created,
                    updated: build.job.updated,
                    status: .cancelled,
                    note: build.job.note,
                    tags: build.job.tags,
                    visibility: build.job.visibility,
                    image: build.job.image,
                    tasks: build.job.tasks
                )
                recentBuilds[index] = HomeBuildItem(
                    job: updatedJob,
                    repositoryName: build.repositoryName,
                    repositoryOwner: build.repositoryOwner
                )
            }
            persistNeedsAttentionSnapshot()
        } catch {
            homeLogger.error("Cancel build failed: \(error, privacy: .public)")
        }
    }

    func markInboxThreadRead(_ thread: InboxThreadSummary) {
        InboxReadStateStore.markViewed(max(Date(), thread.lastActivityAt), for: thread.id, defaults: defaults)
        unreadInboxThreads.removeAll { $0.id == thread.id }
        unreadInboxThreadCount = max((unreadInboxThreadCount ?? 1) - 1, 0)
        hasUnreadInboxThreads = (unreadInboxThreadCount ?? 0) > 0
        persistNeedsAttentionSnapshot()
    }

    func markAllInboxThreadsRead() {
        guard !unreadInboxThreads.isEmpty else { return }

        let viewedAt = Date()
        for thread in unreadInboxThreads {
            InboxReadStateStore.markViewed(max(viewedAt, thread.lastActivityAt), for: thread.id, defaults: defaults)
        }

        unreadInboxThreads = []
        unreadInboxThreadCount = 0
        hasUnreadInboxThreads = false
        persistNeedsAttentionSnapshot()
    }

    func markInboxThreadUnread(_ thread: InboxThreadSummary) {
        InboxReadStateStore.markUnread(for: thread.id, defaults: defaults)
        if unreadInboxThreads.contains(where: { $0.id == thread.id }) == false {
            unreadInboxThreads.append(
                InboxThreadSummary(
                    rootEmailID: thread.rootEmailID,
                    rootMessageID: thread.rootMessageID,
                    threadRootEmailIDs: thread.threadRootEmailIDs,
                    threadRootMessageIDs: thread.threadRootMessageIDs,
                    listID: thread.listID,
                    listRID: thread.listRID,
                    listName: thread.listName,
                    listOwner: thread.listOwner,
                    subject: thread.subject,
                    latestSender: thread.latestSender,
                    lastActivityAt: thread.lastActivityAt,
                    messageCount: thread.messageCount,
                    repo: thread.repo,
                    containsPatch: thread.containsPatch,
                    isUnread: true
                )
            )
            unreadInboxThreads.sort(by: Self.sortInboxThreadsForTriage)
        }
        unreadInboxThreadCount = (unreadInboxThreadCount ?? 0) + 1
        hasUnreadInboxThreads = true
        persistNeedsAttentionSnapshot()
    }

    func refreshNeedsAttentionSnapshot() {
        persistNeedsAttentionSnapshot()
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

    private func loadInboxUnreadSnapshot() async -> HomeInboxUnreadSnapshot? {
        do {
            return try await fetchUnreadInboxSnapshot()
        } catch {
            return nil
        }
    }

    private func loadSystemStatusSnapshot() async -> Result<CachedSystemStatusValue<SystemStatusSnapshot>, Error> {
        do {
            return .success(try await systemStatusRepository.snapshotResult())
        } catch {
            return .failure(error)
        }
    }

    private func fetchUnreadInboxSnapshot() async throws -> HomeInboxUnreadSnapshot {
        let mailingLists = try await fetchInboxMailingLists()
        guard !mailingLists.isEmpty else { return HomeInboxUnreadSnapshot(unreadCount: 0, threads: []) }

        var startIndex = mailingLists.startIndex
        var unreadCount = 0
        var successfulFetchCount = 0
        var unreadThreads: [InboxThreadSummary] = []
        while startIndex < mailingLists.endIndex {
            let endIndex = mailingLists.index(
                startIndex,
                offsetBy: inboxUnreadConcurrencyLimit,
                limitedBy: mailingLists.endIndex
            ) ?? mailingLists.endIndex
            let batch = Array(mailingLists[startIndex..<endIndex])

            let batchResult = await withTaskGroup(of: Result<HomeInboxUnreadSnapshot, Error>.self) { group in
                for mailingList in batch {
                    group.addTask {
                        do {
                            return .success(try await self.fetchUnreadThreadSnapshot(for: mailingList))
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                var snapshots: [HomeInboxUnreadSnapshot] = []
                var errors: [Error] = []
                for await result in group {
                    switch result {
                    case .success(let snapshot):
                        snapshots.append(snapshot)
                    case .failure(let error):
                        errors.append(error)
                    }
                }
                return (snapshots, errors)
            }

            unreadCount += batchResult.0.reduce(0) { $0 + $1.unreadCount }
            unreadThreads.append(contentsOf: batchResult.0.flatMap(\.threads))
            successfulFetchCount += batchResult.0.count

            startIndex = endIndex
        }

        guard successfulFetchCount > 0 else {
            throw SRHTError.graphQLErrors([GraphQLError(message: "Failed to load inbox threads", locations: nil)])
        }

        let deduplicatedThreads = Self.deduplicateInboxThreads(unreadThreads)

        return HomeInboxUnreadSnapshot(
            unreadCount: deduplicatedThreads.count,
            threads: deduplicatedThreads
        )
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

    private func fetchUnreadThreadSnapshot(for mailingList: InboxMailingListReference) async throws -> HomeInboxUnreadSnapshot {
        var unreadCount = 0
        var cursor: String?
        var unreadThreads: [InboxThreadSummary] = []

        while true {
            var variables: [String: any Sendable] = ["rid": mailingList.rid]
            if let cursor {
                variables["cursor"] = cursor
            }

            let response = try await client.execute(
                service: .lists,
                query: Self.inboxListThreadsQuery,
                variables: variables,
                responseType: HomeInboxListThreadsResponse.self
            )

            let unreadThreadSummaries = response.list.threads.results.compactMap { thread -> InboxThreadSummary? in
                let summary = InboxThreadSummary(
                    rootEmailID: thread.root.id,
                    rootMessageID: thread.root.messageID,
                    threadRootEmailIDs: [thread.root.id],
                    threadRootMessageIDs: [thread.root.messageID],
                    listID: mailingList.id,
                    listRID: mailingList.rid,
                    listName: mailingList.name,
                    listOwner: mailingList.owner,
                    subject: thread.subject,
                    latestSender: thread.sender,
                    lastActivityAt: thread.updated,
                    messageCount: thread.replies + 1,
                    repo: InboxThreadUtilities.deriveRepositoryName(from: mailingList.name),
                    containsPatch: thread.root.patch != nil || thread.subject.localizedCaseInsensitiveContains("[patch"),
                    isUnread: InboxReadStateStore.isUnread(
                        threadID: "\(mailingList.rid)#\(InboxThreadSummary.normalizationKey(for: thread.subject))",
                        lastActivityAt: thread.updated,
                        defaults: defaults
                    )
                )
                return summary.isUnread ? summary : nil
            }
            unreadCount += unreadThreadSummaries.count
            unreadThreads.append(contentsOf: unreadThreadSummaries)

            guard let nextCursor = response.list.threads.cursor else {
                break
            }
            cursor = nextCursor
        }

        return HomeInboxUnreadSnapshot(
            unreadCount: unreadCount,
            threads: unreadThreads
        )
    }

    private func loadAssignedTickets() async -> Result<[HomeAssignedTicket], Error> {
        do {
            let trackers = try await fetchAllTrackers()
            let tickets = try await fetchAssignedTickets(for: trackers)
                .sorted(by: Self.sortAssignedTicketsForTriage)
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

    private func performTicketStatusUpdate(
        ticket: HomeAssignedTicket,
        input: [String: any Sendable]
    ) async {
        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.updateTicketStatusMutation,
                variables: [
                    "trackerId": ticket.trackerId,
                    "ticketId": ticket.ticket.id,
                    "input": input
                ],
                responseType: StatusEventResponse.self
            )
            assignedTickets.removeAll { $0.id == ticket.id }
            persistNeedsAttentionSnapshot()
        } catch {
            homeLogger.error("Ticket status update failed: \(error, privacy: .public)")
        }
    }

    private func persistNeedsAttentionSnapshot() {
        let failedBuildCount = recentFailedBuilds().count
        NeedsAttentionSnapshotStore.save(
            NeedsAttentionSnapshot(
                unreadInboxThreads: unreadInboxThreadCount,
                assignedOpenTickets: assignedTicketsError == nil ? assignedTickets.count : nil,
                failedBuilds: recentBuildsError == nil ? failedBuildCount : nil,
                updatedAt: .now
            ),
            accountID: accountID
        )
    }

    private func persistSystemStatusWidgetSnapshot() {
        guard let snapshot = systemStatusSnapshot else {
            return
        }
        let widgetSnapshot = SystemStatusWidgetSnapshot(
            services: snapshot.services.map { service in
                SystemStatusWidgetSnapshot.ServiceEntry(
                    id: service.id,
                    name: service.name,
                    status: service.status.displayName,
                    requiresAttention: service.status.requiresAttention
                )
            },
            hasDisruption: snapshot.hasDisruption,
            overallStatusText: snapshot.overallStatusText,
            bannerSummary: snapshot.bannerSummary,
            updatedAt: .now
        )
        SystemStatusWidgetSnapshotStore.save(widgetSnapshot, accountID: accountID)
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
        .sorted(by: sortBuildItemsForTriage)
    }

    nonisolated static func failedBuilds(from jobs: [HomeJobPayload]) -> [HomeBuildItem] {
        buildItems(from: jobs).filter { build in
            switch build.job.status {
            case .failed, .timeout:
                true
            default:
                false
            }
        }
    }

    nonisolated static func failedBuildLookbackDays(defaults: UserDefaults = .standard) -> Int {
        let value = defaults.object(forKey: AppStorageKeys.homeFailedBuildLookbackDays) as? Int
        guard let value, allowedFailedBuildLookbackDays.contains(value) else {
            return defaultFailedBuildLookbackDays
        }
        return value
    }

    nonisolated static func failedBuilds(
        in builds: [HomeBuildItem],
        lookbackDays: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [HomeBuildItem] {
        let normalizedLookbackDays = allowedFailedBuildLookbackDays.contains(lookbackDays)
            ? lookbackDays
            : defaultFailedBuildLookbackDays
        let startOfToday = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(normalizedLookbackDays - 1), to: startOfToday) ?? startOfToday

        return builds.filter { build in
            guard build.job.updated >= windowStart else { return false }
            switch build.job.status {
            case .failed, .timeout:
                return true
            default:
                return false
            }
        }
    }

    nonisolated static func failedBuildLookbackLabel(days: Int) -> String {
        let normalizedDays = allowedFailedBuildLookbackDays.contains(days)
            ? days
            : defaultFailedBuildLookbackDays
        if normalizedDays == 1 {
            return "today"
        }
        return "last \(normalizedDays) days"
    }

    nonisolated static func sortBuildItemsForTriage(_ lhs: HomeBuildItem, _ rhs: HomeBuildItem) -> Bool {
        let lhsPriority = buildPriority(for: lhs.job.status)
        let rhsPriority = buildPriority(for: rhs.job.status)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        if lhs.job.updated != rhs.job.updated {
            return lhs.job.updated > rhs.job.updated
        }
        return lhs.job.id > rhs.job.id
    }

    nonisolated static func sortAssignedTicketsForTriage(_ lhs: HomeAssignedTicket, _ rhs: HomeAssignedTicket) -> Bool {
        if lhs.ticket.created != rhs.ticket.created {
            return lhs.ticket.created < rhs.ticket.created
        }
        return lhs.ticket.id < rhs.ticket.id
    }

    nonisolated static func sortInboxThreadsForTriage(_ lhs: InboxThreadSummary, _ rhs: InboxThreadSummary) -> Bool {
        if lhs.containsPatch != rhs.containsPatch {
            return lhs.containsPatch && !rhs.containsPatch
        }
        if lhs.lastActivityAt != rhs.lastActivityAt {
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
        return InboxThreadSummary.normalizationKey(for: lhs.subject)
            .localizedCaseInsensitiveCompare(InboxThreadSummary.normalizationKey(for: rhs.subject)) == .orderedAscending
    }

    nonisolated static func deduplicateInboxThreads(_ threads: [InboxThreadSummary]) -> [InboxThreadSummary] {
        var grouped: [String: InboxThreadSummary] = [:]

        for thread in threads {
            guard let existing = grouped[thread.threadGroupingKey] else {
                grouped[thread.threadGroupingKey] = thread
                continue
            }

            let latest = thread.lastActivityAt >= existing.lastActivityAt ? thread : existing
            let mergedRootEmailIDs = Array(Set(existing.threadRootEmailIDs + thread.threadRootEmailIDs)).sorted()
            let mergedRootMessageIDs = Array(Set(existing.threadRootMessageIDs + thread.threadRootMessageIDs)).sorted()
            let mergedMessageCount = max(
                existing.messageCount ?? existing.threadRootMessageIDs.count,
                thread.messageCount ?? thread.threadRootMessageIDs.count,
                mergedRootMessageIDs.count
            )

            grouped[thread.threadGroupingKey] = InboxThreadSummary(
                rootEmailID: latest.rootEmailID,
                rootMessageID: latest.rootMessageID,
                threadRootEmailIDs: mergedRootEmailIDs,
                threadRootMessageIDs: mergedRootMessageIDs,
                listID: latest.listID,
                listRID: latest.listRID,
                listName: latest.listName,
                listOwner: latest.listOwner,
                subject: latest.subject,
                latestSender: latest.latestSender,
                lastActivityAt: max(existing.lastActivityAt, thread.lastActivityAt),
                messageCount: mergedMessageCount,
                repo: latest.repo ?? existing.repo,
                containsPatch: latest.containsPatch || existing.containsPatch,
                isUnread: latest.isUnread || existing.isUnread
            )
        }

        return grouped.values.sorted(by: sortInboxThreadsForTriage)
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

    private nonisolated static func buildPriority(for status: JobStatus) -> Int {
        switch status {
        case .failed, .timeout:
            return 0
        case .running:
            return 1
        case .queued, .pending:
            return 2
        case .cancelled:
            return 3
        case .success:
            return 4
        }
    }

    private nonisolated static func countLabel(_ count: Int, singular: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(singular)s"
    }

    private struct StatusEventResponse: Decodable, Sendable {
        struct EventRef: Decodable, Sendable {
            let eventType: String
        }

        let updateTicketStatus: EventRef
    }

    private struct UnassignResponse: Decodable, Sendable {
        struct EventRef: Decodable, Sendable {
            let id: Int
        }

        let unassignUser: EventRef
    }

    private struct CancelBuildResponse: Decodable, Sendable {
        struct CancelResult: Decodable, Sendable {
            let id: Int
        }

        let cancel: CancelResult
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
