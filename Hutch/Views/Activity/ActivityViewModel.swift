import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct ActivityResponse: Decodable, Sendable {
    /// Nullable in the schema, and null when the token lacks the EVENTS scope.
    let events: ActivityPage?
}

private struct ActivityPage: Decodable, Sendable {
    let results: [ActivityEventPayload]
    let cursor: String?
}

private struct ActivityEventPayload: Decodable, Sendable {
    let id: Int
    let created: Date
    let changes: [EventChange]
    let ticket: ActivityTicketPayload
}

private struct ActivityTicketPayload: Decodable, Sendable {
    let id: Int
    let subject: String
    let tracker: ActivityTrackerPayload
}

private struct ActivityTrackerPayload: Decodable, Sendable {
    let id: Int
    let rid: String
    let name: String
    let owner: Entity
}

// MARK: - View Model

/// The authenticated user's ticket activity across every tracker.
///
/// todo.sr.ht's root `events` returns what the user is subscribed to or
/// implicated in, newest first — the closest thing sr.ht offers to a personal
/// feed, and it works across trackers the user does not own.
@Observable
@MainActor
final class ActivityViewModel {

    private(set) var events: [ActivityEvent] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    var error: String?

    private var cursor: String?
    private let client: SRHTClient

    init(client: SRHTClient) {
        self.client = client
    }

    private static let eventsQuery = """
    query activity($cursor: Cursor) {
        events(cursor: $cursor) {
            results {
                id
                created
                changes {
                    eventType: __typename
                    ... on Created { __typename }
                    ... on Comment {
                        author { canonicalName }
                        text
                        authenticity
                    }
                    ... on StatusChange {
                        oldStatus
                        newStatus
                    }
                    ... on LabelUpdate {
                        labeler { canonicalName }
                        label { name }
                    }
                    ... on Assignment {
                        assigner { canonicalName }
                        assignee { canonicalName }
                    }
                }
                ticket {
                    id
                    subject
                    tracker { id rid name owner { canonicalName } }
                }
            }
            cursor
        }
    }
    """

    func loadIfNeeded() async {
        guard events.isEmpty, !isLoading else { return }
        await load()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        cursor = nil
        do {
            let page = try await fetch(cursor: nil)
            events = page.events
            cursor = page.cursor
            hasMore = page.cursor != nil
        } catch {
            self.error = error.userFacingMessage
        }
    }

    func loadMore() async {
        guard !isLoadingMore, !isLoading, let cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await fetch(cursor: cursor)
            events.append(contentsOf: page.events)
            self.cursor = page.cursor
            hasMore = page.cursor != nil
        } catch {
            // Keep what is already on screen; the next scroll can retry.
            self.error = error.userFacingMessage
        }
    }

    private func fetch(cursor: String?) async throws -> (events: [ActivityEvent], cursor: String?) {
        var variables: [String: any Sendable] = [:]
        if let cursor {
            variables["cursor"] = cursor
        }

        let response = try await client.execute(
            service: .todo,
            query: Self.eventsQuery,
            variables: variables.isEmpty ? nil : variables,
            responseType: ActivityResponse.self
        )

        guard let page = response.events else {
            throw SRHTError.graphQLErrors([
                GraphQLError(message: "Your token does not grant access to ticket events.", locations: nil)
            ])
        }

        let mapped = page.results.map { payload in
            ActivityEvent(
                id: payload.id,
                created: payload.created,
                changes: payload.changes,
                ticketID: payload.ticket.id,
                ticketSubject: payload.ticket.subject,
                trackerID: payload.ticket.tracker.id,
                trackerRID: payload.ticket.tracker.rid,
                trackerName: payload.ticket.tracker.name,
                trackerOwner: payload.ticket.tracker.owner
            )
        }
        return (mapped, page.cursor)
    }
}

/// One entry in the activity feed, flattened so the row does not have to walk
/// into the ticket and tracker payloads.
struct ActivityEvent: Identifiable, Sendable {
    let id: Int
    let created: Date
    let changes: [EventChange]
    let ticketID: Int
    let ticketSubject: String
    let trackerID: Int
    let trackerRID: String
    let trackerName: String
    let trackerOwner: Entity

    var ownerUsername: String {
        trackerOwner.canonicalName.hasPrefix("~")
            ? String(trackerOwner.canonicalName.dropFirst())
            : trackerOwner.canonicalName
    }

    /// A one-line description of what happened, from the first change.
    var summary: String {
        guard let change = changes.first else { return "Updated" }
        switch change.eventType {
        case "Created": return "Filed"
        case "Comment": return "Commented"
        case "StatusChange":
            if let newStatus = change.newStatus {
                return "Status \(newStatus.displayName.lowercased())"
            }
            return "Status changed"
        case "LabelUpdate": return change.label.map { "Labeled \($0.name)" } ?? "Labels changed"
        case "Assignment":
            if let assignee = change.assignee {
                return "Assigned \(assignee.canonicalName)"
            }
            return "Assignment changed"
        default: return "Updated"
        }
    }
}
