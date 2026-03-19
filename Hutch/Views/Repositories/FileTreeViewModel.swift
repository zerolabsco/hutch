import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct RevparseResponse: Decodable, Sendable {
    let repository: RevparseRepository?
}

private struct RevparseRepository: Decodable, Sendable {
    let revparse_single: RevparseCommit?
}

private struct RevparseCommit: Decodable, Sendable {
    let tree: GitTree?
}

private struct SubtreeResponse: Decodable, Sendable {
    let repository: SubtreeRepository?
}

private struct SubtreeRepository: Decodable, Sendable {
    let object: SubtreeObject?
}

/// Dedicated decoding struct for the subtree query response.
/// Does not use GitObject enum — decodes entries directly from the Tree inline fragment.
private struct SubtreeObject: Decodable, Sendable {
    let entries: GitTreeEntryPage?
}

private struct BlobResponse: Decodable, Sendable {
    let repository: BlobRepository?
}

private struct BlobRepository: Decodable, Sendable {
    let object: GitObject?
}

// MARK: - Navigation Stack Entry

struct FileNavEntry: Hashable {
    let name: String
    let treeId: String
}

// MARK: - View Model

@Observable
@MainActor
final class FileTreeViewModel {

    let repositoryRid: String
    let service: SRHTService
    private let client: SRHTClient

    /// The current revspec. "HEAD" by default, or a full ref name.
    var revspec: String = "HEAD"

    /// Navigation stack: each entry is a (name, treeId) pair.
    /// The first entry is always the root.
    private(set) var navStack: [FileNavEntry] = []

    /// The tree entries at the current directory level.
    private(set) var entries: [TreeEntry] = []

    /// When viewing a file (text blob or binary blob), this holds the object.
    private(set) var viewingEntry: TreeEntry?
    private(set) var viewingObject: GitObject?

    private(set) var isLoading = false
    var error: String?

    // Available references for the branch/tag picker
    private(set) var branches: [Reference] = []
    private(set) var tags: [Reference] = []
    private(set) var isLoadingRefs = false

    init(repositoryRid: String, service: SRHTService, client: SRHTClient) {
        self.repositoryRid = repositoryRid
        self.service = service
        self.client = client
    }

    // MARK: - Queries

    private static let rootTreeQuery = """
    query files($rid: ID!, $revspec: String!) {
        repository(rid: $rid) {
            revparse_single(revspec: $revspec) {
                tree {
                    id
                    entries {
                        results {
                            id
                            name
                            mode
                            object {
                                type
                                __typename
                                id
                                shortId
                                ... on Tree {
                                    entries {
                                        results {
                                            id
                                            name
                                            mode
                                            object { type id shortId }
                                        }
                                        cursor
                                    }
                                }
                                ... on TextBlob {
                                    size
                                }
                                ... on BinaryBlob {
                                    size
                                }
                            }
                        }
                        cursor
                    }
                }
            }
        }
    }
    """

    /// Query to fetch additional pages of tree entries by tree ID + cursor.
    private static let treeEntriesPageQuery = """
    query treeEntriesPage($rid: ID!, $treeId: String!, $cursor: Cursor) {
        repository(rid: $rid) {
            object(id: $treeId) {
                type
                id
                ... on Tree {
                    entries(cursor: $cursor) {
                        results {
                            id
                            name
                            mode
                            object {
                                type
                                __typename
                                id
                                shortId
                                ... on Tree {
                                    entries {
                                        results {
                                            id
                                            name
                                            mode
                                            object { type id shortId }
                                        }
                                        cursor
                                    }
                                }
                                ... on TextBlob {
                                    size
                                }
                                ... on BinaryBlob {
                                    size
                                }
                            }
                        }
                        cursor
                    }
                }
            }
        }
    }
    """

    private static let subtreeQuery = """
    query subtree($rid: ID!, $treeId: String!, $cursor: Cursor) {
        repository(rid: $rid) {
            object(id: $treeId) {
                type
                id
                ... on Tree {
                    entries(cursor: $cursor) {
                        results {
                            id
                            name
                            mode
                            object {
                                type
                                __typename
                                id
                                shortId
                                ... on Tree {
                                    entries {
                                        results {
                                            id
                                            name
                                            mode
                                            object { type id shortId }
                                        }
                                        cursor
                                    }
                                }
                                ... on TextBlob {
                                    size
                                }
                                ... on BinaryBlob {
                                    size
                                }
                            }
                        }
                        cursor
                    }
                }
            }
        }
    }
    """

    private static let blobQuery = """
    query blob($rid: ID!, $blobId: String!) {
        repository(rid: $rid) {
            object(id: $blobId) {
                type
                id
                ... on TextBlob {
                    text
                    size
                }
                ... on BinaryBlob {
                    size
                    content
                }
            }
        }
    }
    """

    private static let refsQuery = """
    query refs($rid: ID!) {
        repository(rid: $rid) {
            references {
                results { name target }
                cursor
            }
        }
    }
    """

    // MARK: - Load Root Tree

    func loadRootTree() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        viewingEntry = nil
        viewingObject = nil
        defer { isLoading = false }

        let variables: [String: any Sendable] = [
            "rid": repositoryRid,
            "revspec": revspec
        ]

        do {
            let result: RevparseResponse
            do {
                result = try await client.execute(
                    service: service,
                    query: Self.rootTreeQuery,
                    variables: variables,
                    responseType: RevparseResponse.self
                )
            } catch {
                if isMissingGitReferenceError(error) {
                    navStack = [FileNavEntry(name: "root", treeId: "")]
                    entries = []
                    return
                }
                throw error
            }
            if let tree = result.repository?.revparse_single?.tree,
               let rootId = tree.id {
                navStack = [FileNavEntry(name: "root", treeId: rootId)]
                var allEntries = tree.entries?.results ?? []
                var cursor = tree.entries?.cursor
                // Follow cursor pagination for remaining pages
                while let nextCursor = cursor {
                    let pageEntries = try await fetchTreeEntriesPage(treeId: rootId, cursor: nextCursor)
                    allEntries.append(contentsOf: pageEntries.results)
                    cursor = pageEntries.cursor
                }
                entries = allEntries
            } else {
                navStack = []
                entries = []
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Navigate Into Folder

    func navigateInto(entry: TreeEntry) async {
        guard let object = entry.object else { return }

        switch object {
        case .tree(let tree):
            // Use the git object SHA from entry.object, NOT entry.id
            guard let objectSHA = tree.id else { return }
            // If we already have the entries inline and no further pages, use them directly
            if let inlineEntries = tree.entries?.results, !inlineEntries.isEmpty, tree.entries?.cursor == nil {
                navStack.append(FileNavEntry(name: entry.name, treeId: objectSHA))
                entries = inlineEntries
                viewingEntry = nil
                viewingObject = nil
                return
            }
            // Otherwise fetch the subtree (handles pagination)
            await loadSubtree(name: entry.name, treeId: objectSHA)

        case .textBlob(let blob):
            if blob.text != nil {
                viewingEntry = entry
                viewingObject = object
            } else if let blobId = blob.id {
                await loadBlob(entry: entry, blobId: blobId)
            }

        case .binaryBlob(let blob):
            if blob.content != nil {
                viewingEntry = entry
                viewingObject = object
            } else if let blobId = blob.id {
                await loadBlob(entry: entry, blobId: blobId)
            } else {
                viewingEntry = entry
                viewingObject = object
            }

        case .unknown:
            break
        }
    }

    private func loadSubtree(name: String, treeId: String) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        viewingEntry = nil
        viewingObject = nil
        defer { isLoading = false }

        let variables: [String: any Sendable] = [
            "rid": repositoryRid,
            "treeId": treeId
        ]

        do {
            let result = try await client.execute(
                service: service,
                query: Self.subtreeQuery,
                variables: variables,
                responseType: SubtreeResponse.self
            )
            navStack.append(FileNavEntry(name: name, treeId: treeId))
            var allEntries = result.repository?.object?.entries?.results ?? []
            var cursor = result.repository?.object?.entries?.cursor
            while let nextCursor = cursor {
                let pageEntries = try await fetchTreeEntriesPage(treeId: treeId, cursor: nextCursor)
                allEntries.append(contentsOf: pageEntries.results)
                cursor = pageEntries.cursor
            }
            entries = allEntries
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadBlob(entry: TreeEntry, blobId: String) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        let variables: [String: any Sendable] = [
            "rid": repositoryRid,
            "blobId": blobId
        ]

        do {
            let result = try await client.execute(
                service: service,
                query: Self.blobQuery,
                variables: variables,
                responseType: BlobResponse.self
            )
            viewingEntry = entry
            viewingObject = result.repository?.object ?? .unknown
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Navigate to Breadcrumb

    func navigateToBreadcrumb(at index: Int) async {
        guard index >= 0, index < navStack.count else { return }

        // If tapping current level, do nothing
        if index == navStack.count - 1, viewingEntry == nil {
            return
        }

        // Clear file view
        viewingEntry = nil
        viewingObject = nil

        // Trim the stack
        let targetEntry = navStack[index]
        navStack = Array(navStack.prefix(index + 1))

        if index == 0 {
            // Go back to root — reload from revparse_single
            await loadRootTree()
        } else {
            // Load the subtree at this level
            isLoading = true
            error = nil
            defer { isLoading = false }

            let variables: [String: any Sendable] = [
                "rid": repositoryRid,
                "treeId": targetEntry.treeId
            ]

            do {
                let result = try await client.execute(
                    service: service,
                    query: Self.subtreeQuery,
                    variables: variables,
                    responseType: SubtreeResponse.self
                )
                var allEntries = result.repository?.object?.entries?.results ?? []
                var cursor = result.repository?.object?.entries?.cursor
                while let nextCursor = cursor {
                    let pageEntries = try await fetchTreeEntriesPage(treeId: targetEntry.treeId, cursor: nextCursor)
                    allEntries.append(contentsOf: pageEntries.results)
                    cursor = pageEntries.cursor
                }
                entries = allEntries
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Fetch a single page of tree entries by tree ID and cursor.
    private func fetchTreeEntriesPage(treeId: String, cursor: String) async throws -> GitTreeEntryPage {
        let variables: [String: any Sendable] = [
            "rid": repositoryRid,
            "treeId": treeId,
            "cursor": cursor
        ]
        let result = try await client.execute(
            service: service,
            query: Self.treeEntriesPageQuery,
            variables: variables,
            responseType: SubtreeResponse.self
        )
        return result.repository?.object?.entries ?? GitTreeEntryPage(results: [], cursor: nil)
    }

    /// Dismiss the file view and go back to the directory listing.
    func dismissFileView() {
        viewingEntry = nil
        viewingObject = nil
    }

    // MARK: - Change Revspec

    func changeRevspec(_ newRevspec: String) async {
        revspec = newRevspec
        await loadRootTree()
    }

    // MARK: - Load References

    func loadReferences() async {
        guard !isLoadingRefs else { return }
        isLoadingRefs = true

        do {
            let result = try await client.execute(
                service: service,
                query: Self.refsQuery,
                variables: ["rid": repositoryRid],
                responseType: RefsResponseLocal.self
            )
            let allRefs = result.repository?.references.results ?? []
            branches = allRefs.filter { $0.name.hasPrefix("refs/heads/") }
            tags = allRefs.filter { $0.name.hasPrefix("refs/tags/") }
        } catch {
            // Silently fail for refs — non-critical
        }

        isLoadingRefs = false
    }

    private func isMissingGitReferenceError(_ error: Error) -> Bool {
        guard let srhtError = error as? SRHTError else { return false }
        guard case .graphQLErrors(let errors) = srhtError else { return false }
        return errors.contains { $0.message.localizedCaseInsensitiveContains("reference not found") }
    }
}

// File-private refs response to avoid collision with RepositoryDetailViewModel's private type
private struct RefsResponseLocal: Decodable, Sendable {
    let repository: RefsRepoLocal?
}

private struct RefsRepoLocal: Decodable, Sendable {
    let references: RefsPageLocal
}

private struct RefsPageLocal: Decodable, Sendable {
    let results: [Reference]
    let cursor: String?
}
