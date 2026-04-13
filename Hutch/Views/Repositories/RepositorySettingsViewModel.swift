import Foundation

// MARK: - Response types

private struct UpdateRepoResponse: Decodable, Sendable {
    let updateRepository: UpdatedRepo
}

private struct UpdateRepoInfoResponse: Decodable, Sendable {
    let updateRepository: UpdatedRepoInfo
}

private struct UpdatedRepo: Decodable, Sendable {
    let id: Int?
    let rid: String?
    let name: String
    let description: String?
    let visibility: Visibility?
}

private struct UpdatedRepoInfo: Decodable, Sendable {
    let id: Int
}

private struct DeleteRepoResponse: Decodable, Sendable {
    let deleteRepository: DeletedRepo
}

private struct DeletedRepo: Decodable, Sendable {
    let id: Int
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
    private let originalEditedHead: String
    var isSavingInfo = false

    // MARK: - Rename fields

    var editedName: String
    var isRenaming = false

    // MARK: - Delete state

    var isDeleting = false

    // MARK: - Branches (for HEAD picker)

    var branches: [ReferenceDetail]

    // MARK: - Results

    var error: String?
    var updatedName: String?
    var didDelete = false

    init(
        repository: RepositorySummary,
        branches: [ReferenceDetail],
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
        let initialEditedHead: String
        if let head = repository.head?.name {
            initialEditedHead = head.replacingOccurrences(of: "refs/heads/", with: "")
        } else {
            initialEditedHead = "main"
        }
        self.editedHead = initialEditedHead
        self.originalEditedHead = initialEditedHead
    }

    // MARK: - Update Repository Info

    private static let updateRepoMutation = """
    mutation updateRepository($id: Int!, $input: RepoInput!) {
        updateRepository(id: $id, input: $input) {
            id rid name description visibility
        }
    }
    """

    private static let updateRepoInfoMutation = """
    mutation updateRepository($id: Int!, $input: RepoInput!) {
        updateRepository(id: $id, input: $input) {
            id
        }
    }
    """

    func saveInfo() async -> Bool {
        isSavingInfo = true
        defer { isSavingInfo = false }
        error = nil

        do {
            var input: [String: any Sendable] = [
                "description": editedDescription,
                "visibility": editedVisibility.rawValue
            ]
            if let headReference = selectedHeadReferenceForSave() {
                input["HEAD"] = headReference
            }
            _ = try await client.execute(
                service: service,
                query: Self.updateRepoInfoMutation,
                variables: ["id": repositoryId, "input": input],
                responseType: UpdateRepoInfoResponse.self
            )
            return true
        } catch {
            self.error = error.userFacingMessage
            return false
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
            self.error = error.userFacingMessage
        }
    }

    static func gitHeadReference(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.hasPrefix("refs/") {
            return trimmed
        }
        return "refs/heads/\(trimmed)"
    }

    func selectedHeadReferenceForSave() -> String? {
        let normalizedEditedHead = editedHead.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEditedHead != originalEditedHead else {
            return nil
        }

        return branches.first {
            $0.name.replacingOccurrences(of: "refs/heads/", with: "") == normalizedEditedHead
        }?.name
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
            self.error = error.userFacingMessage
        }
    }
}
