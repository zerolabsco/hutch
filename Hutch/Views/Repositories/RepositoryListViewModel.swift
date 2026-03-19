import Foundation

enum RepositoryCreationService: String, CaseIterable, Identifiable, Sendable {
    case git
    case hg

    var id: String { rawValue }

    var service: SRHTService {
        switch self {
        case .git: .git
        case .hg: .hg
        }
    }

    var displayName: String {
        switch self {
        case .git: "Git"
        case .hg: "Mercurial"
        }
    }
}

/// View model for the repository list screen.
@Observable
@MainActor
final class RepositoryListViewModel {

    private(set) var repositories: [RepositorySummary] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isRefreshing = false
    var error: String?

    var searchText = ""

    private(set) var cursor: String?
    private(set) var hasMore = false
    private(set) var isSearching = false
    private(set) var isCreatingRepository = false
    private(set) var hasLoadedSearchIndex = false
    private var searchIndex: [RepositorySummary] = []
    private let client: SRHTClient

    private static let gitCacheKey = "git.repositories"
    private static let hgCacheKey = "hg.repositories"
    private static let minimumRemoteSearchLength = 3

    init(client: SRHTClient) {
        self.client = client
    }

    // MARK: - Queries

    private static let gitQuery = """
    query repositories($cursor: Cursor, $filter: Filter) {
        repositories(cursor: $cursor, filter: $filter) {
            results {
                id
                rid
                name
                description
                visibility
                updated
                owner { canonicalName }
                HEAD { name }
            }
            cursor
        }
    }
    """

    private static let hgQuery = """
    query repositories($cursor: Cursor) {
        repositories(cursor: $cursor) {
            results {
                id
                rid
                name
                description
                visibility
                updated
                owner { canonicalName }
                tip { branch }
            }
            cursor
        }
    }
    """

    private static let createRepositoryMutation = """
    mutation createRepository($name: String!, $visibility: Visibility!, $description: String, $cloneUrl: String) {
        createRepository(name: $name, visibility: $visibility, description: $description, cloneUrl: $cloneUrl) {
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

    private static let createHgRepositoryMutation = """
    mutation createRepository($name: String!, $visibility: Visibility!, $description: String) {
        createRepository(name: $name, visibility: $visibility, description: $description) {
            id
            rid
            name
            description
            visibility
            updated
            owner { canonicalName }
            tip { branch }
        }
    }
    """

    // MARK: - Public API

    /// Fetch the first page of repositories. Shows cached data instantly if available,
    /// then refreshes from the network in the background.
    /// - Parameter search: Optional search string. Pass `nil` to use the current `searchText`.
    func loadRepositories(search: String? = nil) async {
        let query = (search ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearch = !query.isEmpty

        // Only use cache for non-search, initial loads
        if !isSearch, repositories.isEmpty {
            loadFromCache()
        }

        // During search, never show the full-screen loading overlay (which
        // would remove the List and dismiss the keyboard). Use "refreshing"
        // instead so the list stays in the hierarchy.
        if isSearch {
            isRefreshing = true
            isSearching = true
        } else if repositories.isEmpty {
            isLoading = true
            isSearching = false
        } else {
            isRefreshing = true
            isSearching = false
        }
        error = nil
        cursor = nil
        hasMore = false

        do {
            var filteredResults: [RepositorySummary]

            if isSearch {
                if hasLoadedSearchIndex || repositories.isEmpty == false {
                    filteredResults = Self.filterRepositories(repositoriesForSearchIndex, matching: query)
                } else if Self.shouldRefreshSearchIndex(for: query) {
                    let repositories = try await fetchAllRepositories(useCache: true)
                    updateSearchIndex(with: repositories)
                    filteredResults = Self.filterRepositories(repositoriesForSearchIndex, matching: query)
                } else {
                    filteredResults = []
                }
            } else {
                let repositories = try await fetchAllRepositories(useCache: true)
                updateSearchIndex(with: repositories)
                filteredResults = repositories
            }

            repositories = filteredResults.sorted(by: repositorySortOrder)
        } catch {
            // Only show error if we have no cached data to fall back on
            if repositories.isEmpty {
                self.error = error.localizedDescription
            }
        }

        isLoading = false
        isRefreshing = false
    }

    /// Load the next page if available. Called when the user scrolls near the end.
    /// Note: Pagination is disabled during search (client-side filtering).
    func loadMoreIfNeeded(currentItem: RepositorySummary) async {
        _ = currentItem
    }

    /// Remove a repository from the local list (e.g. after deletion).
    func removeRepository(id: Int) {
        repositories.removeAll { $0.id == id }
    }

    func createRepository(
        service: RepositoryCreationService,
        name: String,
        description: String,
        visibility: Visibility,
        cloneURL: String
    ) async -> RepositorySummary? {
        guard !isCreatingRepository else { return nil }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            error = "Enter a repository name."
            return nil
        }

        isCreatingRepository = true
        error = nil
        defer { isCreatingRepository = false }

        var variables: [String: any Sendable] = [
            "name": trimmedName,
            "visibility": visibility.rawValue
        ]
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDescription.isEmpty {
            variables["description"] = trimmedDescription
        }
        let trimmedCloneURL = cloneURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCloneURL.isEmpty {
            variables["cloneUrl"] = trimmedCloneURL
        }

        do {
            let repository: RepositorySummary
            switch service {
            case .git:
                let result = try await client.execute(
                    service: .git,
                    query: Self.createRepositoryMutation,
                    variables: variables,
                    responseType: CreateRepositoryResponse.self
                )
                repository = result.createRepository
            case .hg:
                variables.removeValue(forKey: "cloneUrl")
                let result = try await client.execute(
                    service: .hg,
                    query: Self.createHgRepositoryMutation,
                    variables: variables,
                    responseType: CreateHGRepositoryResponse.self
                )
                repository = result.createRepository.repositorySummary(service: .hg)
            }
            repositories.insert(repository, at: 0)
            insertIntoSearchIndex(repository)
            return repository
        } catch {
            self.error = repositoryCreationErrorMessage(for: error)
            return nil
        }
    }

    private func repositoryCreationErrorMessage(for error: Error) -> String {
        let message: String

        if let srhtError = error as? SRHTError {
            switch srhtError {
            case .graphQLErrors(let errors):
                message = errors.map(\.message).joined(separator: "\n")
            default:
                message = srhtError.localizedDescription
            }
        } else {
            message = error.localizedDescription
        }

        return "Couldn’t create the repository. \(message)"
    }

    /// Fetch ALL repositories by paginating through all available pages.
    /// Used for search functionality to ensure we search through the complete dataset.
    private func fetchAllRepositories(useCache: Bool = false) async throws -> [RepositorySummary] {
        async let gitRepositories = fetchRepositories(for: .git, useCache: useCache)
        async let hgRepositories = fetchRepositories(for: .hg, useCache: useCache)
        return try await gitRepositories + hgRepositories
    }

    /// Reset search state and reload all repositories
    func resetSearch() {
        repositories = []
        cursor = nil
        hasMore = false
        isSearching = false
    }

    // MARK: - Private

    /// Page shape matching the GraphQL response without generic constraints that
    /// conflict with strict concurrency when used from a @MainActor context.
    private struct Page: Decodable, Sendable {
        let results: [RepositoryPayload]
        let cursor: String?
    }

    private struct RepositoriesResponse: Decodable, Sendable {
        let repositories: Page?
    }

    private struct CreateRepositoryResponse: Decodable, Sendable {
        let createRepository: RepositorySummary
    }

    private struct CreateHGRepositoryResponse: Decodable, Sendable {
        let createRepository: HGRepositoryPayload
    }

    private struct HGPage: Decodable, Sendable {
        let results: [HGRepositoryPayload]
        let cursor: String?
    }

    private struct HGRepositoriesResponse: Decodable, Sendable {
        let repositories: HGPage?
    }

    private static let emptyPage = Page(results: [], cursor: nil)

    private struct RepositoryPayload: Decodable, Sendable {
        let id: Int
        let rid: String
        let name: String
        let description: String?
        let visibility: Visibility
        let updated: Date
        let owner: Entity
        let head: Reference?

        enum CodingKeys: String, CodingKey {
            case id, rid, name, description, visibility, updated, owner
            case head = "HEAD"
        }

        func repositorySummary(service: SRHTService) -> RepositorySummary {
            RepositorySummary(
                id: id,
                rid: rid,
                service: service,
                name: name,
                description: description,
                visibility: visibility,
                updated: updated,
                owner: owner,
                head: head
            )
        }
    }

    private struct HGRepositoryPayload: Decodable, Sendable {
        let id: Int
        let rid: String
        let name: String
        let description: String?
        let visibility: Visibility
        let updated: Date
        let owner: Entity
        let tip: HGTipReference?

        func repositorySummary(service: SRHTService) -> RepositorySummary {
            RepositorySummary(
                id: id,
                rid: rid,
                service: service,
                name: name,
                description: description,
                visibility: visibility,
                updated: updated,
                owner: owner,
                head: tip.map { Reference(name: $0.branch, target: nil) }
            )
        }
    }

    private struct HGTipReference: Decodable, Sendable {
        let branch: String
    }

    private var repositoriesForSearchIndex: [RepositorySummary] {
        searchIndex
    }

    private func fetchPage(
        service: SRHTService,
        cursor: String?,
        search: String? = nil,
        useCache: Bool
    ) async throws -> Page {
        var variables: [String: any Sendable] = [:]
        if let cursor {
            variables["cursor"] = cursor
        }
        let trimmed = (search ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            variables["filter"] = ["search": trimmed] as [String: any Sendable]
        }

        if useCache && cursor == nil {
            switch service {
            case .git:
                let result = try await client.executeAndCache(
                    service: service,
                    query: Self.gitQuery,
                    variables: variables.isEmpty ? nil : variables,
                    responseType: RepositoriesResponse.self,
                    cacheKey: cacheKey(for: service)
                )
                return result.repositories ?? Self.emptyPage
            case .hg:
                let hgVariables = cursor.map { ["cursor": $0 as any Sendable] }
                let result = try await client.executeAndCache(
                    service: service,
                    query: Self.hgQuery,
                    variables: hgVariables,
                    responseType: HGRepositoriesResponse.self,
                    cacheKey: cacheKey(for: service)
                )
                return Page(
                    results: result.repositories?.results.map {
                        RepositoryPayload(
                            id: $0.id,
                            rid: $0.rid,
                            name: $0.name,
                            description: $0.description,
                            visibility: $0.visibility,
                            updated: $0.updated,
                            owner: $0.owner,
                            head: $0.tip.map { Reference(name: $0.branch, target: nil) }
                        )
                    } ?? [],
                    cursor: result.repositories?.cursor
                )
            default:
                let result = try await client.executeAndCache(
                    service: service,
                    query: Self.gitQuery,
                    variables: variables.isEmpty ? nil : variables,
                    responseType: RepositoriesResponse.self,
                    cacheKey: cacheKey(for: service)
                )
                return result.repositories ?? Self.emptyPage
            }
        } else {
            switch service {
            case .git:
                let result = try await client.execute(
                    service: service,
                    query: Self.gitQuery,
                    variables: variables.isEmpty ? nil : variables,
                    responseType: RepositoriesResponse.self
                )
                return result.repositories ?? Self.emptyPage
            case .hg:
                let hgVariables = cursor.map { ["cursor": $0 as any Sendable] }
                let result = try await client.execute(
                    service: service,
                    query: Self.hgQuery,
                    variables: hgVariables,
                    responseType: HGRepositoriesResponse.self
                )
                return Page(
                    results: result.repositories?.results.map {
                        RepositoryPayload(
                            id: $0.id,
                            rid: $0.rid,
                            name: $0.name,
                            description: $0.description,
                            visibility: $0.visibility,
                            updated: $0.updated,
                            owner: $0.owner,
                            head: $0.tip.map { Reference(name: $0.branch, target: nil) }
                        )
                    } ?? [],
                    cursor: result.repositories?.cursor
                )
            default:
                let result = try await client.execute(
                    service: service,
                    query: Self.gitQuery,
                    variables: variables.isEmpty ? nil : variables,
                    responseType: RepositoriesResponse.self
                )
                return result.repositories ?? Self.emptyPage
            }
        }
    }

    private func loadFromCache() {
        let cachedRepositories = [SRHTService.git, .hg].flatMap { service -> [RepositorySummary] in
            guard let data = client.responseCache.get(forKey: cacheKey(for: service)) else { return [] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .srhtFlexible
            switch service {
            case .git:
                if let response = try? decoder.decode(
                    GraphQLResponse<RepositoriesResponse>.self,
                    from: data
                ), let repos = response.data?.repositories {
                    return repos.results.map { $0.repositorySummary(service: service) }
                }
            case .hg:
                if let response = try? decoder.decode(
                    GraphQLResponse<HGRepositoriesResponse>.self,
                    from: data
                ), let repos = response.data?.repositories {
                    return repos.results.map { $0.repositorySummary(service: service) }
                }
            default:
                break
            }
            return []
        }
        if !cachedRepositories.isEmpty {
            let sortedRepositories = cachedRepositories.sorted(by: repositorySortOrder)
            repositories = sortedRepositories
            updateSearchIndex(with: sortedRepositories)
        }
    }

    private func fetchRepositories(for service: SRHTService, useCache: Bool) async throws -> [RepositorySummary] {
        var allRepositories: [RepositorySummary] = []
        var currentCursor: String? = nil

        while true {
            let page = try await fetchPage(
                service: service,
                cursor: currentCursor,
                search: nil,
                useCache: useCache && currentCursor == nil
            )
            allRepositories.append(contentsOf: page.results.map { $0.repositorySummary(service: service) })
            guard let nextCursor = page.cursor else { break }
            currentCursor = nextCursor
        }

        return allRepositories
    }

    private func cacheKey(for service: SRHTService) -> String {
        switch service {
        case .git:
            Self.gitCacheKey
        case .hg:
            Self.hgCacheKey
        default:
            "\(service.rawValue).repositories"
        }
    }

    private func repositorySortOrder(lhs: RepositorySummary, rhs: RepositorySummary) -> Bool {
        if lhs.updated == rhs.updated {
            if lhs.service == rhs.service {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.service.rawValue < rhs.service.rawValue
        }
        return lhs.updated > rhs.updated
    }

    private func updateSearchIndex(with repositories: [RepositorySummary]) {
        searchIndex = repositories.sorted(by: repositorySortOrder)
        hasLoadedSearchIndex = !searchIndex.isEmpty
    }

    private func insertIntoSearchIndex(_ repository: RepositorySummary) {
        let updatedRepositories = (repositoriesForSearchIndex + [repository])
            .uniqued(on: \.id)
            .sorted(by: repositorySortOrder)
        updateSearchIndex(with: updatedRepositories)
    }

    static func shouldRefreshSearchIndex(for query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minimumRemoteSearchLength
    }

    static func filterRepositories(_ repositories: [RepositorySummary], matching query: String) -> [RepositorySummary] {
        let lowercasedQuery = query.lowercased()
        return repositories.filter { repo in
            repo.name.lowercased().contains(lowercasedQuery) ||
            repo.description?.lowercased().contains(lowercasedQuery) ?? false
        }
    }
}

private extension Array {
    func uniqued<ID: Hashable>(on keyPath: KeyPath<Element, ID>) -> [Element] {
        var seenIDs: Set<ID> = []
        return filter { element in
            seenIDs.insert(element[keyPath: keyPath]).inserted
        }
    }
}
