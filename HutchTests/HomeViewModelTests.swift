import Foundation
import Testing
@testable import Hutch

struct HomeViewModelTests {

    @Test
    func failedBuildsKeepsOnlyFailedAndTimedOutJobs() {
        let jobs = [
            makeJob(id: 1, status: .success, created: Date(timeIntervalSince1970: 10)),
            makeJob(id: 2, status: .failed, created: Date(timeIntervalSince1970: 20)),
            makeJob(id: 3, status: .timeout, created: Date(timeIntervalSince1970: 30)),
            makeJob(id: 4, status: .running, created: Date(timeIntervalSince1970: 40))
        ]

        let failedBuilds = HomeViewModel.failedBuilds(from: jobs)

        #expect(failedBuilds.map(\.job.id) == [2, 3])
    }

    @Test
    func matchesCurrentUserAssigneeNormalizesCanonicalNameAndUsername() {
        let currentUser = User(
            id: 42,
            username: "owner",
            canonicalName: "~owner",
            email: "owner@example.com",
            avatar: nil
        )

        #expect(HomeViewModel.matchesCurrentUserAssignee(Entity(canonicalName: "~owner"), currentUser: currentUser))
        #expect(HomeViewModel.matchesCurrentUserAssignee(Entity(canonicalName: "owner"), currentUser: currentUser))
        #expect(HomeViewModel.matchesCurrentUserAssignee(Entity(canonicalName: currentUser.username), currentUser: currentUser))
        #expect(HomeViewModel.matchesCurrentUserAssignee(Entity(canonicalName: "~someone-else"), currentUser: currentUser) == false)
    }

    @Test
    func primaryRepositoryReferenceParsesManifestSourceURL() {
        let manifest = """
        image: alpine/latest
        sources:
          - https://git.sr.ht/~owner/hutch
        tasks:
          - true
        """

        let repository = HomeViewModel.primaryRepositoryReference(in: manifest)

        #expect(repository?.ownerCanonicalName == "~owner")
        #expect(repository?.name == "hutch")
    }

    private func makeJob(id: Int, status: JobStatus, created: Date) -> HomeJobPayload {
        HomeJobPayload(
            id: id,
            created: created,
            updated: created,
            status: status,
            note: nil,
            tags: [],
            visibility: nil,
            image: nil,
            tasks: [],
            manifest: nil
        )
    }
}
