import Foundation

// MARK: - Response types

private struct UpdateRepoResponse: Decodable, Sendable {
    let updateRepository: UpdatedRepo
}

private struct UpdatedRepo: Decodable, Sendable {
    let id: Int
    let rid: String
    let name: String
    let description: String?
    let visibility: Visibility
}

private struct ACLResponse: Decodable, Sendable {
    let repository: ACLRepository?
}

private struct ACLRepository: Decodable, Sendable {
    let acls: ACLPage
}

private struct ACLPage: Decodable, Sendable {
    let results: [ACLEntry]
    let cursor: String?
}

private struct UpdateACLResponse: Decodable, Sendable {
    let updateACL: ACLEntry
}

private struct DeleteACLResponse: Decodable, Sendable {
    let deleteACL: DeletedACL
}

private struct DeletedACL: Decodable, Sendable {
    let id: Int
}

private struct DeleteRepoResponse: Decodable, Sendable {
    let deleteRepository: DeletedRepo
}

private struct DeletedRepo: Decodable, Sendable {
    let id: Int
}

// MARK: - ACL Model

struct ACLEntry: Decodable, Sendable, Identifiable {
    let id: Int
    let mode: String
    let entity: Entity
}

// MARK: - View Model

@Observable
@MainActor
final class RepositorySettingsViewModel {

    let repositoryId: Int
    let repositoryRid: String
    let service: SRHTService
    private let client: SRHTClient

    // MARK: - Info fields

    var editedDescription: String
    var editedVisibility: Visibility
    var editedHead: String
    var isSavingInfo = false

    // MARK: - Rename fields

    var editedName: String
    var isRenaming = false

    // MARK: - ACL state

    private(set) var acls: [ACLEntry] = []
    private(set) var isLoadingACLs = false
    var newACLEntity = ""
    var newACLMode = "RO"
    var isAddingACL = false
    var isDeletingACL = false

    // MARK: - Delete state

    var isDeleting = false

    // MARK: - Branches (for HEAD picker)

    var branches: [Reference]

    // MARK: - Results

    var error: String?
    var updatedName: String?
    var didDelete = false

    init(
        repository: RepositorySummary,
        branches: [Reference],
        client: SRHTClient
    ) {
        self.repositoryId = repository.id
        self.repositoryRid = repository.rid
        self.service = repository.service
        self.client = client
        self.editedDescription = repository.description ?? ""
        self.editedVisibility = repository.visibility
        self.editedName = repository.name
        self.branches = branches

        // Extract branch name from HEAD reference
        if let head = repository.head?.name {
            self.editedHead = head.replacingOccurrences(of: "refs/heads/", with: "")
        } else {
            self.editedHead = "main"
        }
    }

    // MARK: - Update Repository Info

    private static let updateRepoMutation = """
    mutation updateRepository($id: Int!, $input: RepoInput!) {
        updateRepository(id: $id, input: $input) {
            id rid name description visibility
        }
    }
    """

    func saveInfo() async {
        isSavingInfo = true
        defer { isSavingInfo = false }
        error = nil

        do {
            let input: [String: any Sendable] = [
                "description": editedDescription,
                "visibility": editedVisibility.rawValue,
                "HEAD": editedHead
            ]
            _ = try await client.execute(
                service: service,
                query: Self.updateRepoMutation,
                variables: ["id": repositoryId, "input": input],
                responseType: UpdateRepoResponse.self
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Rename

    func rename() async {
        isRenaming = true
        defer { isRenaming = false }
        error = nil

        do {
            let input: [String: any Sendable] = [
                "name": editedName
            ]
            let result = try await client.execute(
                service: service,
                query: Self.updateRepoMutation,
                variables: ["id": repositoryId, "input": input],
                responseType: UpdateRepoResponse.self
            )
            updatedName = result.updateRepository.name
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - ACLs

    private static let aclsQuery = """
    query acls($rid: ID!) {
        repository(rid: $rid) {
            acls {
                results {
                    id
                    mode
                    entity { canonicalName }
                }
                cursor
            }
        }
    }
    """

    private static let updateACLMutation = """
    mutation updateACL($repoId: Int!, $mode: AccessMode!, $entity: String!) {
        updateACL(repoId: $repoId, mode: $mode, entity: $entity) {
            id mode entity { canonicalName }
        }
    }
    """

    private static let deleteACLMutation = """
    mutation deleteACL($id: Int!) {
        deleteACL(id: $id) { id }
    }
    """

    private static let userLookupQuery = """
    query userLookup($username: String!) {
        user(username: $username) {
            id
            username
            canonicalName
        }
    }
    """

    func loadACLs() async {
        guard !isLoadingACLs else { return }
        isLoadingACLs = true
        defer { isLoadingACLs = false }

        do {
            let result = try await client.execute(
                service: service,
                query: Self.aclsQuery,
                variables: ["rid": repositoryRid],
                responseType: ACLResponse.self
            )
            acls = result.repository?.acls.results ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addACL() async {
        let entity = newACLEntity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entity.isEmpty else { return }
        isAddingACL = true
        defer { isAddingACL = false }
        error = nil

        do {
            let result = try await client.execute(
                service: service,
                query: Self.updateACLMutation,
                variables: [
                    "repoId": repositoryId,
                    "mode": newACLMode,
                    "entity": entity
                ],
                responseType: UpdateACLResponse.self
            )
            // Replace existing entry or append
            if let index = acls.firstIndex(where: { $0.id == result.updateACL.id }) {
                acls[index] = result.updateACL
            } else {
                acls.append(result.updateACL)
            }
            newACLEntity = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteACL(_ entry: ACLEntry) async {
        isDeletingACL = true
        defer { isDeletingACL = false }
        error = nil

        do {
            _ = try await client.execute(
                service: service,
                query: Self.deleteACLMutation,
                variables: ["id": entry.id],
                responseType: DeleteACLResponse.self
            )
            acls.removeAll { $0.id == entry.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Delete Repository

    private static let deleteRepoMutation = """
    mutation deleteRepository($id: Int!) {
        deleteRepository(id: $id) { id }
    }
    """

    func deleteRepository() async {
        isDeleting = true
        defer { isDeleting = false }
        error = nil

        do {
            _ = try await client.execute(
                service: service,
                query: Self.deleteRepoMutation,
                variables: ["id": repositoryId],
                responseType: DeleteRepoResponse.self
            )
            didDelete = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
