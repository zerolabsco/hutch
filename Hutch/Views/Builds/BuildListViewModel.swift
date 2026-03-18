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

// MARK: - View Model

@Observable
@MainActor
final class BuildListViewModel {

    private(set) var jobs: [JobSummary] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isRefreshing = false
    private(set) var isSubmitting = false
    var error: String?

    private var cursor: String?
    private var hasMore = true
    private let client: SRHTClient

    private static let cacheKey = "builds.jobs"

    init(client: SRHTClient) {
        self.client = client
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
                self.error = error.localizedDescription
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
            self.error = error.localizedDescription
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
            self.error = "Couldn’t submit the build. \(error.localizedDescription)"
            return nil
        }
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
}
