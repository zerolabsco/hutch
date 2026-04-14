import Foundation

private struct HgUpdateRepositoryResponse: Decodable, Sendable {
    let updateRepository: HgUpdatedRepository
}

private struct HgUpdatedRepository: Decodable, Sendable {
    let id: Int
}

private struct HgRepositoryInfoResponse: Decodable, Sendable {
    let repository: HgRepositoryInfo?
}

private struct HgRepositoryInfo: Decodable, Sendable {
    let description: String?
    let visibility: Visibility
    let nonPublishing: Bool?
}

private struct HgACLResponse: Decodable, Sendable {
    let repository: HgACLRepository?
}

private struct HgACLRepository: Decodable, Sendable {
    let accessControlList: HgACLPage
}

private struct HgACLPage: Decodable, Sendable {
    let results: [HgACLEntry]
    let cursor: String?
}

private struct HgUpdateACLResponse: Decodable, Sendable {
    let updateACL: HgACLEntry
}

private struct HgDeleteACLResponse: Decodable, Sendable {
    let deleteACL: HgDeletedACL
}

private struct HgDeletedACL: Decodable, Sendable {
    let id: Int
}

private struct HgDeleteRepositoryResponse: Decodable, Sendable {
    let deleteRepository: HgDeletedRepository
}

private struct HgDeletedRepository: Decodable, Sendable {
    let id: Int
}

struct HgACLEntry: Decodable, Sendable, Identifiable {
    let id: Int
    let mode: String
    let entity: Entity
}

@Observable
@MainActor
final class HgRepositorySettingsViewModel {
    let repositoryId: Int
    let repositoryRid: String
    let repositoryName: String
    private let client: SRHTClient
    private var initialDescription: String
    private var initialVisibility: Visibility

    var editedDescription: String
    var editedVisibility: Visibility
    var editedNonPublishing: Bool
    var isSavingInfo = false
    private(set) var loadedNonPublishing = false

    private(set) var acls: [HgACLEntry] = []
    private(set) var isLoadingACLs = false
    var newACLEntity = ""
    var newACLMode = "RO"
    var isAddingACL = false
    var isDeletingACL = false

    var histeditRevision = ""
    var isDeleting = false
    var didDelete = false
    var error: String?

    var normalizedEditedDescription: String {
        editedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isInfoDirty: Bool {
        normalizedEditedDescription != initialDescription ||
        editedVisibility != initialVisibility ||
        editedNonPublishing != loadedNonPublishing
    }

    init(repository: RepositorySummary, client: SRHTClient) {
        self.repositoryId = repository.id
        self.repositoryRid = repository.rid
        self.repositoryName = repository.name
        self.client = client
        let description = repository.description ?? ""
        self.initialDescription = description
        self.initialVisibility = repository.visibility
        self.editedDescription = description
        self.editedVisibility = repository.visibility
        self.editedNonPublishing = false
    }

    private static let updateRepositoryMutation = """
    mutation updateRepository($id: Int!, $input: RepoInput!) {
        updateRepository(id: $id, input: $input) {
            id
        }
    }
    """

    private static let accessControlListQuery = """
    query hgAccessControlList($rid: ID!) {
        repository(rid: $rid) {
            accessControlList {
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
            id
            mode
            entity { canonicalName }
        }
    }
    """

    private static let deleteACLMutation = """
    mutation deleteACL($id: Int!) {
        deleteACL(id: $id) { id }
    }
    """

    private static let deleteRepositoryMutation = """
    mutation deleteRepository($id: Int!) {
        deleteRepository(id: $id) { id }
    }
    """

    private static let repositoryInfoQuery = """
    query hgRepositoryInfo($rid: ID!) {
        repository(rid: $rid) {
            description
            visibility
            nonPublishing
        }
    }
    """

    func loadRepositoryInfo() async {
        error = nil

        do {
            let result = try await client.execute(
                service: .hg,
                query: Self.repositoryInfoQuery,
                variables: ["rid": repositoryRid],
                responseType: HgRepositoryInfoResponse.self
            )

            if let repository = result.repository {
                let description = repository.description ?? ""
                initialDescription = description
                initialVisibility = repository.visibility
                editedDescription = description
                editedVisibility = repository.visibility
                let nonPublishing = repository.nonPublishing ?? false
                editedNonPublishing = nonPublishing
                loadedNonPublishing = nonPublishing
            }
        } catch {
            self.error = error.userFacingMessage
        }
    }

    func saveInfo() async -> Bool {
        isSavingInfo = true
        defer { isSavingInfo = false }
        error = nil

        do {
            let input: [String: any Sendable] = [
                "description": normalizedEditedDescription,
                "visibility": editedVisibility.rawValue,
                "nonPublishing": editedNonPublishing
            ]
            _ = try await client.execute(
                service: .hg,
                query: Self.updateRepositoryMutation,
                variables: ["id": repositoryId, "input": input],
                responseType: HgUpdateRepositoryResponse.self
            )
            initialDescription = normalizedEditedDescription
            initialVisibility = editedVisibility
            loadedNonPublishing = editedNonPublishing
            return true
        } catch {
            self.error = error.userFacingMessage
            return false
        }
    }

    func loadACLs() async {
        guard !isLoadingACLs else { return }
        isLoadingACLs = true
        defer { isLoadingACLs = false }
        error = nil

        do {
            let result = try await client.execute(
                service: .hg,
                query: Self.accessControlListQuery,
                variables: ["rid": repositoryRid],
                responseType: HgACLResponse.self
            )
            acls = result.repository?.accessControlList.results ?? []
        } catch {
            self.error = error.userFacingMessage
        }
    }

    func addACL() async {
        let rawEntity = newACLEntity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawEntity.isEmpty else { return }
        let entity = hgCanonicalEntity(from: rawEntity)
        isAddingACL = true
        defer { isAddingACL = false }
        error = nil

        do {
            let result = try await client.execute(
                service: .hg,
                query: Self.updateACLMutation,
                variables: [
                    "repoId": repositoryId,
                    "mode": newACLMode,
                    "entity": entity
                ],
                responseType: HgUpdateACLResponse.self
            )
            if let index = acls.firstIndex(where: { $0.id == result.updateACL.id }) {
                acls[index] = result.updateACL
            } else {
                acls.append(result.updateACL)
            }
            newACLEntity = ""
        } catch {
            self.error = error.userFacingMessage
        }
    }

    private func hgCanonicalEntity(from input: String) -> String {
        let username = input.hasPrefix("~") ? String(input.dropFirst()) : input
        return "~\(username)"
    }

    func deleteACL(_ entry: HgACLEntry) async {
        isDeletingACL = true
        defer { isDeletingACL = false }
        error = nil

        do {
            _ = try await client.execute(
                service: .hg,
                query: Self.deleteACLMutation,
                variables: ["id": entry.id],
                responseType: HgDeleteACLResponse.self
            )
            acls.removeAll { $0.id == entry.id }
        } catch {
            self.error = error.userFacingMessage
        }
    }

    func deleteRepository() async {
        isDeleting = true
        defer { isDeleting = false }
        error = nil

        do {
            _ = try await client.execute(
                service: .hg,
                query: Self.deleteRepositoryMutation,
                variables: ["id": repositoryId],
                responseType: HgDeleteRepositoryResponse.self
            )
            didDelete = true
        } catch {
            self.error = error.userFacingMessage
        }
    }
}
