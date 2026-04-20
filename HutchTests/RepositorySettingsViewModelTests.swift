import Foundation
import Testing
@testable import Hutch

private struct UpdateRepositoryInfoEnvelope: Decodable {
    let updateRepository: UpdateRepositoryInfoPayload
}

private struct UpdateRepositoryInfoPayload: Decodable {
    let id: Int
}

struct RepositorySettingsViewModelTests {

    @Test
    func saveInfoResponseDecodesMinimalRepositoryPayload() throws {
        let json = """
        {
            "data": {
                "updateRepository": {
                    "id": 42
                }
            }
        }
        """

        let decoded = try JSONDecoder().decode(
            GraphQLResponse<UpdateRepositoryInfoEnvelope>.self,
            from: Data(json.utf8)
        )

        #expect(decoded.data?.updateRepository.id == 42)
    }

    @Test
    @MainActor
    func gitCanonicalEntityAddsMissingTilde() {
        #expect(RepositoryACLViewModel.canonicalEntity(from: "alice") == "~alice")
        #expect(RepositoryACLViewModel.canonicalEntity(from: "~alice") == "~alice")
        #expect(RepositoryACLViewModel.canonicalEntity(from: "  alice  ") == "~alice")
    }

    @Test
    @MainActor
    func gitHeadReferenceUsesFullBranchRef() {
        #expect(RepositorySettingsViewModel.gitHeadReference(from: "main") == "refs/heads/main")
        #expect(RepositorySettingsViewModel.gitHeadReference(from: " refs/heads/dev ") == "refs/heads/dev")
    }

    @Test
    @MainActor
    func unchangedHeadIsOmittedFromSaveInput() {
        let viewModel = RepositorySettingsViewModel(
            repository: makeRepository(headName: "refs/heads/main"),
            branches: [ReferenceDetail(name: "refs/heads/main", target: nil, date: nil)],
            client: SRHTClient(token: "test-token")
        )

        #expect(viewModel.selectedHeadReferenceForSave() == nil)
    }

    @Test
    @MainActor
    func changedHeadUsesSelectedBranchReference() {
        let viewModel = RepositorySettingsViewModel(
            repository: makeRepository(headName: "refs/heads/main"),
            branches: [
                ReferenceDetail(name: "refs/heads/main", target: nil, date: nil),
                ReferenceDetail(name: "refs/heads/dev", target: nil, date: nil)
            ],
            client: SRHTClient(token: "test-token")
        )
        viewModel.editedHead = "dev"

        #expect(viewModel.selectedHeadReferenceForSave() == "refs/heads/dev")
    }

    @Test
    @MainActor
    func bareRepositoryOmitsHeadWhenNoBranchExists() {
        let viewModel = RepositorySettingsViewModel(
            repository: makeRepository(headName: nil),
            branches: [],
            client: SRHTClient(token: "test-token")
        )

        #expect(viewModel.selectedHeadReferenceForSave() == nil)
        viewModel.editedHead = "main"
        #expect(viewModel.selectedHeadReferenceForSave() == nil)
    }

    @Test
    @MainActor
    func metadataValidationRejectsEmptyOrInvalidNames() {
        #expect(RepositorySettingsViewModel.metadataValidationMessage(for: "") == "Enter a repository name.")
        #expect(RepositorySettingsViewModel.metadataValidationMessage(for: "repo/name") == "Repository names can't contain '/'.")
        #expect(RepositorySettingsViewModel.metadataValidationMessage(for: "repo name") == "Repository names can't contain spaces.")
    }

    @Test
    @MainActor
    func metadataDirtyStateTracksNormalizedInputs() {
        let viewModel = RepositorySettingsViewModel(
            repository: makeRepository(headName: "refs/heads/main"),
            branches: [ReferenceDetail(name: "refs/heads/main", target: nil, date: nil)],
            client: SRHTClient(token: "test-token")
        )

        #expect(viewModel.isMetadataDirty == false)
        viewModel.editedDescription = "  updated  "
        #expect(viewModel.isMetadataDirty)

        viewModel.editedDescription = "desc"
        viewModel.editedName = "  repo  "
        #expect(viewModel.isMetadataDirty == false)
    }

    @Test
    @MainActor
    func metadataInputOmitsUnchangedNameWhenOnlyDescriptionChanges() {
        let viewModel = RepositorySettingsViewModel(
            repository: makeRepository(headName: "refs/heads/main"),
            branches: [ReferenceDetail(name: "refs/heads/main", target: nil, date: nil)],
            client: SRHTClient(token: "test-token")
        )
        viewModel.editedDescription = "an ios client for sourcehut"

        let input = viewModel.metadataInputForSave()

        #expect(input["name"] == nil)
        #expect(input["description"] as? String == "an ios client for sourcehut")
    }

    @Test
    @MainActor
    func metadataInputUsesNilToClearDescription() {
        let viewModel = RepositorySettingsViewModel(
            repository: makeRepository(headName: "refs/heads/main"),
            branches: [ReferenceDetail(name: "refs/heads/main", target: nil, date: nil)],
            client: SRHTClient(token: "test-token")
        )
        viewModel.editedDescription = "   "

        let input = viewModel.metadataInputForSave()

        #expect(input["name"] == nil)
        #expect(input.keys.contains("description"))
        #expect(input["description"] as? String == nil)
    }

    @MainActor
    private func makeRepository(headName: String?) -> RepositorySummary {
        RepositorySummary(
            fields: .init(
                id: 1,
                rid: "rid-1",
                service: .git,
                name: "repo",
                description: "desc",
                visibility: .publicVisibility,
                updated: .now,
                owner: Entity(canonicalName: "~owner"),
                head: headName.map { Reference(name: $0, target: nil) }
            )
        )
    }
}
