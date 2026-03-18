import Foundation

private struct HgRepositorySummaryResponse: Decodable, Sendable {
    let repository: HgRepositorySummaryPayload?
}

private struct HgRepositorySummaryPayload: Decodable, Sendable {
    let id: Int
    let rid: String
    let name: String
    let description: String?
    let visibility: Visibility
    let readme: String?
    let nonPublishing: Bool?
    let tip: HgSummaryTip?
    let branches: HgNamedRevisionPage?
    let tags: HgNamedRevisionPage?
    let bookmarks: HgNamedRevisionPage?
}

private struct HgSummaryTip: Decodable, Sendable {
    let id: String?
    let author: String?
    let description: String?
    let branch: String?
    let tags: [String]?

    var resolvedRevision: HgRevision? {
        guard
            let id,
            let author,
            let description
        else {
            return nil
        }

        return HgRevision(
            id: id,
            author: author,
            description: description,
            branch: branch,
            tags: tags
        )
    }
}

private struct HgRevisionLogResponse: Decodable, Sendable {
    let repository: HgRevisionLogRepository?
}

private struct HgRevisionLogRepository: Decodable, Sendable {
    let log: HgRevisionPage?
}

private struct HgReadmeFileResponse: Decodable, Sendable {
    let repository: HgReadmeFileRepository?
}

private struct HgReadmeFileRepository: Decodable, Sendable {
    let readme: String?
}

private struct HgFilesResponse: Decodable, Sendable {
    let repository: HgFilesRepository?
}

private struct HgFilesRepository: Decodable, Sendable {
    let files: HgFilePage?
}

private struct HgFilePage: Decodable, Sendable {
    let results: [HgFile]
    let cursor: String?
}

private struct HgNamedRevisionPage: Decodable, Sendable {
    let results: [HgNamedRevision]
    let cursor: String?

    private enum CodingKeys: String, CodingKey {
        case results
        case cursor
    }

    init(results: [HgNamedRevision], cursor: String?) {
        self.results = results
        self.cursor = cursor
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.results = try container.decodeIfPresent([HgNamedRevision?].self, forKey: .results)?.compactMap { $0 } ?? []
        self.cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
    }
}

private struct HgCatResponse: Decodable, Sendable {
    let repository: HgCatRepository?
}

private struct HgCatRepository: Decodable, Sendable {
    let cat: String?
}

struct HgRevisionPage: Decodable, Sendable {
    let results: [HgRevision]
    let cursor: String?
}

struct HgRevision: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let author: String
    let description: String
    let branch: String?
    let tags: [String]?

    var displayShortId: String {
        String(id.prefix(12))
    }

    var title: String {
        description.prefix(while: { $0 != "\n" }).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: String? {
        let body = description
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .dropFirst()
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body?.isEmpty == false ? body : nil
    }

    var primaryName: String {
        if let tag = tags?.first, !tag.isEmpty {
            return tag
        }
        if let branch, !branch.isEmpty {
            return branch
        }
        return displayShortId
    }
}

struct HgFile: Decodable, Sendable, Hashable, Identifiable {
    let name: String

    var id: String { name }

    var isDirectory: Bool {
        name.hasSuffix("/")
    }
}

struct HgNamedRevision: Decodable, Sendable, Identifiable, Hashable {
    let name: String
    let id: String

    var displayShortId: String {
        String(id.prefix(12))
    }
}

@Observable
@MainActor
final class HgRepositoryDetailViewModel {
    enum Tab: String, CaseIterable {
        case summary = "Summary"
        case browse = "Browse"
        case log = "Log"
        case tags = "Tags"
        case branches = "Branches"
        case bookmarks = "Bookmarks"
    }

    enum ReadmeContent {
        case html(String)
        case markdown(String)
        case org(String)
        case plainText(String)
    }

    let repository: RepositorySummary
    private let client: SRHTClient

    private(set) var summaryLoaded = false
    private(set) var isLoadingSummary = false
    private(set) var readmeContent: ReadmeContent?
    private(set) var readmePath: String?
    private(set) var nonPublishing = false
    private(set) var tip: HgRevision?
    private(set) var branches: [HgNamedRevision] = []
    private(set) var tags: [HgNamedRevision] = []
    private(set) var bookmarks: [HgNamedRevision] = []

    private(set) var log: [HgRevision] = []
    private(set) var isLoadingLog = false
    private(set) var isLoadingMoreLog = false
    private var logCursor: String?
    private var hasMoreLog = true

    private(set) var currentBrowsePath = ""
    private(set) var pathStack: [String] = []
    private(set) var files: [HgFile] = []
    private(set) var fileContent: String?
    private(set) var selectedFilePath: String?
    private(set) var isLoadingBrowse = false
    private(set) var browseRevspec = "tip"

    var error: String?

    init(repository: RepositorySummary, client: SRHTClient) {
        self.repository = repository
        self.client = client
    }

    private static let summaryQuery = """
    query hgRepositorySummary($rid: ID!) {
        repository(rid: $rid) {
            id
            rid
            name
            description
            visibility
            readme
            nonPublishing
            tip {
                id
                author
                description
                branch
                tags
            }
            branches {
                results {
                    name
                    id
                }
                cursor
            }
            tags {
                results {
                    name
                    id
                }
                cursor
            }
            bookmarks {
                results {
                    name
                    id
                }
                cursor
            }
        }
    }
    """

    private static let logQuery = """
    query hgRepositoryLog($rid: ID!, $cursor: Cursor) {
        repository(rid: $rid) {
            log(cursor: $cursor) {
                results {
                    id
                    author
                    description
                    branch
                    tags
                }
                cursor
            }
        }
    }
    """

    private static func readmeFileQuery(filename: String) -> String {
        """
        query hgReadmeFile($rid: ID!) {
            repository(rid: $rid) {
                readme: cat(path: "\(filename)", revspec: "tip")
            }
        }
        """
    }

    private static let readmeFilenames = [
        "README.md", "README.org", "README.txt", "README",
        "readme.md", "readme.org"
    ]

    private static let filesQuery = """
    query hgFiles($rid: ID!, $path: String!, $revspec: String!) {
        repository(rid: $rid) {
            files(path: $path, revspec: $revspec) {
                results {
                    name
                }
                cursor
            }
        }
    }
    """

    private static let catQuery = """
    query hgCat($rid: ID!, $path: String!, $revspec: String!) {
        repository(rid: $rid) {
            cat(path: $path, revspec: $revspec)
        }
    }
    """

    func loadSummary() async {
        guard !isLoadingSummary, !summaryLoaded else { return }
        isLoadingSummary = true
        defer { isLoadingSummary = false }
        error = nil

        do {
            let result = try await client.execute(
                service: .hg,
                query: Self.summaryQuery,
                variables: ["rid": repository.rid],
                responseType: HgRepositorySummaryResponse.self
            )

            guard let repository = result.repository else {
                summaryLoaded = true
                return
            }

            tip = repository.tip?.resolvedRevision
            branches = repository.branches?.results ?? []
            tags = repository.tags?.results ?? []
            bookmarks = repository.bookmarks?.results ?? []
            nonPublishing = repository.nonPublishing ?? false

            if let html = repository.readme, !html.isEmpty {
                readmePath = nil
                readmeContent = .html(html)
            } else {
                await loadReadmeFile()
            }

            summaryLoaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadLog() async {
        guard !isLoadingLog else { return }
        isLoadingLog = true
        defer { isLoadingLog = false }
        error = nil
        logCursor = nil
        hasMoreLog = true

        do {
            let page = try await fetchLogPage(cursor: nil)
            log = page.results
            logCursor = page.cursor
            hasMoreLog = page.cursor != nil
        } catch {
            if isEmptyRepositoryError(error) {
                log = []
                logCursor = nil
                hasMoreLog = false
            } else {
                self.error = error.localizedDescription
            }
        }
    }

    func loadMoreLogIfNeeded(currentItem: HgRevision) async {
        guard let last = log.last,
              last.id == currentItem.id,
              hasMoreLog,
              !isLoadingMoreLog else {
            return
        }

        isLoadingMoreLog = true
        defer { isLoadingMoreLog = false }

        do {
            let page = try await fetchLogPage(cursor: logCursor)
            log.append(contentsOf: page.results)
            logCursor = page.cursor
            hasMoreLog = page.cursor != nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchLogPage(cursor: String?) async throws -> HgRevisionPage {
        var variables: [String: any Sendable] = ["rid": repository.rid]
        if let cursor {
            variables["cursor"] = cursor
        }

        let result = try await client.execute(
            service: .hg,
            query: Self.logQuery,
            variables: variables,
            responseType: HgRevisionLogResponse.self
        )
        return result.repository?.log ?? HgRevisionPage(results: [], cursor: nil)
    }

    private func loadReadmeFile() async {
        for filename in Self.readmeFilenames {
            do {
                let result = try await client.execute(
                    service: .hg,
                    query: Self.readmeFileQuery(filename: filename),
                    variables: ["rid": repository.rid],
                    responseType: HgReadmeFileResponse.self
                )

                if let text = result.repository?.readme, !text.isEmpty {
                    readmePath = filename
                    if filename.hasSuffix(".md") {
                        readmeContent = .markdown(text)
                    } else if filename.hasSuffix(".org") {
                        readmeContent = .org(text)
                    } else {
                        readmeContent = .plainText(text)
                    }
                    return
                }
            } catch {
                if isEmptyRepositoryError(error) {
                    readmeContent = nil
                    readmePath = nil
                    return
                }
                continue
            }
        }
    }

    func loadBrowseRoot() async {
        await loadFiles(at: "")
    }

    func openFile(_ file: HgFile) async {
        let path = joinedPath(for: file.name)
        if file.isDirectory {
            await loadFiles(at: path)
            return
        }

        isLoadingBrowse = true
        defer { isLoadingBrowse = false }
        error = nil

        do {
            let result = try await client.execute(
                service: .hg,
                query: Self.catQuery,
                variables: ["rid": repository.rid, "path": path, "revspec": browseRevspec],
                responseType: HgCatResponse.self
            )

            if let text = result.repository?.cat {
                selectedFilePath = path
                fileContent = text
            } else {
                await loadFiles(at: path)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func navigateToPath(index: Int) async {
        guard index >= 0, index <= pathStack.count else { return }
        let targetPath = Array(pathStack.prefix(index)).joined(separator: "/")
        await loadFiles(at: targetPath)
    }

    func dismissFileView() {
        selectedFilePath = nil
        fileContent = nil
    }

    func changeBrowseRevspec(_ newRevspec: String) async {
        guard browseRevspec != newRevspec else { return }
        browseRevspec = newRevspec
        await loadBrowseRoot()
    }

    private func loadFiles(at path: String) async {
        isLoadingBrowse = true
        defer { isLoadingBrowse = false }
        error = nil
        selectedFilePath = nil
        fileContent = nil

        do {
            let result = try await client.execute(
                service: .hg,
                query: Self.filesQuery,
                variables: ["rid": repository.rid, "path": path, "revspec": browseRevspec],
                responseType: HgFilesResponse.self
            )

            currentBrowsePath = path
            pathStack = path.isEmpty ? [] : path.split(separator: "/").map(String.init)
            files = result.repository?.files?.results ?? []
        } catch {
            if isEmptyRepositoryError(error) {
                currentBrowsePath = path
                pathStack = path.isEmpty ? [] : path.split(separator: "/").map(String.init)
                files = []
            } else {
                self.error = error.localizedDescription
            }
        }
    }

    private func joinedPath(for name: String) -> String {
        let cleanedName = name.hasSuffix("/") ? String(name.dropLast()) : name
        return currentBrowsePath.isEmpty ? cleanedName : "\(currentBrowsePath)/\(cleanedName)"
    }

    private func isEmptyRepositoryError(_ error: Error) -> Bool {
        if let srhtError = error as? SRHTError,
           case .graphQLErrors(let errors) = srhtError {
            return errors.contains {
                let message = $0.message.localizedLowercase
                return message.contains("missing")
                    || message.contains("not found")
                    || message.contains("unknown revision")
                    || message.contains("unknown revision or path not in the working tree")
            }
        }

        let message = error.localizedDescription.localizedLowercase
        return message.contains("missing")
            || message.contains("not found")
            || message.contains("unknown revision")
    }
}
