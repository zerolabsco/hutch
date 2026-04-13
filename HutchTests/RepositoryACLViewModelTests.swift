import Foundation
import Testing
@testable import Hutch

struct RepositoryACLViewModelTests {

    @Test
    @MainActor
    func addValidationRejectsOwnerAndDuplicates() async {
        let service = MockRepositoryACLService()
        service.fetchResponses = [[
            RepositoryACLEntry(
                id: 2,
                mode: .ro,
                entity: Entity(canonicalName: "~alice")
            )
        ]]
        let viewModel = RepositoryACLViewModel(repository: makeRepository(), service: service)
        viewModel.addUsername = "~owner"
        #expect(viewModel.addValidationMessage == "The repository owner already has access.")

        await viewModel.load()
        viewModel.addUsername = "alice"
        #expect(viewModel.addValidationMessage == "That user already has access.")
    }

    @Test
    @MainActor
    func addEntryRefreshesListAfterSuccess() async {
        let service = MockRepositoryACLService()
        service.fetchResponses = [[
            RepositoryACLEntry(
                id: 2,
                mode: .rw,
                entity: Entity(canonicalName: "~alice")
            )
        ]]

        let viewModel = RepositoryACLViewModel(repository: makeRepository(), service: service)
        viewModel.addUsername = "alice"
        viewModel.addMode = .rw

        let didAdd = await viewModel.addEntry()

        #expect(didAdd)
        #expect(service.upsertRequests == [MockRepositoryACLService.UpsertRequest(repositoryId: 1, entity: "~alice", mode: .rw)])
        #expect(service.fetchRequestRids == ["rid-1"])
        #expect(viewModel.visibleEntries.map(\.entity.canonicalName) == ["~alice"])
        #expect(viewModel.addUsername.isEmpty)
    }

    @Test
    @MainActor
    func permissionUpdateFailureLeavesExistingEntryUntouched() async {
        let service = MockRepositoryACLService()
        service.upsertError = SRHTError.httpError(500)

        let entry = RepositoryACLEntry(
            id: 2,
            mode: .ro,
            entity: Entity(canonicalName: "~alice")
        )
        let viewModel = RepositoryACLViewModel(repository: makeRepository(), service: service)
        service.fetchResponses = [[entry]]
        await viewModel.load()

        await viewModel.updatePermission(for: entry, to: .rw)

        #expect(viewModel.visibleEntries.first?.mode == .ro)
        #expect(viewModel.updatingEntryIDs.isEmpty)
        #expect(viewModel.error != nil)
    }

    @Test
    @MainActor
    func removeFailureKeepsEntryVisible() async {
        let service = MockRepositoryACLService()
        service.deleteError = SRHTError.httpError(500)

        let entry = RepositoryACLEntry(
            id: 2,
            mode: .ro,
            entity: Entity(canonicalName: "~alice")
        )
        let viewModel = RepositoryACLViewModel(repository: makeRepository(), service: service)
        service.fetchResponses = [[entry]]
        await viewModel.load()

        await viewModel.removeEntry(entry)

        #expect(viewModel.visibleEntries.map(\.id) == [2])
        #expect(viewModel.deletingEntryIDs.isEmpty)
        #expect(viewModel.error != nil)
    }

    @Test
    @MainActor
    func initialLoadFailureSetsBlockingErrorState() async {
        let service = MockRepositoryACLService()
        service.fetchError = SRHTError.httpError(500)

        let viewModel = RepositoryACLViewModel(repository: makeRepository(), service: service)

        await viewModel.load()

        #expect(viewModel.loadError != nil)
        #expect(viewModel.visibleEntries.isEmpty)
    }

    @MainActor
    private func makeRepository() -> RepositorySummary {
        RepositorySummary(
            id: 1,
            rid: "rid-1",
            service: .git,
            name: "repo",
            description: nil,
            visibility: .public,
            updated: .now,
            owner: Entity(canonicalName: "~owner"),
            head: nil
        )
    }
}

@MainActor
private final class MockRepositoryACLService: RepositoryACLServicing {
    struct UpsertRequest: Equatable {
        let repositoryId: Int
        let entity: String
        let mode: AccessMode
    }

    var fetchResponses: [[RepositoryACLEntry]] = []
    var fetchError: Error?
    var upsertResponse = RepositoryACLEntry(
        id: 2,
        mode: .ro,
        entity: Entity(canonicalName: "~alice")
    )
    var upsertError: Error?
    var deleteError: Error?

    private(set) var fetchRequestRids: [String] = []
    private(set) var upsertRequests: [UpsertRequest] = []
    private(set) var deleteRequestIDs: [Int] = []

    func fetchACLs(repositoryRid: String) async throws -> [RepositoryACLEntry] {
        fetchRequestRids.append(repositoryRid)
        if let fetchError {
            throw fetchError
        }
        if !fetchResponses.isEmpty {
            return fetchResponses.removeFirst()
        }
        return []
    }

    func upsertACL(repositoryId: Int, entity: String, mode: AccessMode) async throws -> RepositoryACLEntry {
        upsertRequests.append(UpsertRequest(repositoryId: repositoryId, entity: entity, mode: mode))
        if let upsertError {
            throw upsertError
        }
        return RepositoryACLEntry(id: upsertResponse.id, mode: mode, entity: Entity(canonicalName: entity))
    }

    func deleteACL(entryId: Int) async throws {
        deleteRequestIDs.append(entryId)
        if let deleteError {
            throw deleteError
        }
    }
}
