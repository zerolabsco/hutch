import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct TicketDetailResponse: Decodable, Sendable {
    let user: UserTrackerTicketWrapper
}

private struct UserTrackerTicketWrapper: Decodable, Sendable {
    let tracker: TrackerTicketWrapper
}

private struct TrackerTicketWrapper: Decodable, Sendable {
    let ticket: TicketDetailPayload
}

private struct TicketDetailPayload: Decodable, Sendable {
    let id: Int
    let created: Date
    let updated: Date
    let title: String
    let description: String?
    let status: TicketStatus
    let resolution: TicketResolution?
    let authenticity: Authenticity
    let submitter: Entity
    let assignees: [Entity]
    let labels: [TicketLabel]
    let events: EventsPage
}

private struct EventsPage: Decodable, Sendable {
    let results: [TicketEvent]
    let cursor: String?
}

private struct SubmitCommentResponse: Decodable, Sendable {
    let submitComment: SubmittedEvent
}

private struct SubmittedEvent: Decodable, Sendable {
    let id: Int
    let created: Date
    let changes: [EventChange]
}

private struct MutationEventResponse: Decodable, Sendable {
    let id: Int
}

private struct UpdateStatusResponse: Decodable, Sendable {
    let updateTicketStatus: UpdatedStatusEvent
}

private struct UpdatedStatusEvent: Decodable, Sendable {
    let eventType: String
}

private struct AssignUserResponse: Decodable, Sendable {
    let assignUser: MutationEventResponse
}

private struct UnassignUserResponse: Decodable, Sendable {
    let unassignUser: MutationEventResponse
}

private struct LabelTicketResponse: Decodable, Sendable {
    let labelTicket: MutationEventResponse
}

private struct UnlabelTicketResponse: Decodable, Sendable {
    let unlabelTicket: MutationEventResponse
}

private struct UserLookupResponse: Decodable, Sendable {
    let user: UserIdPayload
}

private struct UserIdPayload: Decodable, Sendable {
    let id: Int
}

private struct CreateLabelResponse: Decodable, Sendable {
    let createLabel: TicketLabel
}

private struct TrackerLabelsResponse: Decodable, Sendable {
    let user: UserTrackerLabelsWrapper
}

private struct UserTrackerLabelsWrapper: Decodable, Sendable {
    let tracker: TrackerLabelsWrapper
}

private struct TrackerLabelsWrapper: Decodable, Sendable {
    let labels: LabelsPage
}

private struct LabelsPage: Decodable, Sendable {
    let results: [TicketLabel]
}

// MARK: - View Model

@Observable
@MainActor
final class TicketDetailViewModel {

    let ownerUsername: String
    let trackerName: String
    let trackerId: Int
    let trackerRid: String
    let ticketId: Int

    private(set) var ticket: TicketDetail?
    private(set) var events: [TicketEvent] = []
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    private(set) var isPerformingAction = false
    private(set) var trackerLabels: [TicketLabel] = []
    var commentText = ""
    var error: String?

    private let client: SRHTClient

    private static func timelineOrder(lhs: TicketEvent, rhs: TicketEvent) -> Bool {
        if lhs.created == rhs.created {
            return lhs.id < rhs.id
        }
        return lhs.created < rhs.created
    }

    init(ownerUsername: String, trackerName: String, trackerId: Int, trackerRid: String, ticketId: Int, client: SRHTClient) {
        self.ownerUsername = ownerUsername
        self.trackerName = trackerName
        self.trackerId = trackerId
        self.trackerRid = trackerRid
        self.ticketId = ticketId
        self.client = client
    }

    // MARK: - Queries

    private static let detailQuery = """
    query ticket($owner: String!, $tracker: String!, $ticketId: Int!) {
        user(username: $owner) {
            tracker(name: $tracker) {
                ticket(id: $ticketId) {
                    id
                    created
                    updated
                    title: subject
                    description: body
                    status
                    resolution
                    authenticity
                    submitter { canonicalName }
                    assignees { canonicalName }
                    labels { id name backgroundColor foregroundColor }
                    events {
                        results {
                            id
                            created
                            changes {
                                eventType
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
                                ... on TicketMention {
                                    mentioned { id }
                                }
                                ... on UserMention {
                                    mentioned { canonicalName }
                                }
                                ... on Created {
                                    author { canonicalName }
                                }
                            }
                        }
                        cursor
                    }
                }
            }
        }
    }
    """

    private static let submitCommentMutation = """
    mutation submitComment($trackerId: Int!, $ticketId: Int!, $input: SubmitCommentInput!) {
        submitComment(trackerId: $trackerId, ticketId: $ticketId, input: $input) {
            id
            created
            changes {
                eventType
                ... on Comment {
                    author { canonicalName }
                    text
                    authenticity
                }
            }
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

    private static let userLookupQuery = """
    query userLookup($username: String!) {
        user(username: $username) { id }
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

    private static let createLabelMutation = """
    mutation createLabel($trackerId: Int!, $name: String!, $backgroundColor: String!, $foregroundColor: String!) {
        createLabel(trackerId: $trackerId, name: $name, backgroundColor: $backgroundColor, foregroundColor: $foregroundColor) {
            id
            name
            backgroundColor
            foregroundColor
        }
    }
    """

    // MARK: - Public API

    func loadTicket() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            let result = try await client.execute(
                service: .todo,
                query: Self.detailQuery,
                variables: [
                    "owner": ownerUsername,
                    "tracker": trackerName,
                    "ticketId": ticketId
                ],
                responseType: TicketDetailResponse.self
            )
            let payload = result.user.tracker.ticket
            ticket = TicketDetail(
                id: payload.id,
                created: payload.created,
                updated: payload.updated,
                title: payload.title,
                description: payload.description,
                status: payload.status,
                resolution: payload.resolution,
                authenticity: payload.authenticity,
                submitter: payload.submitter,
                assignees: payload.assignees,
                labels: payload.labels
            )
            events = payload.events.results.sorted(by: Self.timelineOrder)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func submitComment() async {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        error = nil

        do {
            let input: [String: any Sendable] = ["text": text]
            let result = try await client.execute(
                service: .todo,
                query: Self.submitCommentMutation,
                variables: [
                    "trackerId": trackerId,
                    "ticketId": ticketId,
                    "input": input
                ],
                responseType: SubmitCommentResponse.self
            )
            // Append the returned event so the comment shows immediately.
            let submitted = result.submitComment
            let event = TicketEvent(
                id: submitted.id,
                created: submitted.created,
                changes: submitted.changes
            )
            events.append(event)
            events.sort(by: Self.timelineOrder)
            commentText = ""
        } catch {
            self.error = error.localizedDescription
        }

        isSubmitting = false
    }
    
    func updateComment(commentId: Int, text: String) async {
        _ = commentId
        _ = text
        error = "Comment editing is not available in todo.sr.ht's public GraphQL API."
    }

    // MARK: - Ticket Actions

    func updateStatus(status: TicketStatus, resolution: TicketResolution) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        error = nil

        do {
            let input: [String: any Sendable] = [
                "status": status.rawValue,
                "resolution": resolution.rawValue
            ]
            _ = try await client.execute(
                service: .todo,
                query: Self.updateStatusMutation,
                variables: [
                    "trackerId": trackerId,
                    "ticketId": ticketId,
                    "input": input
                ],
                responseType: UpdateStatusResponse.self
            )
            // Re-fetch the ticket to get updated status/resolution
            await loadTicket()
        } catch {
            self.error = error.localizedDescription
        }

        isPerformingAction = false
    }

    func assignUser(username: String) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        error = nil

        do {
            // Resolve username to user ID
            let userResult = try await client.execute(
                service: .todo,
                query: Self.userLookupQuery,
                variables: ["username": username],
                responseType: UserLookupResponse.self
            )
            let userId = userResult.user.id

            _ = try await client.execute(
                service: .todo,
                query: Self.assignUserMutation,
                variables: [
                    "trackerId": trackerId,
                    "ticketId": ticketId,
                    "userId": userId
                ],
                responseType: AssignUserResponse.self
            )
            // Reload to reflect the change
            await loadTicket()
        } catch {
            self.error = error.localizedDescription
        }

        isPerformingAction = false
    }

    func unassignUser(username: String) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        error = nil

        do {
            // Resolve username to user ID
            let stripped = username.hasPrefix("~") ? String(username.dropFirst()) : username
            let userResult = try await client.execute(
                service: .todo,
                query: Self.userLookupQuery,
                variables: ["username": stripped],
                responseType: UserLookupResponse.self
            )
            let userId = userResult.user.id

            _ = try await client.execute(
                service: .todo,
                query: Self.unassignUserMutation,
                variables: [
                    "trackerId": trackerId,
                    "ticketId": ticketId,
                    "userId": userId
                ],
                responseType: UnassignUserResponse.self
            )
            // Reload to reflect the change
            await loadTicket()
        } catch {
            self.error = error.localizedDescription
        }

        isPerformingAction = false
    }

    func labelTicket(labelId: Int) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        error = nil

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.labelTicketMutation,
                variables: [
                    "trackerId": trackerId,
                    "ticketId": ticketId,
                    "labelId": labelId
                ],
                responseType: LabelTicketResponse.self
            )
            await loadTicket()
        } catch {
            self.error = error.localizedDescription
        }

        isPerformingAction = false
    }

    func unlabelTicket(labelId: Int) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        error = nil

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.unlabelTicketMutation,
                variables: [
                    "trackerId": trackerId,
                    "ticketId": ticketId,
                    "labelId": labelId
                ],
                responseType: UnlabelTicketResponse.self
            )
            await loadTicket()
        } catch {
            self.error = error.localizedDescription
        }

        isPerformingAction = false
    }

    func loadTrackerLabels() async {
        do {
            let result = try await client.execute(
                service: .todo,
                query: Self.trackerLabelsQuery,
                variables: [
                    "owner": ownerUsername,
                    "tracker": trackerName
                ],
                responseType: TrackerLabelsResponse.self
            )
            trackerLabels = result.user.tracker.labels.results
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createLabel(name: String, backgroundColor: String, foregroundColor: String) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        error = nil

        do {
            let result = try await client.execute(
                service: .todo,
                query: Self.createLabelMutation,
                variables: [
                    "trackerId": trackerId,
                    "name": name,
                    "backgroundColor": backgroundColor,
                    "foregroundColor": foregroundColor
                ],
                responseType: CreateLabelResponse.self
            )
            trackerLabels.append(result.createLabel)
        } catch {
            self.error = error.localizedDescription
        }

        isPerformingAction = false
    }

}
