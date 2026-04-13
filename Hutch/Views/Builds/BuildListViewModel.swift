import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct JobsResponse: Decodable, Sendable {
    let jobs: JobsPage
}

private struct JobsPage: Decodable, Sendable {
    let results: [JobSummary]
    let cursor: String?
}

private struct SubmitJobResponse: Decodable, Sendable {
    let submit: SubmittedJob
}

private struct SubmittedJob: Decodable, Sendable {
    let id: Int
}

enum BuildListFilter: String, CaseIterable, Sendable {
    case attention = "Attention"
    case active = "Active"
    case all = "All"
}

enum AutoRefreshInterval: Int, CaseIterable, Sendable {
    case off = 0
    case fiveSeconds = 5
    case tenSeconds = 10

    var label: String {
        switch self {
        case .off: "Off"
        case .fiveSeconds: "5s"
        case .tenSeconds: "10s"
        }
    }
}

// MARK: - View Model

@Observable
@MainActor
final class BuildListViewModel {
    private static let searchHistoryScopeID = "builds"

    private(set) var jobs: [JobSummary] = []
    private(set) var recentSearches: [ScopedSearchHistoryEntry]
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isRefreshing = false
    private(set) var isSubmitting = false
    var error: String?
    var filter: BuildListFilter = .attention
    var searchText = ""
    var repoFilter: String = "" {
        didSet { if repoFilter != oldValue { repoFilterDidChange() } }
    }

    private var cursor: String?
    private var hasMore = true
    private let client: SRHTClient
    private let defaults: UserDefaults
    private var refreshTask: Task<Void, Never>?
    private var isAutoRefreshing = false

    private static let cacheKey = "builds.jobs"

    init(client: SRHTClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        self.recentSearches = ScopedSearchHistoryStore.load(
            scopeID: Self.searchHistoryScopeID,
            defaults: defaults
        )
    }

    /// Unique tags across all loaded jobs, sorted alphabetically.
    var availableTags: [String] {
        let allTags = Set(jobs.flatMap(\.tags))
        return allTags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var filteredJobs: [JobSummary] {
        var result = Self.filterJobs(jobs, filter: filter)

        if !repoFilter.isEmpty {
            result = result.filter { $0.tags.contains(repoFilter) }
        }

        return Self.searchJobs(result, matching: searchText)
    }

    // MARK: - Auto-Refresh

    func startAutoRefresh(interval: AutoRefreshInterval) {
        stopAutoRefresh()
        guard interval != .off else { return }
        let seconds = interval.rawValue
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                guard !self.isAutoRefreshing, !self.isLoading, !self.isRefreshing else { continue }
                self.isAutoRefreshing = true
                await self.loadJobs()
                self.isAutoRefreshing = false
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func repoFilterDidChange() {
        // Reset to empty if the selected tag no longer exists
        if !repoFilter.isEmpty, !availableTags.contains(repoFilter) {
            repoFilter = ""
        }
    }

    // MARK: - Query

    private static let query = """
    query jobs($cursor: Cursor) {
        jobs(cursor: $cursor) {
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
            }
            cursor
        }
    }
    """

    private static let submitMutation = """
    mutation submit($manifest: String!, $tags: [String!], $note: String, $secrets: Boolean, $execute: Boolean, $visibility: Visibility) {
        submit(manifest: $manifest, tags: $tags, note: $note, secrets: $secrets, execute: $execute, visibility: $visibility) {
            id
        }
    }
    """

    private static let cancelMutation = """
    mutation cancel($id: Int!) {
        cancel(jobId: $id) { id }
    }
    """

    // MARK: - Public API

    /// Fetch the first page of jobs. Shows cached data instantly if available,
    /// then refreshes from the network in the background.
    func loadJobs() async {
        // Show cached data immediately on first load
        if jobs.isEmpty {
            loadFromCache()
        }

        if jobs.isEmpty {
            isLoading = true
        } else {
            isRefreshing = true
        }
        error = nil
        cursor = nil
        hasMore = true

        do {
            let page = try await fetchPage(cursor: nil, useCache: true)
            jobs = page.results
            cursor = page.cursor
            hasMore = page.cursor != nil
        } catch {
            if jobs.isEmpty {
                self.error = error.userFacingMessage
            }
        }

        isLoading = false
        isRefreshing = false
    }

    func loadMoreIfNeeded(currentItem: JobSummary) async {
        guard let last = jobs.last,
              last.id == currentItem.id,
              hasMore,
              !isLoadingMore else {
            return
        }

        isLoadingMore = true

        do {
            let page = try await fetchPage(cursor: cursor, useCache: false)
            jobs.append(contentsOf: page.results)
            cursor = page.cursor
            hasMore = page.cursor != nil
        } catch {
            self.error = error.userFacingMessage
        }

        isLoadingMore = false
    }

    func submitBuild(
        manifest: String,
        tags: [String],
        note: String,
        secrets: Bool,
        execute: Bool,
        visibility: Visibility
    ) async -> Int? {
        guard !isSubmitting else { return nil }

        let trimmedManifest = manifest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedManifest.isEmpty else {
            error = "Paste a build manifest."
            return nil
        }

        isSubmitting = true
        error = nil
        defer { isSubmitting = false }

        var variables: [String: any Sendable] = [
            "manifest": trimmedManifest,
            "secrets": secrets,
            "execute": execute,
            "visibility": visibility.rawValue
        ]
        if !tags.isEmpty {
            variables["tags"] = tags
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            variables["note"] = trimmedNote
        }

        do {
            let result = try await client.execute(
                service: .builds,
                query: Self.submitMutation,
                variables: variables,
                responseType: SubmitJobResponse.self
            )
            await loadJobs()
            return result.submit.id
        } catch {
            self.error = "Couldn’t submit the build. \(error.userFacingMessage)"
            return nil
        }
    }

    func cancelJob(_ job: JobSummary) async {
        guard job.status.isCancellable else { return }

        do {
            _ = try await client.execute(
                service: .builds,
                query: Self.cancelMutation,
                variables: ["id": job.id],
                responseType: CancelResponse.self
            )
            if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                let updated = JobSummary(
                    id: job.id,
                    created: job.created,
                    updated: job.updated,
                    status: .cancelled,
                    note: job.note,
                    tags: job.tags,
                    visibility: job.visibility,
                    image: job.image,
                    tasks: job.tasks
                )
                jobs[index] = updated
            }
        } catch {
            self.error = error.userFacingMessage
        }
    }

    func recordRecentSearch(_ query: String) {
        ScopedSearchHistoryStore.record(
            query: query,
            scopeID: Self.searchHistoryScopeID,
            defaults: defaults
        )
        recentSearches = ScopedSearchHistoryStore.load(
            scopeID: Self.searchHistoryScopeID,
            defaults: defaults
        )
    }

    func clearRecentSearches() {
        ScopedSearchHistoryStore.clear(
            scopeID: Self.searchHistoryScopeID,
            defaults: defaults
        )
        recentSearches = []
    }

    // MARK: - Private

    private func fetchPage(cursor: String?, useCache: Bool) async throws -> JobsPage {
        var variables: [String: any Sendable] = [:]
        if let cursor {
            variables["cursor"] = cursor
        }

        if useCache && cursor == nil {
            let result = try await client.executeAndCache(
                service: .builds,
                query: Self.query,
                variables: variables.isEmpty ? nil : variables,
                responseType: JobsResponse.self,
                cacheKey: Self.cacheKey
            )
            return result.jobs
        } else {
            let result = try await client.execute(
                service: .builds,
                query: Self.query,
                variables: variables.isEmpty ? nil : variables,
                responseType: JobsResponse.self
            )
            return result.jobs
        }
    }

    private func loadFromCache() {
        guard let data = client.responseCache.get(forKey: Self.cacheKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .srhtFlexible
        if let response = try? decoder.decode(
            GraphQLResponse<JobsResponse>.self,
            from: data
        ), let page = response.data?.jobs {
            jobs = page.results
            cursor = page.cursor
            hasMore = page.cursor != nil
        }
    }

    private struct CancelResponse: Decodable, Sendable {
        struct CancelResult: Decodable, Sendable {
            let id: Int
        }

        let cancel: CancelResult
    }

    nonisolated static func filterJobs(_ jobs: [JobSummary], filter: BuildListFilter) -> [JobSummary] {
        jobs.filter { job in
            switch filter {
            case .attention:
                switch job.status {
                case .failed, .timeout, .running, .queued, .pending:
                    return true
                case .success, .cancelled:
                    return false
                }
            case .active:
                switch job.status {
                case .running, .queued, .pending:
                    return true
                case .success, .failed, .cancelled, .timeout:
                    return false
                }
            case .all:
                return true
            }
        }
    }

    nonisolated static func searchJobs(_ jobs: [JobSummary], matching query: String) -> [JobSummary] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return jobs }

        return jobs.filter {
            String($0.id).contains(normalizedQuery) ||
            $0.status.rawValue.lowercased().contains(normalizedQuery) ||
            $0.tags.contains { $0.lowercased().contains(normalizedQuery) } ||
            ($0.note?.lowercased().contains(normalizedQuery) == true) ||
            ($0.image?.lowercased().contains(normalizedQuery) == true)
        }
    }
}
