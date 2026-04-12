import Foundation

@Observable
@MainActor
final class UserProfileViewModel {
    private(set) var repositories: [RepositorySummary] = []
    private(set) var trackers: [TrackerSummary] = []
    private(set) var contributionCalendar: ContributionCalendarResponse?
    private(set) var contributionStats: ContributionStatsResponse?
    private(set) var isLoadingRepositories = false
    private(set) var isLoadingTrackers = false
    private(set) var isLoadingContributions = false
    var repositoriesError: String?
    var trackersError: String?
    var contributionsError: String?

    private let client: SRHTClient
    private let statsService: HutchStatsService
    let ownerUsername: String
    let actor: String

    var isContributionActivityIndexedButEmpty: Bool {
        contributionDisplayState != .populated && contributionDisplayState != .unavailable
    }

    var contributionStatusText: String? {
        switch contributionDisplayState {
        case .indexing:
            return "Activity is being indexed."
        case .empty:
            return "No contribution activity found."
        case .unavailable:
            return "Contribution activity is unavailable."
        case .populated:
            return nil
        }
    }

    init(ownerUsername: String, actor: String, client: SRHTClient, statsService: HutchStatsService) {
        self.ownerUsername = ownerUsername
        self.actor = actor
        self.client = client
        self.statsService = statsService
    }

    func loadRepositories() async {
        isLoadingRepositories = true
        repositoriesError = nil
        defer { isLoadingRepositories = false }

        do {
            let result = try await client.execute(
                service: .git,
                query: Self.repositoriesQuery,
                variables: ["owner": ownerUsername],
                responseType: UserRepositoriesResponse.self
            )
            repositories = result.user.repositories.results.map { $0.repositorySummary(service: .git) }
        } catch {
            repositoriesError = error.userFacingMessage
        }
    }

    func loadTrackers() async {
        isLoadingTrackers = true
        trackersError = nil
        defer { isLoadingTrackers = false }

        do {
            let result = try await client.execute(
                service: .todo,
                query: Self.trackersQuery,
                variables: ["owner": ownerUsername],
                responseType: UserTrackersResponse.self
            )
            trackers = result.user.trackers.results
        } catch {
            trackersError = error.userFacingMessage
        }
    }

    func loadContributions(endingOn endDate: Date? = nil) async {
        isLoadingContributions = true
        contributionsError = nil
        defer { isLoadingContributions = false }

        let resolvedEndDate = Calendar.contributionCalendar.startOfDay(for: endDate ?? Date())
        do {
            async let contributionCalendar = statsService.fetchContributionCalendar(actor: actor, endingOn: resolvedEndDate)
            async let contributionStats = statsService.fetchContributionStats(actor: actor, endingOn: resolvedEndDate)

            self.contributionCalendar = try await contributionCalendar
            self.contributionStats = try await contributionStats
            if contributionDisplayState != .unavailable {
                contributionsError = nil
            }
        } catch {
            contributionsError = error.userFacingMessage
        }
    }

    private static let repositoriesQuery = """
    query userRepositories($owner: String!) {
        user(username: $owner) {
            repositories {
                results {
                    id
                    rid
                    name
                    description
                    visibility
                    updated
                    owner { canonicalName }
                    HEAD { name target }
                }
                cursor
            }
        }
    }
    """

    private static let trackersQuery = """
    query userTrackers($owner: String!) {
        user(username: $owner) {
            trackers {
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
    }
    """

    private struct UserRepositoriesResponse: Decodable, Sendable {
        let user: UserRepositoriesContainer
    }

    private struct UserRepositoriesContainer: Decodable, Sendable {
        let repositories: RepositoriesPage
    }

    private struct RepositoriesPage: Decodable, Sendable {
        let results: [RepositoryPayload]
        let cursor: String?
    }

    private struct RepositoryPayload: Decodable, Sendable {
        let id: Int
        let rid: String
        let name: String
        let description: String?
        let visibility: Visibility
        let updated: Date
        let owner: Entity
        let head: Reference?

        enum CodingKeys: String, CodingKey {
            case id, rid, name, description, visibility, updated, owner
            case head = "HEAD"
        }

        func repositorySummary(service: SRHTService) -> RepositorySummary {
            RepositorySummary(
                id: id,
                rid: rid,
                service: service,
                name: name,
                description: description,
                visibility: visibility,
                updated: updated,
                owner: owner,
                head: head
            )
        }
    }

    private struct UserTrackersResponse: Decodable, Sendable {
        let user: UserTrackersContainer
    }

    private struct UserTrackersContainer: Decodable, Sendable {
        let trackers: TrackersPage
    }

    private struct TrackersPage: Decodable, Sendable {
        let results: [TrackerSummary]
        let cursor: String?
    }

    private enum ContributionDisplayState {
        case populated
        case indexing
        case empty
        case unavailable
    }

    private var contributionDisplayState: ContributionDisplayState {
        if let contributionStats, contributionStats.totalEvents > 0 {
            return .populated
        }

        if let contributionCalendar, !contributionCalendar.isEmpty {
            return .populated
        }

        let indexingState = contributionStats?.indexingState ?? contributionCalendar?.indexingState
        switch indexingState {
        case .pending:
            return .indexing
        case .error:
            return .unavailable
        case .indexed, nil:
            return .empty
        }
    }

}
