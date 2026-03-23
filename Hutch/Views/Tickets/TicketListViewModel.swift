import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct TrackerTicketsResponse: Decodable, Sendable {
    let user: UserTrackerWrapper
}

private struct UserTrackerWrapper: Decodable, Sendable {
    let tracker: TrackerTicketsWrapper
}

private struct TrackerTicketsWrapper: Decodable, Sendable {
    let tickets: TicketsPage
}

private struct TicketsPage: Decodable, Sendable {
    let results: [TicketSummary]
    let cursor: String?
}

// MARK: - Filter

enum TicketFilter: String, CaseIterable, Sendable {
    case open = "Open"
    case resolved = "Resolved"
    case all = "All"
}

// MARK: - View Model

@Observable
@MainActor
final class TicketListViewModel {
    let ownerUsername: String
    let trackerName: String
    let trackerId: Int
    let trackerRid: String

    private(set) var tickets: [TicketSummary] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isCreatingTicket = false
    private(set) var isPerformingAction = false
    private(set) var trackerLabels: [TicketLabel] = []
    var error: String?
    var filter: TicketFilter = .open {
        didSet {
            UserDefaults.standard.set(filter.rawValue, forKey: filterDefaultsKey)
        }
    }
    var searchText = ""

    private var cursor: String?
    private var hasMore = true
    private let client: SRHTClient

    private var filterDefaultsKey: String {
        "ticketFilter_\(trackerRid)"
    }

    init(ownerUsername: String, trackerName: String, trackerId: Int, trackerRid: String, client: SRHTClient) {
        self.ownerUsername = ownerUsername
        self.trackerName = trackerName
        self.trackerId = trackerId
        self.trackerRid = trackerRid
        self.client = client
        if let raw = UserDefaults.standard.string(forKey: filterDefaultsKey),
           let restored = TicketFilter(rawValue: raw) {
            self.filter = restored
        }
    }

    // MARK: - Query

    private static let query = """
    query tickets($owner: String!, $tracker: String!, $cursor: Cursor) {
        user(username: $owner) {
            tracker(name: $tracker) {
                tickets(cursor: $cursor) {
                    results {
                        id
                        title: subject
                        status
                        resolution
                        created
                        submitter { canonicalName }
                        labels { id name backgroundColor foregroundColor }
                        assignees { canonicalName }
                    }
                    cursor
                }
            }
        }
    }
    """

    private static let submitTicketMutation = """
    mutation submitTicket($trackerId: Int!, $input: SubmitTicketInput!) {
        submitTicket(trackerId: $trackerId, input: $input) {
            id
            title: subject
            status
            resolution
            created
            submitter { canonicalName }
            labels { id name backgroundColor foregroundColor }
            assignees { canonicalName }
        }
    }
    """

    private static let updateStatusMutation = """
    mutation updateTicketStatus($trackerId: Int!, $ticketId: Int!, $input: UpdateStatusInput!) {
        updateTicketStatus(trackerId: $trackerId, ticketId: $ticketId, input: $input) {
            eventType: __typename
        }
    }
    """

    private static let assignUserMutation = """
    mutation assignUser($trackerId: Int!, $ticketId: Int!, $userId: Int!) {
        assignUser(trackerId: $trackerId, ticketId: $ticketId, userId: $userId) { id }
    }
    """

    private static let unassignUserMutation = """
    mutation unassignUser($trackerId: Int!, $ticketId: Int!, $userId: Int!) {
        unassignUser(trackerId: $trackerId, ticketId: $ticketId, userId: $userId) { id }
    }
    """

    private static let labelTicketMutation = """
    mutation labelTicket($trackerId: Int!, $ticketId: Int!, $labelId: Int!) {
        labelTicket(trackerId: $trackerId, ticketId: $ticketId, labelId: $labelId) { id }
    }
    """

    private static let unlabelTicketMutation = """
    mutation unlabelTicket($trackerId: Int!, $ticketId: Int!, $labelId: Int!) {
        unlabelTicket(trackerId: $trackerId, ticketId: $ticketId, labelId: $labelId) { id }
    }
    """

    private static let trackerLabelsQuery = """
    query trackerLabels($owner: String!, $tracker: String!) {
        user(username: $owner) {
            tracker(name: $tracker) {
                labels {
                    results { id name backgroundColor foregroundColor }
                }
            }
        }
    }
    """

    // MARK: - Computed

    /// Tickets filtered by the selected status filter.
    var filteredTickets: [TicketSummary] {
        let statusFiltered: [TicketSummary]
        switch filter {
        case .open:
            statusFiltered = tickets.filter { $0.status.isOpen }
        case .resolved:
            statusFiltered = tickets.filter { !$0.status.isOpen }
        case .all:
            statusFiltered = tickets
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return statusFiltered }
        return statusFiltered.filter {
            String($0.id).contains(q) ||
            $0.title.lowercased().contains(q) ||
            $0.submitter.canonicalName.lowercased().contains(q) ||
            $0.labels.contains { $0.name.lowercased().contains(q) }
        }
    }

    // MARK: - Public API

    func loadTickets() async {
        isLoading = true
        error = nil
        cursor = nil
        hasMore = true

        do {
            let page = try await fetchPage(cursor: nil)
            tickets = page.results
            cursor = page.cursor
            hasMore = page.cursor != nil
        } catch {
            self.error = error.userFacingMessage
        }

        isLoading = false
    }

    func loadMoreIfNeeded(currentItem: TicketSummary) async {
        guard let last = tickets.last,
              last.id == currentItem.id,
              hasMore,
              !isLoadingMore else {
            return
        }

        isLoadingMore = true

        do {
            let page = try await fetchPage(cursor: cursor)
            tickets.append(contentsOf: page.results)
            cursor = page.cursor
            hasMore = page.cursor != nil
        } catch {
            self.error = error.userFacingMessage
        }

        isLoadingMore = false
    }

    func createTicket(subject: String, body: String) async -> TicketSummary? {
        guard !isCreatingTicket else { return nil }

        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty else {
            error = "Enter a ticket title."
            return nil
        }

        isCreatingTicket = true
        error = nil
        defer { isCreatingTicket = false }

        var input: [String: any Sendable] = [
            "subject": trimmedSubject
        ]
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            input["body"] = trimmedBody
        }
        let variables: [String: any Sendable] = [
            "trackerId": trackerId,
            "input": input
        ]

        do {
            let result = try await client.execute(
                service: .todo,
                query: Self.submitTicketMutation,
                variables: variables,
                responseType: SubmitTicketResponse.self
            )
            let ticket = result.submitTicket
            tickets.insert(ticket, at: 0)
            return ticket
        } catch {
            self.error = "Couldn’t create the ticket. \(error.userFacingMessage)"
            return nil
        }
    }

    // MARK: - Private

    private func fetchPage(cursor: String?) async throws -> TicketsPage {
        var variables: [String: any Sendable] = [
            "owner": ownerUsername,
            "tracker": trackerName
        ]
        if let cursor {
            variables["cursor"] = cursor
        }
        let result = try await client.execute(
            service: .todo,
            query: Self.query,
            variables: variables,
            responseType: TrackerTicketsResponse.self
        )
        return result.user.tracker.tickets
    }

    private struct SubmitTicketResponse: Decodable, Sendable {
        let submitTicket: TicketSummary
    }
}
