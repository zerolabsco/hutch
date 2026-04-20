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
    func failedBuildsWithinLookbackExcludeOlderFailures() {
        let now = Date(timeIntervalSince1970: 60 * 60 * 24 * 20)
        let recentFailure = HomeBuildItem(
            job: JobSummary(
                id: 1,
                created: now.addingTimeInterval(-(60 * 60 * 24)),
                updated: now.addingTimeInterval(-(60 * 60 * 24)),
                status: .failed,
                note: nil,
                tags: [],
                visibility: nil,
                image: nil,
                tasks: []
            ),
            repositoryName: nil,
            repositoryOwner: nil
        )
        let oldFailure = HomeBuildItem(
            job: JobSummary(
                id: 2,
                created: now.addingTimeInterval(-(60 * 60 * 24 * 10)),
                updated: now.addingTimeInterval(-(60 * 60 * 24 * 10)),
                status: .timeout,
                note: nil,
                tags: [],
                visibility: nil,
                image: nil,
                tasks: []
            ),
            repositoryName: nil,
            repositoryOwner: nil
        )
        let recentSuccess = HomeBuildItem(
            job: JobSummary(
                id: 3,
                created: now.addingTimeInterval(-(60 * 60 * 24)),
                updated: now.addingTimeInterval(-(60 * 60 * 24)),
                status: .success,
                note: nil,
                tags: [],
                visibility: nil,
                image: nil,
                tasks: []
            ),
            repositoryName: nil,
            repositoryOwner: nil
        )

        let filtered = HomeViewModel.failedBuilds(
            in: [recentFailure, oldFailure, recentSuccess],
            lookbackDays: 7,
            now: now,
            calendar: Calendar(identifier: .gregorian)
        )

        #expect(filtered.map(\.job.id) == [1])
    }

    @Test
    func failedBuildLookbackDaysFallsBackToDefaultWhenUnsetOrInvalid() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        #expect(HomeViewModel.failedBuildLookbackDays(defaults: defaults) == HomeViewModel.defaultFailedBuildLookbackDays)

        defaults.set(99, forKey: AppStorageKeys.homeFailedBuildLookbackDays)

        #expect(HomeViewModel.failedBuildLookbackDays(defaults: defaults) == HomeViewModel.defaultFailedBuildLookbackDays)
    }

    @Test
    func deduplicateInboxThreadsCollapsesMessagesIntoOneThreadSummary() {
        let list = InboxMailingListReference(
            id: 1,
            rid: "list",
            name: "hutch-devel",
            owner: Entity(canonicalName: "~owner")
        )
        let first = InboxThreadSummary(
            rootEmailID: 10,
            rootMessageID: "message-1",
            threadRootEmailIDs: [10],
            threadRootMessageIDs: ["message-1"],
            listID: list.id,
            listRID: list.rid,
            listName: list.name,
            listOwner: list.owner,
            subject: "Re: [PATCH] add search",
            latestSender: Entity(canonicalName: "~alice"),
            lastActivityAt: Date(timeIntervalSince1970: 100),
            messageCount: 1,
            repo: "hutch",
            containsPatch: true,
            isUnread: true
        )
        let second = InboxThreadSummary(
            rootEmailID: 11,
            rootMessageID: "message-2",
            threadRootEmailIDs: [11],
            threadRootMessageIDs: ["message-2"],
            listID: list.id,
            listRID: list.rid,
            listName: list.name,
            listOwner: list.owner,
            subject: "[PATCH] add search",
            latestSender: Entity(canonicalName: "~bob"),
            lastActivityAt: Date(timeIntervalSince1970: 200),
            messageCount: 2,
            repo: "hutch",
            containsPatch: true,
            isUnread: true
        )

        let deduplicated = HomeViewModel.deduplicateInboxThreads([first, second])

        #expect(deduplicated.count == 1)
        #expect(deduplicated[0].rootEmailID == 11)
        #expect(deduplicated[0].threadRootEmailIDs == [10, 11])
        #expect(deduplicated[0].threadRootMessageIDs == ["message-1", "message-2"])
        #expect(deduplicated[0].messageCount == 2)
    }

    @Test
    func matchesCurrentUserAssigneeNormalizesCanonicalNameAndUsername() {
        let currentUser = User(
            id: 42,
            created: nil,
            updated: nil,
            username: "owner",
            canonicalName: "~owner",
            email: "owner@example.com",
            url: nil,
            location: nil,
            bio: nil,
            avatar: nil,
            pronouns: nil,
            userType: nil,
            receivesPaidServices: nil,
            suspensionNotice: nil
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

    @Test
    func buildItemsAreSortedForTriage() {
        let jobs = [
            makeJob(id: 1, status: .success, created: Date(timeIntervalSince1970: 10)),
            makeJob(id: 2, status: .running, created: Date(timeIntervalSince1970: 20)),
            makeJob(id: 3, status: .failed, created: Date(timeIntervalSince1970: 30))
        ]

        let sorted = HomeViewModel.buildItems(from: jobs)

        #expect(sorted.map(\.job.id) == [3, 2, 1])
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
