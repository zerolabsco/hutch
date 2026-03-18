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

    private(set) var tickets: [TicketSummary] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isCreatingTicket = false
    var error: String?
    var filter: TicketFilter = .open

    private var cursor: String?
    private var hasMore = true
    private let client: SRHTClient

    init(ownerUsername: String, trackerName: String, trackerId: Int, client: SRHTClient) {
        self.ownerUsername = ownerUsername
        self.trackerName = trackerName
        self.trackerId = trackerId
        self.client = client
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

    // MARK: - Computed

    /// Tickets filtered by the selected status filter.
    var filteredTickets: [TicketSummary] {
        switch filter {
        case .open:
            tickets.filter { $0.status.isOpen }
        case .resolved:
            tickets.filter { !$0.status.isOpen }
        case .all:
            tickets
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
            self.error = error.localizedDescription
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
            self.error = error.localizedDescription
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
            self.error = "Couldn’t create the ticket. \(error.localizedDescription)"
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
