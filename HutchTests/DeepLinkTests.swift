import Foundation
import Testing
@testable import Hutch

struct DeepLinkTests {

    @Test
    func parsesHomeLink() {
        let link = DeepLink(url: URL(string: "hutch://home")!)
        #expect(link == .home)
    }

    @Test
    func parsesNilPathAsHome() {
        let link = DeepLink(url: URL(string: "hutch://")!)
        #expect(link == .home)
    }

    @Test
    func parsesRepositoryLink() {
        let link = DeepLink(url: URL(string: "hutch://git/~user/repo")!)
        #expect(link == .repository(owner: "~user", repo: "repo"))
    }

    @Test
    func parsesTicketLink() {
        let link = DeepLink(url: URL(string: "hutch://todo/~owner/tracker/42")!)
        #expect(link == .ticket(owner: "~owner", tracker: "tracker", ticketId: 42))
    }

    @Test
    func parsesBuildJobLink() {
        let link = DeepLink(url: URL(string: "hutch://builds/12345")!)
        #expect(link == .build(jobId: 12345))
    }

    @Test
    func parsesBuildsTabLink() {
        let link = DeepLink(url: URL(string: "hutch://builds")!)
        #expect(link == .buildsTab)
    }

    @Test
    func parsesRepositoriesTabLink() {
        let link = DeepLink(url: URL(string: "hutch://repositories")!)
        #expect(link == .repositoriesTab)
    }

    @Test
    func parsesTrackersTabLink() {
        let link = DeepLink(url: URL(string: "hutch://trackers")!)
        #expect(link == .trackersTab)
    }

    @Test
    func parsesSystemStatusLink() {
        let link = DeepLink(url: URL(string: "hutch://status")!)
        #expect(link == .systemStatus)
    }

    @Test
    func parsesLookupLink() {
        let link = DeepLink(url: URL(string: "hutch://lookup")!)
        #expect(link == .lookup)
    }

    @Test
    func rejectsNonHutchScheme() {
        let link = DeepLink(url: URL(string: "https://example.com/home")!)
        #expect(link == nil)
    }

    @Test
    func rejectsUnknownPath() {
        let link = DeepLink(url: URL(string: "hutch://unknown")!)
        #expect(link == nil)
    }

    @Test
    func rejectsTicketLinkWithNonNumericId() {
        let link = DeepLink(url: URL(string: "hutch://todo/~owner/tracker/abc")!)
        #expect(link == nil)
    }

    @Test
    func rejectsBuildLinkWithNonNumericId() {
        let link = DeepLink(url: URL(string: "hutch://builds/abc")!)
        #expect(link == nil)
    }
}
