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
        #expect(link == .repository(owner: "~user", repo: "repo"))
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
