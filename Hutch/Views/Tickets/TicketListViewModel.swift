import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct TrackerTicketsResponse: Decodable, Sendable {
    let tracker: TrackerTicketsWrapper
}

private struct TrackerTicketsWrapper: Decodable, Sendable {
    let tickets: TicketsPage
}

private struct TicketsPage: Decodable, Sendable {
    let results: [TicketSummary]
    let cursor: String?
}

private struct AssignmentMutationResponse: Decodable, Sendable {
    struct EventRef: Decodable, Sendable {
        let id: Int
    }

    let assignUser: EventRef?
    let unassignUser: EventRef?
}

private struct LabelMutationResponse: Decodable, Sendable {
    struct EventRef: Decodable, Sendable {
        let id: Int
    }

    let labelTicket: EventRef?
    let unlabelTicket: EventRef?
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

private struct UpdateStatusResponse: Decodable, Sendable {
    let updateTicketStatus: MutationEventRef
}

private struct MutationEventRef: Decodable, Sendable {
    let eventType: String
}

// MARK: - Filter

enum TicketFilter: String, CaseIterable, Codable, Sendable {
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
    private(set) var savedFilters: [SavedTicketFilter]
    var error: String?
    var filter: TicketFilter = .open {
        didSet {
            persistFilterState()
        }
    }
    var selectedLabelIDs: Set<Int> = [] {
        didSet {
            persistFilterState()
        }
    }
    var searchText = ""
    private(set) var activeSavedFilterID: SavedTicketFilter.ID?

    private var cursor: String?
    private var hasMore = true
    private let client: SRHTClient
    private let defaults: UserDefaults

    init(
        ownerUsername: String,
        trackerName: String,
        trackerId: Int,
        trackerRid: String,
        client: SRHTClient,
        defaults: UserDefaults = .standard
    ) {
        self.ownerUsername = ownerUsername
        self.trackerName = trackerName
        self.trackerId = trackerId
        self.trackerRid = trackerRid
        self.client = client
        self.defaults = defaults

        let restoredState = TicketSavedFilterStore.loadCurrentState(for: trackerRid, defaults: defaults)
        self.filter = restoredState.status
        self.selectedLabelIDs = Set(restoredState.labelIDs)
        self.savedFilters = TicketSavedFilterStore.loadSavedFilters(for: trackerRid, defaults: defaults)
        self.activeSavedFilterID = self.savedFilters.first(where: { $0.state == restoredState })?.id
    }

    // MARK: - Query

    private static let query = """
    query tickets($rid: ID!, $cursor: Cursor) {
        tracker(rid: $rid) {
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
    query trackerLabels($rid: ID!) {
        tracker(rid: $rid) {
            labels {
                results { id name backgroundColor foregroundColor }
            }
        }
    }
    """

    // MARK: - Computed

    var currentFilterState: TicketListFilterState {
        TicketListFilterState(status: filter, labelIDs: Array(selectedLabelIDs))
    }

    var availableLabels: [TicketLabel] {
        let combinedLabels = trackerLabels + tickets.flatMap(\.labels)
        let deduplicated = combinedLabels.reduce(into: [Int: TicketLabel]()) { partialResult, label in
            partialResult[label.id] = label
        }
        return deduplicated.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var selectedLabels: [TicketLabel] {
        availableLabels.filter { selectedLabelIDs.contains($0.id) }
    }

    var suggestedSavedFilterName: String {
        let labelNames = selectedLabels.map(\.name).sorted()
        var components: [String] = []

        if filter != .open || !labelNames.isEmpty {
            components.append(filter.rawValue)
        }
        if !labelNames.isEmpty {
            components.append(labelNames.joined(separator: ", "))
        }

        return components.isEmpty ? "Open Tickets" : components.joined(separator: " • ")
    }

    var hasCustomFilterSelection: Bool {
        !currentFilterState.isDefault
    }

    /// Tickets filtered by the selected status and label filters.
    var filteredTickets: [TicketSummary] {
        Self.filterTickets(tickets, state: currentFilterState, query: searchText)
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

    func resolveTicket(_ ticket: TicketSummary) async {
        let input: [String: any Sendable] = [
            "status": TicketStatus.resolved.rawValue,
            "resolution": TicketResolution.fixed.rawValue
        ]
        await performStatusUpdate(ticket: ticket, input: input)
    }

    func reopenTicket(_ ticket: TicketSummary) async {
        let input: [String: any Sendable] = [
            "status": TicketStatus.reported.rawValue
        ]
        await performStatusUpdate(ticket: ticket, input: input)
    }

    func assignToMe(ticket: TicketSummary, user: User) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        error = nil

        let original = tickets
        if let index = tickets.firstIndex(where: { $0.id == ticket.id }) {
            let entity = Entity(canonicalName: user.canonicalName)
            let updated = TicketSummary(
                id: ticket.id,
                title: ticket.title,
                status: ticket.status,
                resolution: ticket.resolution,
                created: ticket.created,
                submitter: ticket.submitter,
                labels: ticket.labels,
                assignees: ticket.assignees + [entity]
            )
            tickets[index] = updated
        }

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.assignUserMutation,
                variables: [
                    "trackerId": trackerId,
                    "ticketId": ticket.id,
                    "userId": user.id
                ],
                responseType: AssignmentMutationResponse.self
            )
        } catch {
            tickets = original
            self.error = error.userFacingMessage
        }

        isPerformingAction = false
    }

    func unassignFromMe(ticket: TicketSummary, user: User) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        error = nil

        let original = tickets
        if let index = tickets.firstIndex(where: { $0.id == ticket.id }) {
            let filtered = ticket.assignees.filter { assignee in
                !Self.matchesAssignee(assignee, user: user)
            }
            let updated = TicketSummary(
                id: ticket.id,
                title: ticket.title,
                status: ticket.status,
                resolution: ticket.resolution,
                created: ticket.created,
                submitter: ticket.submitter,
                labels: ticket.labels,
                assignees: filtered
            )
            tickets[index] = updated
        }

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.unassignUserMutation,
                variables: [
                    "trackerId": trackerId,
                    "ticketId": ticket.id,
                    "userId": user.id
                ],
                responseType: AssignmentMutationResponse.self
            )
        } catch {
            tickets = original
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

    func toggleLabelSelection(_ label: TicketLabel) {
        if selectedLabelIDs.contains(label.id) {
            selectedLabelIDs.remove(label.id)
        } else {
            selectedLabelIDs.insert(label.id)
        }
    }

    func clearLabelSelection() {
        selectedLabelIDs = []
    }

    func resetFilters() {
        filter = .open
        selectedLabelIDs = []
    }

    func applySavedFilter(_ savedFilter: SavedTicketFilter) {
        filter = savedFilter.state.status
        selectedLabelIDs = Set(savedFilter.state.labelIDs)
        activeSavedFilterID = savedFilter.id
    }

    func saveCurrentFilter(named name: String) {
        guard let savedFilter = TicketSavedFilterStore.saveFilter(
            named: name,
            state: currentFilterState,
            for: trackerRid,
            defaults: defaults
        ) else {
            return
        }

        savedFilters.removeAll {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        savedFilters.insert(savedFilter, at: 0)
        activeSavedFilterID = savedFilter.id
    }

    func deleteSavedFilter(_ savedFilter: SavedTicketFilter) {
        TicketSavedFilterStore.deleteFilter(id: savedFilter.id, for: trackerRid, defaults: defaults)
        savedFilters.removeAll { $0.id == savedFilter.id }
        if activeSavedFilterID == savedFilter.id {
            activeSavedFilterID = savedFilters.first(where: { $0.state == currentFilterState })?.id
        }
    }

    func labelTicket(_ ticket: TicketSummary, label: TicketLabel) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        error = nil

        let original = tickets
        if let index = tickets.firstIndex(where: { $0.id == ticket.id }) {
            let updated = TicketSummary(
                id: ticket.id,
                title: ticket.title,
                status: ticket.status,
                resolution: ticket.resolution,
                created: ticket.created,
                submitter: ticket.submitter,
                labels: ticket.labels + [label],
                assignees: ticket.assignees
            )
            tickets[index] = updated
        }

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.labelTicketMutation,
                variables: [
                    "trackerId": trackerId,
                    "ticketId": ticket.id,
                    "labelId": label.id
                ],
                responseType: LabelMutationResponse.self
            )
        } catch {
            tickets = original
            self.error = error.userFacingMessage
        }

        isPerformingAction = false
    }

    func unlabelTicket(_ ticket: TicketSummary, label: TicketLabel) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        error = nil

        let original = tickets
        if let index = tickets.firstIndex(where: { $0.id == ticket.id }) {
            let filtered = ticket.labels.filter { $0.id != label.id }
            let updated = TicketSummary(
                id: ticket.id,
                title: ticket.title,
                status: ticket.status,
                resolution: ticket.resolution,
                created: ticket.created,
                submitter: ticket.submitter,
                labels: filtered,
                assignees: ticket.assignees
            )
            tickets[index] = updated
        }

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.unlabelTicketMutation,
                variables: [
                    "trackerId": trackerId,
                    "ticketId": ticket.id,
                    "labelId": label.id
                ],
                responseType: LabelMutationResponse.self
            )
        } catch {
            tickets = original
            self.error = error.userFacingMessage
        }

        isPerformingAction = false
    }

    func ticket(withId ticketId: Int) -> TicketSummary? {
        tickets.first(where: { $0.id == ticketId })
    }

    // MARK: - Private

    private func performStatusUpdate(ticket: TicketSummary, input: [String: any Sendable]) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        error = nil

        do {
            let variables: [String: any Sendable] = [
                "trackerId": trackerId,
                "ticketId": ticket.id,
                "input": input
            ]
            let result = try await client.execute(
                service: .todo,
                query: Self.updateStatusMutation,
                variables: variables,
                responseType: UpdateStatusResponse.self
            )
            _ = result.updateTicketStatus
            if let index = tickets.firstIndex(where: { $0.id == ticket.id }) {
                tickets[index] = updatedTicket(from: ticket, input: input)
            }
        } catch {
            self.error = error.userFacingMessage
        }

        isPerformingAction = false
    }

    private func fetchPage(cursor: String?) async throws -> TicketsPage {
        var variables: [String: any Sendable] = ["rid": trackerRid]
        if let cursor {
            variables["cursor"] = cursor
        }
        let result = try await client.execute(
            service: .todo,
            query: Self.query,
            variables: variables,
            responseType: TrackerTicketsResponse.self
        )
        return result.tracker.tickets
    }

    private struct SubmitTicketResponse: Decodable, Sendable {
        let submitTicket: TicketSummary
    }

    private static func matchesAssignee(_ entity: Entity, user: User) -> Bool {
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

    private func updatedTicket(from ticket: TicketSummary, input: [String: any Sendable]) -> TicketSummary {
        let updatedStatus = (input["status"] as? String).flatMap(TicketStatus.init(rawValue:)) ?? ticket.status
        let updatedResolution = (input["resolution"] as? String).flatMap(TicketResolution.init(rawValue:))

        return TicketSummary(
            id: ticket.id,
            title: ticket.title,
            status: updatedStatus,
            resolution: updatedStatus == .resolved ? updatedResolution : nil,
            created: ticket.created,
            submitter: ticket.submitter,
            labels: ticket.labels,
            assignees: ticket.assignees
        )
    }

    private func persistFilterState() {
        TicketSavedFilterStore.saveCurrentState(currentFilterState, for: trackerRid, defaults: defaults)
        activeSavedFilterID = savedFilters.first(where: { $0.state == currentFilterState })?.id
    }

    static func filterTickets(
        _ tickets: [TicketSummary],
        state: TicketListFilterState,
        query: String
    ) -> [TicketSummary] {
        let statusFiltered: [TicketSummary]
        switch state.status {
        case .open:
            statusFiltered = tickets.filter { $0.status.isOpen }
        case .resolved:
            statusFiltered = tickets.filter { !$0.status.isOpen }
        case .all:
            statusFiltered = tickets
        }

        let labelFiltered: [TicketSummary]
        if state.labelIDs.isEmpty {
            labelFiltered = statusFiltered
        } else {
            let selectedLabelIDs = Set(state.labelIDs)
            labelFiltered = statusFiltered.filter { ticket in
                !selectedLabelIDs.isDisjoint(with: ticket.labels.map(\.id))
            }
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return labelFiltered }
        return labelFiltered.filter {
            String($0.id).contains(q) ||
            $0.title.lowercased().contains(q) ||
            $0.submitter.canonicalName.lowercased().contains(q) ||
            $0.labels.contains { $0.name.lowercased().contains(q) }
        }
    }
}
