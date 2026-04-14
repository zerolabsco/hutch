import Foundation
import Testing
@testable import Hutch

struct SRHTWebURLTests {
    private enum Expected {
        static let chatOrigin = "https://chat.sr.ht"
        static let statusOrigin = "https://status.sr.ht"
        static let gitRepoHTTPS = "https://git.sr.ht/~ccleberg/hutch"
        static let gitSSH = "git@git.sr.ht:~ccleberg/hutch"
        static let tracker = "https://todo.sr.ht/~ccleberg/todo"
        static let ticket = "https://todo.sr.ht/~ccleberg/todo/42"
        static let buildJob = "https://builds.sr.ht/~ccleberg/job/12"
    }

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
        #expect(SRHTWebURL.chat.absoluteString == Expected.chatOrigin)
        #expect(SRHTWebURL.status.absoluteString == Expected.statusOrigin)
    }

    @Test
    func repositoryAndCloneURLsUseStableUserScopedPaths() {
        #expect(SRHTWebURL.repository(repository)?.absoluteString == Expected.gitRepoHTTPS)
        #expect(SRHTWebURL.httpsCloneURL(repository) == Expected.gitRepoHTTPS)
        #expect(SRHTWebURL.sshCloneURL(repository) == Expected.gitSSH)
    }

    @Test
    func trackerTicketAndBuildURLsUseStableUserScopedPaths() {
        #expect(SRHTWebURL.tracker(tracker)?.absoluteString == Expected.tracker)
        #expect(SRHTWebURL.ticket(ownerUsername: "ccleberg", trackerName: "todo", ticketId: 42)?.absoluteString == Expected.ticket)
        #expect(SRHTWebURL.build(jobId: 12, ownerCanonicalName: "~ccleberg")?.absoluteString == Expected.buildJob)
    }
}
