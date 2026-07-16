import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct TicketDetailResponse: Decodable, Sendable {
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
    /// Null when the authenticated user is not subscribed to this ticket.
    let subscription: SubscriptionIdPayload?
    let submitter: Entity
    let assignees: [Entity]
    let labels: [TicketLabel]
    let events: EventsPage
}

struct SubscriptionIdPayload: Decodable, Sendable {
    let id: Int
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

private struct TicketSubscriptionResponse: Decodable, Sendable {
    let subscription: SubscriptionIdPayload
}

private struct UpdateTicketResponse: Decodable, Sendable {
    let updateTicket: TicketIdPayload
}

private struct DeleteTicketResponse: Decodable, Sendable {
    let deleteTicket: TicketIdPayload
}

private struct TicketIdPayload: Decodable, Sendable {
    let id: Int
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
    private static func cacheKey(ownerUsername: String, trackerRid: String, ticketId: Int) -> String {
        APICacheKeys.ticketDetail(owner: ownerUsername, trackerRid: trackerRid, ticketId: ticketId)
    }

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
    /// Whether the authenticated user receives email for this ticket. Mirrors
    /// `Ticket.subscription`, which is null when not subscribed.
    private(set) var isSubscribed = false
    private(set) var trackerLabels: [TicketLabel] = []
    private(set) var rawTicketResponse: String?
    private(set) var cacheMetadata: CacheEntryMetadata?
    private(set) var isRefreshingCachedData = false
    var commentText = ""
    var error: String?

    private let client: SRHTClient

    private static func timelineOrder(lhs: TicketEvent, rhs: TicketEvent) -> Bool {
        if lhs.created == rhs.created {
            return lhs.id < rhs.id
        }
        return lhs.created < rhs.created
    }

    static func statusUpdateInput(
        status: TicketStatus,
        resolution: TicketResolution?
    ) -> [String: any Sendable] {
        var input: [String: any Sendable] = [
            "status": status.rawValue
        ]
        if status == .resolved, let resolution {
            input["resolution"] = resolution.rawValue
        }
        return input
    }

    /// Builds an `UpdateTicketInput` carrying only the fields that changed, so an
    /// edit never overwrites a field the user did not touch.
    static func ticketUpdateInput(
        subject: String,
        body: String,
        currentSubject: String,
        currentBody: String?
    ) -> [String: any Sendable] {
        var input: [String: any Sendable] = [:]
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedSubject != currentSubject {
            input["subject"] = trimmedSubject
        }

        if trimmedBody != (currentBody ?? "") {
            if trimmedBody.isEmpty {
                // A nil subscript assignment would drop the key and leave the old
                // body in place instead of clearing it.
                input.updateValue(Optional<String>.none as any Sendable, forKey: "body")
            } else {
                input["body"] = trimmedBody
            }
        }

        return input
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
    query ticket($rid: ID!, $ticketId: Int!) {
        tracker(rid: $rid) {
            ticket(id: $ticketId) {
                id
                created
                updated
                title: subject
                description: body
                status
                resolution
                authenticity
                subscription { id }
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

    private static let updateTicketMutation = """
    mutation updateTicket($trackerId: Int!, $ticketId: Int!, $input: UpdateTicketInput!) {
        updateTicket(trackerId: $trackerId, ticketId: $ticketId, input: $input) { id }
    }
    """

    private static let deleteTicketMutation = """
    mutation deleteTicket($trackerId: Int!, $ticketId: Int!) {
        deleteTicket(trackerId: $trackerId, ticketId: $ticketId) { id }
    }
    """

    private static let ticketSubscribeMutation = """
    mutation ticketSubscribe($trackerId: Int!, $ticketId: Int!) {
        subscription: ticketSubscribe(trackerId: $trackerId, ticketId: $ticketId) { id }
    }
    """

    private static let ticketUnsubscribeMutation = """
    mutation ticketUnsubscribe($trackerId: Int!, $ticketId: Int!) {
        subscription: ticketUnsubscribe(trackerId: $trackerId, ticketId: $ticketId) { id }
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
    query trackerLabels($rid: ID!) {
        tracker(rid: $rid) {
            labels {
                results { id name backgroundColor foregroundColor }
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
        rawTicketResponse = nil

        do {
            let result = try await client.executeCached(
                service: .todo,
                query: Self.detailQuery,
                variables: [
                    "rid": trackerRid,
                    "ticketId": ticketId
                ],
                responseType: TicketDetailResponse.self,
                cacheKey: Self.cacheKey(ownerUsername: ownerUsername, trackerRid: trackerRid, ticketId: ticketId),
                resourceType: .ticketDetail,
                ttl: APICacheTTLs.ticketDetail,
                policy: .cacheFirstThenRefresh
            )
            apply(result.value, metadata: result.metadata)
            if result.isFromCache {
                isLoading = false
                await refreshTicketInBackground()
                return
            }
        } catch {
            self.error = error.userFacingMessage
        }

        isLoading = false
    }

    func loadTicketWithDebugCapture() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            let cacheKey = Self.cacheKey(ownerUsername: ownerUsername, trackerRid: trackerRid, ticketId: ticketId)
            let result = try await client.executeCached(
                service: .todo,
                query: Self.detailQuery,
                variables: [
                    "rid": trackerRid,
                    "ticketId": ticketId
                ],
                responseType: TicketDetailResponse.self,
                cacheKey: cacheKey,
                resourceType: .ticketDetail,
                ttl: APICacheTTLs.ticketDetail,
                policy: .refreshIgnoringCache
            )
            rawTicketResponse = await client.cachedPayload(forKey: cacheKey)
                .flatMap { String(data: $0, encoding: .utf8) }
            apply(result.value, metadata: result.metadata)
        } catch {
            self.error = error.userFacingMessage
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
            await invalidateAfterMutation()
        } catch {
            self.error = error.userFacingMessage
        }

        isSubmitting = false
    }
    
    func updateComment(commentId: Int, text: String) async {
        _ = commentId
        _ = text
        error = "Comment editing is not available in todo.sr.ht's public GraphQL API."
    }

    // MARK: - Ticket Actions

    func updateStatus(status: TicketStatus, resolution: TicketResolution? = nil) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        error = nil

        do {
            let input = Self.statusUpdateInput(status: status, resolution: resolution)
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
            await invalidateAfterMutation()
            // Re-fetch the ticket to get updated status/resolution
            await reloadTicketPreservingDebugState()
        } catch {
            self.error = error.userFacingMessage
        }

        isPerformingAction = false
    }

    /// Edits the ticket's subject and body. Returns true when the edit was sent,
    /// including the no-op case where nothing changed.
    @discardableResult
    func updateTicket(subject: String, body: String) async -> Bool {
        guard !isPerformingAction, let ticket else { return false }

        let input = Self.ticketUpdateInput(
            subject: subject,
            body: body,
            currentSubject: ticket.title,
            currentBody: ticket.description
        )
        guard !input.isEmpty else { return true }

        isPerformingAction = true
        error = nil
        defer { isPerformingAction = false }

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.updateTicketMutation,
                variables: [
                    "trackerId": trackerId,
                    "ticketId": ticketId,
                    "input": input
                ],
                responseType: UpdateTicketResponse.self
            )
            await invalidateAfterMutation()
            await reloadTicketPreservingDebugState()
            return true
        } catch {
            self.error = error.userFacingMessage
            return false
        }
    }

    /// Subscribes to or unsubscribes from email notifications for this ticket.
    func toggleSubscription() async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        error = nil
        defer { isPerformingAction = false }

        let wasSubscribed = isSubscribed
        // Reflect the change immediately; the catch below puts it back if the
        // mutation fails, so the control never lies about server state.
        isSubscribed.toggle()

        do {
            _ = try await client.execute(
                service: .todo,
                query: wasSubscribed ? Self.ticketUnsubscribeMutation : Self.ticketSubscribeMutation,
                variables: [
                    "trackerId": trackerId,
                    "ticketId": ticketId
                ],
                responseType: TicketSubscriptionResponse.self
            )
            await client.invalidateCache(prefix: APICacheKeys.prefix(SRHTService.todo.rawValue, "ticket"))
        } catch {
            isSubscribed = wasSubscribed
            self.error = error.userFacingMessage
        }
    }

    /// Deletes the ticket. Returns true on success so the caller can pop the view.
    @discardableResult
    func deleteTicket() async -> Bool {
        guard !isPerformingAction else { return false }
        isPerformingAction = true
        error = nil
        defer { isPerformingAction = false }

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.deleteTicketMutation,
                variables: [
                    "trackerId": trackerId,
                    "ticketId": ticketId
                ],
                responseType: DeleteTicketResponse.self
            )
            await invalidateAfterMutation()
            return true
        } catch {
            self.error = error.userFacingMessage
            return false
        }
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
            await invalidateAfterMutation()
            // Reload to reflect the change
            await reloadTicketPreservingDebugState()
        } catch {
            self.error = error.userFacingMessage
        }

        isPerformingAction = false
    }

    func assignToCurrentUser(_ user: User) async {
        guard !isPerformingAction, let currentTicket = ticket else { return }

        let currentAssignees = currentTicket.assignees
        let currentEntity = Entity(canonicalName: user.canonicalName)
        guard !currentAssignees.contains(where: { Self.matchesAssignee($0, user: user) }) else {
            return
        }

        isPerformingAction = true
        error = nil

        ticket = TicketDetail(
            id: currentTicket.id,
            created: currentTicket.created,
            updated: currentTicket.updated,
            title: currentTicket.title,
            description: currentTicket.description,
            status: currentTicket.status,
            resolution: currentTicket.resolution,
            authenticity: currentTicket.authenticity,
            submitter: currentTicket.submitter,
            assignees: currentAssignees + [currentEntity],
            labels: currentTicket.labels
        )

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.assignUserMutation,
                variables: [
                    "trackerId": trackerId,
                    "ticketId": ticketId,
                    "userId": user.id
                ],
                responseType: AssignUserResponse.self
            )
            await invalidateAfterMutation()
            await reloadTicketPreservingDebugState()
        } catch {
            ticket = TicketDetail(
                id: currentTicket.id,
                created: currentTicket.created,
                updated: currentTicket.updated,
                title: currentTicket.title,
                description: currentTicket.description,
                status: currentTicket.status,
                resolution: currentTicket.resolution,
                authenticity: currentTicket.authenticity,
                submitter: currentTicket.submitter,
                assignees: currentAssignees,
                labels: currentTicket.labels
            )
            self.error = error.userFacingMessage
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
            await invalidateAfterMutation()
            // Reload to reflect the change
            await reloadTicketPreservingDebugState()
        } catch {
            self.error = error.userFacingMessage
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
            await invalidateAfterMutation()
            await reloadTicketPreservingDebugState()
        } catch {
            self.error = error.userFacingMessage
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
            await invalidateAfterMutation()
            await reloadTicketPreservingDebugState()
        } catch {
            self.error = error.userFacingMessage
        }

        isPerformingAction = false
    }

    func loadTrackerLabels() async {
        do {
            let result = try await client.execute(
                service: .todo,
                query: Self.trackerLabelsQuery,
                variables: ["rid": trackerRid],
                responseType: TrackerLabelsResponse.self
            )
            trackerLabels = result.tracker.labels.results
        } catch {
            self.error = error.userFacingMessage
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
            self.error = error.userFacingMessage
        }

        isPerformingAction = false
    }

    private func reloadTicketPreservingDebugState() async {
        if rawTicketResponse != nil {
            await loadTicketWithDebugCapture()
        } else {
            await loadTicket()
        }
    }

    private func refreshTicketInBackground() async {
        guard !isRefreshingCachedData else { return }
        isRefreshingCachedData = true
        defer { isRefreshingCachedData = false }

        do {
            let result = try await client.executeCached(
                service: .todo,
                query: Self.detailQuery,
                variables: [
                    "rid": trackerRid,
                    "ticketId": ticketId
                ],
                responseType: TicketDetailResponse.self,
                cacheKey: Self.cacheKey(ownerUsername: ownerUsername, trackerRid: trackerRid, ticketId: ticketId),
                resourceType: .ticketDetail,
                ttl: APICacheTTLs.ticketDetail,
                policy: .refreshIgnoringCache
            )
            apply(result.value, metadata: result.metadata)
        } catch {
            if ticket == nil {
                self.error = error.userFacingMessage
            }
        }
    }

    private func apply(_ response: TicketDetailResponse, metadata: CacheEntryMetadata?) {
        cacheMetadata = metadata
        let payload = response.tracker.ticket
        let updatedTicket = TicketDetail(
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
        ticket = updatedTicket
        isSubscribed = payload.subscription != nil
        let updatedEvents = payload.events.results.sorted(by: Self.timelineOrder)
        events = updatedEvents
    }

    private func invalidateAfterMutation() async {
        await client.invalidateCache(prefix: APICacheKeys.prefix(SRHTService.todo.rawValue, "ticket"))
        await client.invalidateCache(prefix: APICacheKeys.prefix(SRHTService.todo.rawValue, "tickets"))
        await client.invalidateCache(prefix: APICacheKeys.prefix(SRHTService.todo.rawValue, "tracker"))
        await client.invalidateCache(prefix: APICacheKeys.prefix("home"))
    }

    static func matchesAssignee(_ entity: Entity, user: User) -> Bool {
        let assigneeCanonical = normalizedCanonicalName(entity.canonicalName)
        let userCanonical = normalizedCanonicalName(user.canonicalName)
        if assigneeCanonical == userCanonical {
            return true
        }
        return normalizedUsername(entity.canonicalName) == normalizedUsername(user.username)
    }

    private static func normalizedCanonicalName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("~") {
            return trimmed
        }
        return "~\(trimmed)"
    }

    private static func normalizedUsername(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("~") ? String(trimmed.dropFirst()) : trimmed
    }

}
