import Foundation

private struct UpdateRepositoryResponse: Decodable, Sendable {
    let updateRepository: UpdatedRepositoryPayload
}

private struct UpdatedRepositoryPayload: Decodable, Sendable {
    let id: Int
    let rid: String
    let name: String
    let description: String?
    let visibility: Visibility
    let updated: Date
    let head: Reference?

    enum CodingKeys: String, CodingKey {
        case id, rid, name, description, visibility, updated
        case head = "HEAD"
    }

    func repositorySummary(using owner: Entity, service: SRHTService) -> RepositorySummary {
        RepositorySummary(
            fields: .init(
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
        )
    }
}

private struct DeleteRepositoryResponse: Decodable, Sendable {
    let deleteRepository: DeletedRepositoryPayload
}

private struct DeletedRepositoryPayload: Decodable, Sendable {
    let id: Int
}

@Observable
@MainActor
final class RepositorySettingsViewModel {
    let repositoryId: Int
    let repositoryRid: String
    let service: SRHTService

    private let client: SRHTClient
    private(set) var repository: RepositorySummary

    var editedName: String
    var editedDescription: String
    var editedVisibility: Visibility
    var editedHead: String

    private(set) var branches: [ReferenceDetail]
    var isSavingMetadata = false
    var isSavingDefaultBranch = false
    var isUpdatingVisibility = false
    var isDeleting = false
    var error: String?
    var didDelete = false

    var isMutating: Bool {
        isSavingMetadata || isSavingDefaultBranch || isUpdatingVisibility || isDeleting
    }

    var currentDefaultBranchName: String {
        repository.defaultBranchName ?? "Not set"
    }

    var availableBranchNames: [String] {
        branches.map { RepositorySummary.displayBranchName(for: $0.name) }
    }

    var normalizedEditedName: String {
        editedName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedEditedDescription: String {
        editedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var metadataValidationMessage: String? {
        Self.metadataValidationMessage(for: normalizedEditedName)
    }

    var defaultBranchValidationMessage: String? {
        guard !branches.isEmpty else {
            return "This repository doesn't have any branches yet."
        }
        let normalizedHead = editedHead.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHead.isEmpty else {
            return "Select a default branch."
        }
        guard availableBranchNames.contains(normalizedHead) else {
            return "Select one of the available branches."
        }
        return nil
    }

    var isMetadataDirty: Bool {
        normalizedEditedName != repository.name ||
        normalizedEditedDescription != (repository.description ?? "")
    }

    var isDefaultBranchDirty: Bool {
        editedHead.trimmingCharacters(in: .whitespacesAndNewlines) != (repository.defaultBranchName ?? "")
    }

    var isVisibilityDirty: Bool {
        editedVisibility != repository.visibility
    }

    init(
        repository: RepositorySummary,
        branches: [ReferenceDetail],
        client: SRHTClient
    ) {
        self.repositoryId = repository.id
        self.repositoryRid = repository.rid
        self.service = repository.service
        self.client = client
        self.repository = repository
        self.branches = branches
        self.editedName = repository.name
        self.editedDescription = repository.description ?? ""
        self.editedVisibility = repository.visibility
        self.editedHead = repository.defaultBranchName ?? ""
    }

    private static let updateRepositoryMutation = """
    mutation updateRepository($id: Int!, $input: RepoInput!) {
        updateRepository(id: $id, input: $input) {
            id
            rid
            name
            description
            visibility
            updated
            HEAD { name target }
        }
    }
    """

    private static let deleteRepositoryMutation = """
    mutation deleteRepository($id: Int!) {
        deleteRepository(id: $id) { id }
    }
    """

    func saveMetadata() async -> RepositorySummary? {
        guard !isMutating else { return nil }
        if let metadataValidationMessage {
            error = metadataValidationMessage
            return nil
        }
        guard isMetadataDirty else { return repository }

        isSavingMetadata = true
        defer { isSavingMetadata = false }
        error = nil

        let input = metadataInputForSave()

        do {
            return try await updateRepository(with: input)
        } catch {
            self.error = "Couldn't update repository details. \(error.userFacingMessage)"
            return nil
        }
    }

    func saveDefaultBranch() async -> RepositorySummary? {
        guard !isMutating else { return nil }
        if let defaultBranchValidationMessage {
            error = defaultBranchValidationMessage
            return nil
        }
        guard isDefaultBranchDirty else { return repository }
        guard let headReference = selectedHeadReferenceForSave() else {
            error = "Select one of the available branches."
            return nil
        }

        isSavingDefaultBranch = true
        defer { isSavingDefaultBranch = false }
        error = nil

        do {
            return try await updateRepository(with: ["HEAD": headReference])
        } catch {
            self.error = "Couldn't update the default branch. \(error.userFacingMessage)"
            return nil
        }
    }

    func updateVisibility() async -> RepositorySummary? {
        guard !isMutating else { return nil }
        guard isVisibilityDirty else { return repository }

        isUpdatingVisibility = true
        defer { isUpdatingVisibility = false }
        error = nil

        do {
            return try await updateRepository(with: ["visibility": editedVisibility.rawValue])
        } catch {
            self.error = "Couldn't update visibility. \(error.userFacingMessage)"
            editedVisibility = repository.visibility
            return nil
        }
    }

    func deleteRepository() async {
        guard !isMutating else { return }

        isDeleting = true
        defer { isDeleting = false }
        error = nil

        do {
            _ = try await client.execute(
                service: service,
                query: Self.deleteRepositoryMutation,
                variables: ["id": repositoryId],
                responseType: DeleteRepositoryResponse.self
            )
            didDelete = true
        } catch {
            self.error = error.userFacingMessage
        }
    }

    private func updateRepository(with input: [String: any Sendable]) async throws -> RepositorySummary {
        let result = try await client.execute(
            service: service,
            query: Self.updateRepositoryMutation,
            variables: ["id": repositoryId, "input": input],
            responseType: UpdateRepositoryResponse.self
        )
        let updatedRepository = result.updateRepository.repositorySummary(
            using: repository.owner,
            service: service
        )
        apply(updatedRepository)
        return updatedRepository
    }

    private func apply(_ updatedRepository: RepositorySummary) {
        repository = updatedRepository
        editedName = updatedRepository.name
        editedDescription = updatedRepository.description ?? ""
        editedVisibility = updatedRepository.visibility
        editedHead = updatedRepository.defaultBranchName ?? ""
    }

    static func metadataValidationMessage(for name: String) -> String? {
        guard !name.isEmpty else {
            return "Enter a repository name."
        }
        guard !name.contains("/") else {
            return "Repository names can't contain '/'."
        }
        guard name.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return "Repository names can't contain spaces."
        }
        return nil
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
        guard normalizedEditedHead != (repository.defaultBranchName ?? "") else {
            return nil
        }

        return branches.first {
            RepositorySummary.displayBranchName(for: $0.name) == normalizedEditedHead
        }?.name
    }

    func metadataInputForSave() -> [String: any Sendable] {
        var input: [String: any Sendable] = [:]

        if normalizedEditedName != repository.name {
            input["name"] = normalizedEditedName
        }

        if normalizedEditedDescription != (repository.description ?? "") {
            input["description"] = normalizedEditedDescription.isEmpty ? Optional<String>.none as String? : normalizedEditedDescription
        }

        return input
    }
}
