import Foundation

// MARK: - Response types

private struct JobDetailResponse: Decodable, Sendable {
    let job: JobDetail
}

private struct CancelResponse: Decodable, Sendable {
    let cancel: CancelResult
}

private struct CancelResult: Decodable, Sendable {
    let id: Int
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
final class BuildDetailViewModel {

    let jobId: Int
    private let client: SRHTClient

    private(set) var job: JobDetail?
    private(set) var isLoading = false
    private(set) var taskLogs: [String: String] = [:]
    private(set) var loadingTaskLogs: Set<String> = []
    private(set) var isCancelling = false
    private(set) var isRebuilding = false
    private(set) var isSubmittingEditedBuild = false
    var error: String?

    init(jobId: Int, client: SRHTClient) {
        self.jobId = jobId
        self.client = client
    }

    // MARK: - Queries

    private static let detailQuery = """
    query job($id: Int!) {
        job(id: $id) {
            id
            created
            updated
            status
            note
            tags
            visibility
            image
            manifest
            tasks { name status log { fullURL } }
            log { fullURL }
            owner { canonicalName }
        }
    }
    """

    private static let cancelMutation = """
    mutation cancel($id: Int!) {
        cancel(jobId: $id) {
            id
        }
    }
    """

    private static let submitMutation = """
    mutation submit($manifest: String!, $tags: [String!], $note: String, $visibility: Visibility) {
        submit(manifest: $manifest, tags: $tags, note: $note, visibility: $visibility) {
            id
        }
    }
    """

    private static let editableSubmitMutation = """
    mutation submit($manifest: String!, $tags: [String!], $note: String, $secrets: Boolean, $execute: Boolean, $visibility: Visibility) {
        submit(manifest: $manifest, tags: $tags, note: $note, secrets: $secrets, execute: $execute, visibility: $visibility) {
            id
        }
    }
    """

    // MARK: - Public API

    func loadJob() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            let result = try await client.execute(
                service: .builds,
                query: Self.detailQuery,
                variables: ["id": jobId],
                responseType: JobDetailResponse.self
            )
            var loadedJob = result.job
            loadedJob.tasks = loadedJob.tasks.enumerated().map { index, task in
                task.withOrdinal(index)
            }
            job = loadedJob
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadTaskLog(task: BuildTask) async {
        let cacheKey = task.logCacheKey
        guard let log = task.log,
              let logURL = URL(string: log.fullURL),
              !loadingTaskLogs.contains(cacheKey),
              taskLogs[cacheKey] == nil else { return }
        loadingTaskLogs.insert(cacheKey)

        do {
            taskLogs[cacheKey] = try await client.fetchText(url: logURL)
        } catch {
            self.error = error.localizedDescription
        }

        loadingTaskLogs.remove(cacheKey)
    }

    func cancelJob() async {
        guard let job, job.status.isCancellable, !isCancelling else { return }
        isCancelling = true
        error = nil

        do {
            _ = try await client.execute(
                service: .builds,
                query: Self.cancelMutation,
                variables: ["id": jobId],
                responseType: CancelResponse.self
            )
            // Reload job to get updated status.
            await loadJob()
        } catch {
            self.error = error.localizedDescription
        }

        isCancelling = false
    }

    func rebuildJob() async -> Int? {
        guard let job, let manifest = job.manifest, !manifest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isRebuilding else {
            return nil
        }

        isRebuilding = true
        error = nil
        defer { isRebuilding = false }

        var variables: [String: any Sendable] = [
            "manifest": manifest.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        if !job.tags.isEmpty {
            variables["tags"] = job.tags
        }
        if let note = job.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            variables["note"] = note.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let visibility = job.visibility {
            variables["visibility"] = visibility.rawValue
        }

        do {
            let result = try await client.execute(
                service: .builds,
                query: Self.submitMutation,
                variables: variables,
                responseType: SubmitJobResponse.self
            )
            return result.submit.id
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func submitBuild(
        manifest: String,
        tags: [String],
        note: String,
        secrets: Bool,
        execute: Bool,
        visibility: Visibility
    ) async -> Int? {
        guard !isSubmittingEditedBuild else { return nil }

        let trimmedManifest = manifest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedManifest.isEmpty else {
            error = "Paste a build manifest."
            return nil
        }

        isSubmittingEditedBuild = true
        error = nil
        defer { isSubmittingEditedBuild = false }

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
                query: Self.editableSubmitMutation,
                variables: variables,
                responseType: SubmitJobResponse.self
            )
            return result.submit.id
        } catch {
            self.error = "Couldn’t submit the build. \(error.localizedDescription)"
            return nil
        }
    }
}
