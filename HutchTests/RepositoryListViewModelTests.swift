import Foundation
import Testing
@testable import Hutch

struct RepositoryListViewModelTests {

    @Test
    @MainActor
    func searchIndexRefreshRequiresMinimumQueryLength() {
        #expect(RepositoryListViewModel.shouldRefreshSearchIndex(for: "ab") == false)
        #expect(RepositoryListViewModel.shouldRefreshSearchIndex(for: "abc") == true)
        #expect(RepositoryListViewModel.shouldRefreshSearchIndex(for: "  abc  ") == true)
    }

    @Test
    @MainActor
    func filterRepositoriesMatchesNameAndDescriptionLocally() {
        let repositories = [
            makeRepository(id: 1, service: .git, name: "Hutch", description: "SourceHut client"),
            makeRepository(id: 2, service: .hg, name: "Mail", description: "patch queue"),
            makeRepository(id: 3, service: .git, name: "Tree", description: nil)
        ]

        let nameMatches = RepositoryListViewModel.filterRepositories(repositories, matching: "hut")
        let descriptionMatches = RepositoryListViewModel.filterRepositories(repositories, matching: "patch")

        #expect(nameMatches.map(\.id) == [1])
        #expect(descriptionMatches.map(\.id) == [2])
    }

    @Test
    func buildStatusKeysParsesSourceHutRepositoryURLsFromManifest() {
        let manifest = """
        image: alpine/latest
        sources:
          - https://git.sr.ht/~owner/hutch
          - ssh://hg@hg.sr.ht/~owner/wiki
        tasks:
          - echo "build"
        """

        let keys = RepositoryListViewModel.buildStatusKeys(in: manifest)

        #expect(keys.contains("git|~owner|hutch"))
        #expect(keys.contains("hg|~owner|wiki"))
    }

    @Test
    func repositoryBuildStatusMapsJobStatesToRowStates() {
        #expect(RepositoryListViewModel.repositoryBuildStatus(for: .success) == .success)
        #expect(RepositoryListViewModel.repositoryBuildStatus(for: .running) == .running)
        #expect(RepositoryListViewModel.repositoryBuildStatus(for: .queued) == .running)
        #expect(RepositoryListViewModel.repositoryBuildStatus(for: .failed) == .failed)
        #expect(RepositoryListViewModel.repositoryBuildStatus(for: .timeout) == .failed)
    }

    @MainActor
    private func makeRepository(
        id: Int,
        service: SRHTService,
        name: String,
        description: String?
    ) -> RepositorySummary {
        RepositorySummary(
            id: id,
            rid: "rid-\(id)",
            service: service,
            name: name,
            description: description,
            visibility: .public,
            updated: Date(timeIntervalSince1970: TimeInterval(id)),
            owner: Entity(canonicalName: "~owner"),
            head: Reference(name: "main", target: nil)
        )
    }
}
