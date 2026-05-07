import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct TrackersResponse: Decodable, Sendable {
    let trackers: TrackersPage
}

private struct TrackersPage: Decodable, Sendable {
    let results: [TrackerSummary]
    let cursor: String?
}

private struct UpdateTrackerResponse: Decodable, Sendable {
    let updateTracker: TrackerSummary
}

private struct DeleteTrackerResponse: Decodable, Sendable {
    let deleteTracker: DeletedTracker
}

private struct DeletedTracker: Decodable, Sendable {
    let id: Int
}

// MARK: - View Model

@Observable
@MainActor
final class TrackerListViewModel {

    private(set) var trackers: [TrackerSummary] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isCreatingTracker = false
    var error: String?
    var searchText = ""

    private var cursor: String?
    private var hasMore = true
    private let client: SRHTClient

    init(client: SRHTClient) {
        self.client = client
    }

    var filteredTrackers: [TrackerSummary] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return trackers }
        return trackers.filter {
            $0.name.lowercased().contains(q) ||
            ($0.description?.lowercased().contains(q) == true) ||
            $0.owner.canonicalName.lowercased().contains(q)
        }
    }

    // MARK: - Query

    private static let query = """
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

    private static let createTrackerMutation = """
    mutation createTracker($name: String!, $visibility: Visibility!, $description: String) {
        createTracker(name: $name, visibility: $visibility, description: $description) {
            id
            rid
            name
            description
            visibility
            updated
            owner { canonicalName }
        }
    }
    """

    private static let updateTrackerMutation = """
    mutation updateTracker($id: Int!, $input: TrackerInput!) {
        updateTracker(id: $id, input: $input) {
            id
            rid
            name
            description
            visibility
            updated
            owner { canonicalName }
        }
    }
    """

    private static let deleteTrackerMutation = """
    mutation deleteTracker($id: Int!) {
        deleteTracker(id: $id) {
            id
        }
    }
    """

    // MARK: - Public API

    func loadTrackers() async {
        isLoading = true
        error = nil
        cursor = nil
        hasMore = true

        do {
            if trackers.isEmpty, let cached = try? await fetchPage(cursor: nil, policy: .cacheOnly) {
                trackers = cached.results
                cursor = cached.cursor
                hasMore = cached.cursor != nil
                isLoading = false
            }
            let page = try await fetchPage(cursor: nil)
            trackers = page.results
            cursor = page.cursor
            hasMore = page.cursor != nil
        } catch {
            self.error = error.userFacingMessage
        }

        isLoading = false
    }

    func loadMoreIfNeeded(currentItem: TrackerSummary) async {
        guard let last = trackers.last,
              last.id == currentItem.id,
              hasMore,
              !isLoadingMore else {
            return
        }

        isLoadingMore = true

        do {
            let page = try await fetchPage(cursor: cursor)
            trackers.append(contentsOf: page.results)
            cursor = page.cursor
            hasMore = page.cursor != nil
        } catch {
            self.error = error.userFacingMessage
        }

        isLoadingMore = false
    }

    func createTracker(name: String, description: String, visibility: Visibility) async -> TrackerSummary? {
        guard !isCreatingTracker else { return nil }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            error = "Enter a tracker name."
            return nil
        }

        isCreatingTracker = true
        error = nil
        defer { isCreatingTracker = false }

        var variables: [String: any Sendable] = [
            "name": trimmedName,
            "visibility": visibility.rawValue
        ]
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDescription.isEmpty {
            variables["description"] = trimmedDescription
        }

        do {
            let result = try await client.execute(
                service: .todo,
                query: Self.createTrackerMutation,
                variables: variables,
                responseType: CreateTrackerResponse.self
            )
            let tracker = result.createTracker
            await invalidateTrackerCaches()
            trackers.insert(tracker, at: 0)
            return tracker
        } catch {
            self.error = trackerCreationErrorMessage(for: error)
            return nil
        }
    }

    func updateTracker(
        _ tracker: TrackerSummary,
        name: String,
        description: String,
        visibility: Visibility
    ) async -> TrackerSummary? {
        guard !isCreatingTracker else { return nil }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            error = "Enter a tracker name."
            return nil
        }

        isCreatingTracker = true
        error = nil
        defer { isCreatingTracker = false }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let input: [String: any Sendable] = [
            "name": trimmedName,
            "description": trimmedDescription.isEmpty ? "" : trimmedDescription,
            "visibility": visibility.rawValue
        ]

        do {
            let result = try await client.execute(
                service: .todo,
                query: Self.updateTrackerMutation,
                variables: [
                    "id": tracker.id,
                    "input": input
                ],
                responseType: UpdateTrackerResponse.self
            )
            await invalidateTrackerCaches()
            applyTrackerUpdate(result.updateTracker)
            return result.updateTracker
        } catch {
            self.error = "Couldn’t update the tracker. \(error.userFacingMessage)"
            return nil
        }
    }

    func deleteTracker(_ tracker: TrackerSummary) async -> Bool {
        guard !isCreatingTracker else { return false }

        isCreatingTracker = true
        error = nil
        defer { isCreatingTracker = false }

        do {
            _ = try await client.execute(
                service: .todo,
                query: Self.deleteTrackerMutation,
                variables: ["id": tracker.id],
                responseType: DeleteTrackerResponse.self
            )
            await invalidateTrackerCaches()
            trackers.removeAll { $0.id == tracker.id }
            await loadTrackers()
            return true
        } catch {
            self.error = "Couldn’t delete the tracker. \(error.userFacingMessage)"
            return false
        }
    }

    func applyTrackerUpdate(_ tracker: TrackerSummary) {
        if let index = trackers.firstIndex(where: { $0.id == tracker.id }) {
            trackers[index] = tracker
        } else {
            trackers.insert(tracker, at: 0)
        }
    }

    func applyTrackerDeletion(_ tracker: TrackerSummary) {
        trackers.removeAll { $0.id == tracker.id }
    }

    // MARK: - Private

    private func fetchPage(cursor: String?, policy: CachePolicy = .cacheFirstThenRefresh) async throws -> TrackersPage {
        var variables: [String: any Sendable] = [:]
        if let cursor {
            variables["cursor"] = cursor
        }
        let cached = try await client.executeCached(
            service: .todo,
            query: Self.query,
            variables: variables.isEmpty ? nil : variables,
            responseType: TrackersResponse.self,
            cacheKey: APICacheKeys.trackers(cursor: cursor),
            resourceType: .ticketList,
            ttl: APICacheTTLs.ticketList,
            policy: policy
        )
        return cached.value.trackers
    }

    private struct CreateTrackerResponse: Decodable, Sendable {
        let createTracker: TrackerSummary
    }

    private func trackerCreationErrorMessage(for error: Error) -> String {
        "Couldn’t create the tracker. \(error.userFacingMessage)"
    }

    private func invalidateTrackerCaches() async {
        await client.invalidateCache(prefix: APICacheKeys.prefix(SRHTService.todo.rawValue, "trackers"))
        await client.invalidateCache(prefix: APICacheKeys.prefix(SRHTService.todo.rawValue, "tracker"))
        await client.invalidateCache(prefix: APICacheKeys.prefix("home"))
    }
}
