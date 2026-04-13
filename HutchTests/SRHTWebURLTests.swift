import Foundation
import Testing
@testable import Hutch

struct SRHTWebURLTests {
    private let repository = RepositorySummary(
        id: 1,
        rid: "repo-1",
        service: .git,
        name: "hutch",
        description: nil,
        visibility: .public,
        updated: .distantPast,
        owner: Entity(canonicalName: "~ccleberg"),
        head: nil
    )
    private let tracker = TrackerSummary(
        id: 2,
        rid: "tracker-1",
        name: "todo",
        description: nil,
        visibility: .public,
        updated: .distantPast,
        owner: Entity(canonicalName: "~ccleberg")
    )

    @Test
    func browserOnlyServiceURLsUseCanonicalHosts() {
        #expect(SRHTWebURL.chat.absoluteString == "https://chat.sr.ht")
        #expect(SRHTWebURL.status.absoluteString == "https://status.sr.ht")
    }

    @Test
    func repositoryAndCloneURLsUseStableUserScopedPaths() {
        #expect(SRHTWebURL.repository(repository)?.absoluteString == "https://git.sr.ht/~ccleberg/hutch")
        #expect(SRHTWebURL.httpsCloneURL(repository) == "https://git.sr.ht/~ccleberg/hutch")
        #expect(SRHTWebURL.sshCloneURL(repository) == "git@git.sr.ht:~ccleberg/hutch")
    }

    @Test
    func trackerTicketAndBuildURLsUseStableUserScopedPaths() {
        #expect(SRHTWebURL.tracker(tracker)?.absoluteString == "https://todo.sr.ht/~ccleberg/todo")
        #expect(SRHTWebURL.ticket(ownerUsername: "ccleberg", trackerName: "todo", ticketId: 42)?.absoluteString == "https://todo.sr.ht/~ccleberg/todo/42")
        #expect(SRHTWebURL.build(jobId: 12, ownerCanonicalName: "~ccleberg")?.absoluteString == "https://builds.sr.ht/~ccleberg/job/12")
    }
}
