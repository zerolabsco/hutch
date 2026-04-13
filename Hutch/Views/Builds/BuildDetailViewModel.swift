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
    private static let autoRefreshInterval: Duration = .seconds(5)

    let jobId: Int
    private let client: SRHTClient

    private var autoRefreshTask: Task<Void, Never>?
    private(set) var job: JobDetail?
    private(set) var isLoading = false
    private(set) var buildLogText: String?
    private(set) var isLoadingBuildLog = false
    private(set) var taskLogs: [String: String] = [:]
    private(set) var loadingTaskLogs: Set<String> = []
    private(set) var failedTaskLogs: Set<String> = []
    private var taskLogRetryCounts: [String: Int] = [:]
    private(set) var isCancelling = false
    private(set) var isRebuilding = false
    private(set) var isSubmittingEditedBuild = false
    var error: String?
    /// Transient error shown for action failures (cancel, rebuild, submit).
    /// Separate from `error` so auto-refresh doesn't immediately clear it.
    private(set) var actionError: String?
    private var actionErrorDismissTask: Task<Void, Never>?

    init(jobId: Int, client: SRHTClient) {
        self.jobId = jobId
        self.client = client
    }

    func dismissActionError() {
        actionError = nil
        actionErrorDismissTask?.cancel()
        actionErrorDismissTask = nil
    }

    private func setActionError(_ message: String) {
        actionError = message
        actionErrorDismissTask?.cancel()
        actionErrorDismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            actionError = nil
        }
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
            if job != loadedJob {
                job = loadedJob
            }

            if loadedJob.status.isTerminal {
                stopAutoRefresh()
            }
        } catch {
            self.error = error.userFacingMessage
        }

        isLoading = false
    }

    func loadTaskLog(task: BuildTask) async {
        let cacheKey = task.logCacheKey
        let jobIsTerminal = job?.status.isTerminal ?? false

        // Task-specific logs are only fetched after the job reaches a terminal
        // state. While the build is active, the UI shows the shared live build log.
        guard let log = task.log,
              let logURL = URL(string: log.fullURL),
              !loadingTaskLogs.contains(cacheKey) else { return }
        guard jobIsTerminal else { return }
        if jobIsTerminal, taskLogs[cacheKey] != nil { return }
        failedTaskLogs.remove(cacheKey)
        loadingTaskLogs.insert(cacheKey)

        do {
            taskLogs[cacheKey] = try await client.fetchText(url: logURL)
            failedTaskLogs.remove(cacheKey)
        } catch {
            failedTaskLogs.insert(cacheKey)
            self.error = error.userFacingMessage
        }

        loadingTaskLogs.remove(cacheKey)
    }

    func loadBuildLog() async {
        guard let log = job?.log,
              let logURL = URL(string: log.fullURL),
              !isLoadingBuildLog else { return }

        let jobIsTerminal = job?.status.isTerminal ?? false
        if jobIsTerminal, buildLogText != nil { return }

        isLoadingBuildLog = true

        do {
            buildLogText = try await client.fetchText(url: logURL)
        } catch {
            self.error = error.userFacingMessage
        }

        isLoadingBuildLog = false
    }

    func retryTaskLog(task: BuildTask) async {
        let cacheKey = task.logCacheKey
        failedTaskLogs.remove(cacheKey)
        taskLogRetryCounts[cacheKey, default: 0] += 1
        await loadTaskLog(task: task)
    }

    func displayedLogText(for task: BuildTask?) -> String? {
        guard let task else { return nil }
        guard let job else { return nil }

        if !job.status.isTerminal {
            return buildLogText
        }

        return taskLogs[task.logCacheKey] ?? buildLogText
    }

    func isShowingBuildLogFallback(for task: BuildTask?) -> Bool {
        guard let task, let job else { return false }
        if !job.status.isTerminal {
            return buildLogText != nil
        }

        return taskLogs[task.logCacheKey] == nil && buildLogText != nil
    }

    func taskLogTrigger(for task: BuildTask?) -> String? {
        guard let task, let logURL = task.log?.fullURL else { return nil }
        let retryCount = taskLogRetryCounts[task.logCacheKey, default: 0]
        let isTerminal = job?.status.isTerminal ?? false
        return "\(logURL)#\(retryCount)#\(isTerminal)"
    }

    func cancelJob() async {
        guard let job, job.status.isCancellable, !isCancelling else { return }
        let originalJob = job
        isCancelling = true

        // Optimistic update: show cancelled status immediately.
        self.job = JobDetail(
            id: job.id, created: job.created, updated: job.updated,
            status: .cancelled, note: job.note, tags: job.tags,
            visibility: job.visibility, image: job.image,
            manifest: job.manifest, tasks: job.tasks,
            log: job.log, owner: job.owner
        )
        stopAutoRefresh()

        do {
            _ = try await client.execute(
                service: .builds,
                query: Self.cancelMutation,
                variables: ["id": jobId],
                responseType: CancelResponse.self
            )
            await loadJob()
        } catch {
            // Revert optimistic update on failure.
            self.job = originalJob
            if !originalJob.status.isTerminal {
                startAutoRefresh()
            }
            setActionError("Couldn't cancel build. \(error.userFacingMessage)")
        }

        isCancelling = false
    }

    func rebuildJob() async -> Int? {
        guard let job, let manifest = job.manifest, !manifest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isRebuilding else {
            return nil
        }

        isRebuilding = true
        dismissActionError()
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
            setActionError("Couldn't rebuild. \(error.userFacingMessage)")
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
            setActionError("Paste a build manifest.")
            return nil
        }

        isSubmittingEditedBuild = true
        dismissActionError()
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
            setActionError("Couldn’t submit the build. \(error.userFacingMessage)")
            return nil
        }
    }

    func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }
        guard shouldAutoRefresh else { return }

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.autoRefreshInterval)
                } catch {
                    break
                }

                guard let self else { return }
                await self.performAutoRefreshTick()
            }
        }
    }

    func stopAutoRefresh() {
        guard let autoRefreshTask else { return }

        autoRefreshTask.cancel()
        self.autoRefreshTask = nil
    }

    private var shouldAutoRefresh: Bool {
        guard let job else { return true }
        return !job.status.isTerminal
    }

    private func performAutoRefreshTick() async {
        guard !Task.isCancelled, shouldAutoRefresh, !isLoading else {
            if !shouldAutoRefresh {
                stopAutoRefresh()
            }
            return
        }

        await loadJob()
        await loadBuildLog()
    }
}
