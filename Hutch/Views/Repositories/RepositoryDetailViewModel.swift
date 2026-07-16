import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct LogResponse: Decodable, Sendable {
    let repository: LogRepository?
}

private struct LogRepository: Decodable, Sendable {
    let log: LogPage
}

private struct LogPage: Decodable, Sendable {
    let results: [CommitSummary]
    let cursor: String?
}

private struct RefsResponse: Decodable, Sendable {
    let repository: RefsRepository?
}

private struct RefsRepository: Decodable, Sendable {
    let references: RefsPage
}

private struct RefsPage: Decodable, Sendable {
    let results: [ReferencePayload]
    let cursor: String?
}

/// Decodes a single reference including the optional follow object for date extraction.
private struct ReferencePayload: Decodable, Sendable {
    let name: String
    let target: String?
    let follow: ReferenceFollow?

    func toDetail() -> ReferenceDetail {
        // Branches and lightweight tags follow to a Commit (author.time).
        // Annotated tags follow to a Tag object (tagger.time).
        let date = follow?.author?.time ?? follow?.tagger?.time
        return ReferenceDetail(name: name, target: target, date: date)
    }
}

private struct ReferenceFollow: Decodable, Sendable {
    let author: ReferenceSignature?
    let tagger: ReferenceSignature?
}

private struct ReferenceSignature: Decodable, Sendable {
    let time: Date
}

private struct ReadmeResponse: Decodable, Sendable {
    let repository: ReadmeRepository?
}

private struct ReadmeRepository: Decodable, Sendable {
    let readme: String?
}

private struct PathResponse: Decodable, Sendable {
    let repository: PathRepository?
}

private struct PathRepository: Decodable, Sendable {
    let readme: PathEntry?
}

private struct PathEntry: Decodable, Sendable {
    let object: PathObject?
}

private struct PathObject: Decodable, Sendable {
    let text: String?
}

private struct UploadArtifactResponse: Decodable, Sendable {
    let uploadArtifact: ArtifactInfo
}

private struct DeleteArtifactResponse: Decodable, Sendable {
    /// Nullable in the schema: sr.ht returns null when there was no artifact to
    /// remove, which is still a success from the caller's point of view.
    let deleteArtifact: ArtifactIDPayload?
}

private struct ArtifactIDPayload: Decodable, Sendable {
    let id: Int
}

private struct ArtifactsResponse: Decodable, Sendable {
    let repository: ArtifactsRepository?
}

private struct ArtifactsRepository: Decodable, Sendable {
    let references: ArtifactRefsPage
}

private struct ArtifactRefsPage: Decodable, Sendable {
    let results: [ArtifactRef]
    let cursor: String?
}

private struct ArtifactRef: Decodable, Sendable {
    let name: String
    let artifacts: ArtifactPage
}

// MARK: - View Model

@Observable
@MainActor
final class RepositoryDetailViewModel {

    enum Tab: String, CaseIterable {
        case summary = "Summary"
        case tree = "Tree"
        case log = "Log"
        case refs = "Refs"
        case artifacts = "Artifacts"
    }

    let repository: RepositorySummary
    private var service: SRHTService { repository.service }
    private let client: SRHTClient

    // MARK: - Commit log state

    private(set) var commits: [CommitSummary] = []
    private(set) var isLoadingCommits = false
    private(set) var isLoadingMoreCommits = false
    private var commitCursor: String?
    private var hasMoreCommits = true

    // MARK: - References state

    private(set) var branches: [ReferenceDetail] = []
    private(set) var tags: [ReferenceDetail] = []
    private(set) var isLoadingRefs = false

    // MARK: - README state

    enum ReadmeContent {
        case html(String)
        case markdown(String)
        case org(String)
        case plainText(String)
    }

    private(set) var readmeContent: ReadmeContent?
    private(set) var readmePath: String?
    private(set) var isLoadingReadme = false
    private(set) var readmeLoaded = false
    private(set) var readmeCacheMetadata: CacheEntryMetadata?

    // MARK: - Artifacts state

    private(set) var referenceArtifacts: [ReferenceWithArtifacts] = []
    private(set) var isLoadingArtifacts = false
    private(set) var isMutatingArtifact = false

    // MARK: - Error

    var error: String?

    init(repository: RepositorySummary, client: SRHTClient) {
        self.repository = repository
        self.client = client
    }

    // MARK: - Commit log

    private static let logQuery = """
    query repoLog($rid: ID!, $cursor: Cursor) {
        repository(rid: $rid) {
            log(cursor: $cursor) {
                results {
                    id
                    shortId
                    author { name email time }
                    message
                }
                cursor
            }
        }
    }
    """

    func loadCommits() async {
        guard !isLoadingCommits else { return }
        isLoadingCommits = true
        error = nil
        commitCursor = nil
        hasMoreCommits = true

        do {
            let page = try await fetchCommitPage(cursor: nil)
            commits = page.results
            commitCursor = page.cursor
            hasMoreCommits = page.cursor != nil
        } catch {
            self.error = error.userFacingMessage
        }

        isLoadingCommits = false
    }

    func loadMoreCommitsIfNeeded(currentItem: CommitSummary) async {
        guard let last = commits.last,
              last.id == currentItem.id,
              hasMoreCommits,
              !isLoadingMoreCommits else {
            return
        }

        isLoadingMoreCommits = true

        do {
            let page = try await fetchCommitPage(cursor: commitCursor)
            commits.append(contentsOf: page.results)
            commitCursor = page.cursor
            hasMoreCommits = page.cursor != nil
        } catch {
            self.error = error.userFacingMessage
        }

        isLoadingMoreCommits = false
    }

    private func fetchCommitPage(cursor: String?) async throws -> LogPage {
        var variables: [String: any Sendable] = ["rid": repository.rid]
        if let cursor {
            variables["cursor"] = cursor
        }
        let result: LogResponse
        do {
            result = try await client.execute(
                service: service,
                query: Self.logQuery,
                variables: variables,
                responseType: LogResponse.self
            )
        } catch {
            if isEmptyRepositoryError(error) {
                return LogPage(results: [], cursor: nil)
            }
            throw error
        }
        guard let repo = result.repository else {
            return LogPage(results: [], cursor: nil)
        }
        return repo.log
    }

    // MARK: - References

    private static let refsQuery = """
    query refs($rid: ID!, $cursor: Cursor) {
        repository(rid: $rid) {
            references(cursor: $cursor) {
                results {
                    name
                    target
                    follow {
                        ... on Commit { author { time } }
                        ... on Tag { tagger { time } }
                    }
                }
                cursor
            }
        }
    }
    """

    func loadReferences() async {
        guard !isLoadingRefs else { return }
        isLoadingRefs = true
        error = nil

        do {
            let allRefs = try await fetchAllReferences()
            branches = allRefs
                .filter { $0.name.hasPrefix("refs/heads/") }
                .map { $0.toDetail() }
                .sorted(by: Self.sortBranches)
            tags = allRefs
                .filter { $0.name.hasPrefix("refs/tags/") }
                .map { $0.toDetail() }
                .sorted(by: Self.sortTags)
        } catch {
            if isEmptyRepositoryError(error) {
                branches = []
                tags = []
            } else {
                self.error = error.userFacingMessage
            }
        }

        isLoadingRefs = false
    }

    var defaultBranchReference: ReferenceDetail? {
        if let headName = repository.head?.name,
           let branch = branches.first(where: { $0.name == headName }) {
            return branch
        }
        return branches.first
    }

    var latestTagReference: ReferenceDetail? {
        tags.first
    }

    private func fetchAllReferences() async throws -> [ReferencePayload] {
        var allRefs: [ReferencePayload] = []
        var cursor: String?

        repeat {
            let page = try await fetchReferencePage(cursor: cursor)
            allRefs.append(contentsOf: page.results)
            cursor = page.cursor
        } while cursor != nil

        return allRefs
    }

    private func fetchReferencePage(cursor: String?) async throws -> RefsPage {
        var variables: [String: any Sendable] = ["rid": repository.rid]
        if let cursor {
            variables["cursor"] = cursor
        }

        let result = try await client.execute(
            service: service,
            query: Self.refsQuery,
            variables: variables,
            responseType: RefsResponse.self
        )

        return result.repository?.references ?? RefsPage(results: [], cursor: nil)
    }

    nonisolated private static func sortBranches(_ lhs: ReferenceDetail, _ rhs: ReferenceDetail) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    nonisolated private static func sortTags(_ lhs: ReferenceDetail, _ rhs: ReferenceDetail) -> Bool {
        switch (lhs.date, rhs.date) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - README

    private static let readmeQuery = """
    query readme($rid: ID!) {
        repository(rid: $rid) {
            readme
        }
    }
    """

    private static func readmeFileQuery(filename: String) -> String {
        """
        query readmeFile($rid: ID!) {
            repository(rid: $rid) {
                readme: path(revspec: "HEAD", path: "\(filename)") {
                    object {
                        ... on TextBlob { text }
                    }
                }
            }
        }
        """
    }

    private static let readmeFilenames = [
        "README.md", "README.org", "README.txt", "README",
        "readme.md", "readme.org"
    ]

    func loadReadme() async {
        guard !isLoadingReadme, !readmeLoaded else { return }
        isLoadingReadme = true
        defer { isLoadingReadme = false }
        error = nil

        do {
            // Step 1: Check the custom HTML readme set via the web UI
            let result = try await client.executeCached(
                service: service,
                query: Self.readmeQuery,
                variables: ["rid": repository.rid],
                responseType: ReadmeResponse.self,
                cacheKey: APICacheKeys.readme(service: service, rid: repository.rid),
                resourceType: .repositoryReadme,
                ttl: APICacheTTLs.movingRefFileContent,
                policy: .cacheFirstThenRefresh
            )
            readmeCacheMetadata = result.metadata
            if let html = result.value.repository?.readme, !html.isEmpty {
                readmePath = nil
                readmeContent = .html(html)
                readmeLoaded = true
                return
            }

            // Step 2: Try each README filename sequentially
            for filename in Self.readmeFilenames {
                let pathResult: PathResponse
                do {
                    let cached = try await client.executeCached(
                        service: service,
                        query: Self.readmeFileQuery(filename: filename),
                        variables: ["rid": repository.rid],
                        responseType: PathResponse.self,
                        cacheKey: APICacheKeys.readme(service: service, rid: repository.rid, path: filename),
                        resourceType: .repositoryReadme,
                        ttl: APICacheTTLs.movingRefFileContent,
                        policy: .cacheFirstThenRefresh
                    )
                    pathResult = cached.value
                    readmeCacheMetadata = cached.metadata
                } catch {
                    if isEmptyRepositoryError(error) {
                        readmeContent = nil
                        readmePath = nil
                        readmeLoaded = true
                        return
                    }
                    throw error
                }
                if let text = pathResult.repository?.readme?.object?.text, !text.isEmpty {
                    readmePath = filename
                    if filename.hasSuffix(".md") {
                        readmeContent = .markdown(text)
                    } else if filename.hasSuffix(".org") {
                        readmeContent = .org(text)
                    } else {
                        readmeContent = .plainText(text)
                    }
                    readmeLoaded = true
                    return
                }
            }

            // Step 3: No readme found
            readmeContent = nil
            readmePath = nil
            readmeLoaded = true
        } catch {
            self.error = error.userFacingMessage
        }
    }

    private func isEmptyRepositoryError(_ error: Error) -> Bool {
        error.matchesGraphQLErrorClassification(.missingReference)
            || error.matchesGraphQLErrorClassification(.unknownRevision)
            || error.matchesGraphQLErrorClassification(.noRows)
            || error.matchesGraphQLErrorClassification(.notFound)
            || error.containsGraphQLErrorMessage("missing")
            || error.containsGraphQLErrorMessage("internal system error")
    }

    // MARK: - Artifacts

    /// `file` is a top-level Upload variable here, unlike meta's avatar upload
    /// where it is nested inside an input object.
    private static let uploadArtifactMutation = """
    mutation uploadArtifact($repoId: Int!, $revspec: String!, $file: Upload!) {
        uploadArtifact(repoId: $repoId, revspec: $revspec, file: $file) {
            id
            filename
            checksum
            size
            url
        }
    }
    """

    private static let deleteArtifactMutation = """
    mutation deleteArtifact($id: Int!) {
        deleteArtifact(id: $id) { id }
    }
    """

    private static let artifactsQuery = """
    query artifacts($rid: ID!) {
        repository(rid: $rid) {
            references {
                results {
                    name
                    artifacts {
                        results {
                            id
                            filename
                            checksum
                            size
                            url
                        }
                        cursor
                    }
                }
                cursor
            }
        }
    }
    """

    /// Attaches a file to the tag named by `revspec`.
    ///
    /// sr.ht requires the filename to be unique among the repository's artifacts,
    /// and rejects a duplicate rather than replacing it, so the error is surfaced
    /// as-is rather than being retried.
    @discardableResult
    func uploadArtifact(revspec: String, fileURL: URL) async -> Bool {
        guard !isMutatingArtifact else { return false }
        isMutatingArtifact = true
        error = nil
        defer { isMutatingArtifact = false }

        let needsScopedAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            self.error = "Couldn't read \(fileURL.lastPathComponent)."
            return false
        }

        // sr.ht streams the upload into S3, which rejects a zero-part multipart
        // completion with "MalformedXML" — an error that says nothing about the
        // actual problem. Catch it here where we can name it.
        guard !fileData.isEmpty else {
            self.error = "\(fileURL.lastPathComponent) is empty. SourceHut rejects zero-byte artifacts."
            return false
        }

        do {
            _ = try await client.executeMultipart(
                service: service,
                query: Self.uploadArtifactMutation,
                variables: [
                    "repoId": repository.id,
                    "revspec": revspec,
                    "file": nil as String? as Any
                ],
                file: MultipartUploadFile(
                    variablePath: "file",
                    fileData: fileData,
                    fileName: fileURL.lastPathComponent,
                    mimeType: Self.mimeType(for: fileURL)
                ),
                responseType: UploadArtifactResponse.self
            )
            await reloadArtifacts()
            return true
        } catch {
            self.error = "Couldn't upload \(fileURL.lastPathComponent). \(error.userFacingMessage)"
            return false
        }
    }

    /// Downloads an artifact and returns a local file URL to share.
    ///
    /// `Artifact.url` points at the API origin, not the web one, and returns an
    /// auth error to anything without a bearer token — so it cannot be opened in
    /// a browser. Fetch it here and hand the user the file instead.
    func downloadArtifact(_ artifact: ArtifactInfo) async -> URL? {
        guard !isMutatingArtifact else { return nil }
        isMutatingArtifact = true
        error = nil
        defer { isMutatingArtifact = false }

        do {
            let data = try await client.fetchData(url: artifact.url)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(artifact.filename)
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            self.error = "Couldn't download \(artifact.filename). \(error.userFacingMessage)"
            return nil
        }
    }

    @discardableResult
    func deleteArtifact(id: Int) async -> Bool {
        guard !isMutatingArtifact else { return false }
        isMutatingArtifact = true
        error = nil
        defer { isMutatingArtifact = false }

        do {
            _ = try await client.execute(
                service: service,
                query: Self.deleteArtifactMutation,
                variables: ["id": id],
                responseType: DeleteArtifactResponse.self
            )
            await reloadArtifacts()
            return true
        } catch {
            self.error = "Couldn't delete the artifact. \(error.userFacingMessage)"
            return false
        }
    }

    private func reloadArtifacts() async {
        isLoadingArtifacts = false
        await loadArtifacts()
    }

    /// Artifacts are release tarballs and signatures rather than media, so a
    /// generic binary type is honest more often than guessing from the extension.
    private nonisolated static func mimeType(for _: URL) -> String {
        "application/octet-stream"
    }

    func loadArtifacts() async {
        guard !isLoadingArtifacts else { return }
        isLoadingArtifacts = true
        error = nil

        do {
            let result = try await client.execute(
                service: service,
                query: Self.artifactsQuery,
                variables: ["rid": repository.rid],
                responseType: ArtifactsResponse.self
            )
            // Only include references that have at least one artifact.
            referenceArtifacts = (result.repository?.references.results ?? [])
                .filter { !$0.artifacts.results.isEmpty }
                .map { ReferenceWithArtifacts(name: $0.name, artifacts: $0.artifacts.results) }
        } catch {
            if isEmptyRepositoryError(error) {
                referenceArtifacts = []
            } else {
                self.error = error.userFacingMessage
            }
        }

        isLoadingArtifacts = false
    }
}
