import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct TrackersResponse: Decodable, Sendable {
    let trackers: TrackersPage
}

private struct TrackersPage: Decodable, Sendable {
    let results: [TrackerSummary]
    let cursor: String?
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

    // MARK: - Public API

    func loadTrackers() async {
        isLoading = true
        error = nil
        cursor = nil
        hasMore = true

        do {
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
            trackers.insert(tracker, at: 0)
            return tracker
        } catch {
            self.error = trackerCreationErrorMessage(for: error)
            return nil
        }
    }

    // MARK: - Private

    private func fetchPage(cursor: String?) async throws -> TrackersPage {
        var variables: [String: any Sendable] = [:]
        if let cursor {
            variables["cursor"] = cursor
        }
        let result = try await client.execute(
            service: .todo,
            query: Self.query,
            variables: variables.isEmpty ? nil : variables,
            responseType: TrackersResponse.self
        )
        return result.trackers
    }

    private struct CreateTrackerResponse: Decodable, Sendable {
        let createTracker: TrackerSummary
    }

    private func trackerCreationErrorMessage(for error: Error) -> String {
        "Couldn’t create the tracker. \(error.userFacingMessage)"
    }
}
