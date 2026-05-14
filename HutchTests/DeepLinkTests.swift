import Foundation
import Testing
@testable import Hutch

struct DeepLinkTests {

    @Test
    func parsesHomeLink() {
        let link = DeepLink(url: HutchDeepLinkURL.home)
        #expect(link == .home)
    }

    @Test
    func parsesNilPathAsHome() {
        let link = DeepLink(url: HutchDeepLinkURL.emptyHost)
        #expect(link == .home)
    }

    @Test
    func parsesRepositoryLink() {
        let link = DeepLink(url: HutchDeepLinkURL.repositoryGit)
        #expect(link == .repository(service: .git, owner: "~user", repo: "repo"))
    }

    @Test
    func parsesHgRepositoryLink() {
        let link = DeepLink(url: HutchDeepLinkURL.repositoryHg)
        #expect(link == .repository(service: .hg, owner: "~user", repo: "repo"))
    }

    @Test
    func parsesServiceOwnerRootAsUserProfile() {
        let link = DeepLink(url: HutchDeepLinkURL.gitOwnerRoot)
        #expect(link == .userProfile(owner: "~owner"))
    }

    @Test
    func parsesTicketLink() {
        let link = DeepLink(url: HutchDeepLinkURL.ticket)
        #expect(link == .ticket(owner: "~owner", tracker: "tracker", ticketId: 42))
    }

    @Test
    func parsesBuildJobLink() {
        let link = DeepLink(url: HutchDeepLinkURL.buildJob)
        #expect(link == .build(jobId: 12345))
    }

    @Test
    func parsesBuildJobLinkWithOwnerPath() {
        let link = DeepLink(url: HutchDeepLinkURL.buildJobWithOwner)
        #expect(link == .build(jobId: 12345))
    }

    @Test
    func parsesMailingListLink() {
        let link = DeepLink(url: HutchDeepLinkURL.mailingList)
        #expect(link == .mailingList(owner: "~owner", list: "list"))
    }

    @Test
    func parsesBuildsTabLink() {
        let link = DeepLink(url: HutchDeepLinkURL.builds)
        #expect(link == .buildsTab)
    }

    @Test
    func parsesRepositoriesTabLink() {
        let link = DeepLink(url: HutchDeepLinkURL.repositories)
        #expect(link == .repositoriesTab)
    }

    @Test
    func parsesTrackersTabLink() {
        let link = DeepLink(url: HutchDeepLinkURL.trackers)
        #expect(link == .trackersTab)
    }

    @Test
    func parsesSystemStatusLink() {
        let link = DeepLink(url: HutchDeepLinkURL.status)
        #expect(link == .systemStatus)
    }

    @Test
    func parsesLookupLink() {
        let link = DeepLink(url: HutchDeepLinkURL.lookup)
        #expect(link == .lookup)
    }

    @Test
    func parsesRouteBackedNavigationLinks() {
        #expect(DeepLink(url: HutchRoute.workQueue(scope: .assigned).url) == .workQueue(scope: .assigned))
        #expect(DeepLink(url: HutchRoute.failedBuilds.url) == .failedBuilds)
        #expect(DeepLink(url: HutchRoute.search(query: "patch queue").url) == .search(query: "patch queue"))
        #expect(DeepLink(url: HutchRoute.projectDashboard(id: "project-1", title: "Hutch").url) == .projectDashboard(id: "project-1", title: "Hutch"))
    }

    @Test
    func parsesUserProfileLink() {
        let link = DeepLink(url: HutchDeepLinkURL.userProfile)
        #expect(link == .userProfile(owner: "~owner"))
    }

    @Test
    func rejectsNonHutchScheme() {
        let link = DeepLink(url: URL(string: "https://example.com/home")!)
        #expect(link == nil)
    }

    @Test
    func rejectsUnknownPath() {
        let link = DeepLink(url: HutchDeepLinkURL.unknown)
        #expect(link == nil)
    }

    @Test
    func rejectsTicketLinkWithNonNumericId() {
        let link = DeepLink(url: HutchDeepLinkURL.invalidTicketId)
        #expect(link == nil)
    }

    @Test
    func rejectsBuildLinkWithNonNumericId() {
        let link = DeepLink(url: HutchDeepLinkURL.invalidBuildId)
        #expect(link == nil)
    }
}
