import Foundation
import Testing
@testable import Hutch

struct MailingListActivityTests {

    @Test
    func usesTheNewestArrivalOverTheRootTimestamp() {
        // The case that started this: sr.ht reports thread.updated seven seconds
        // after the root email on a thread carrying four replies, so the fallback
        // must lose to real arrival data.
        let rootInsert = Date(timeIntervalSince1970: 1_000)
        let newestReply = Date(timeIntervalSince1970: 5_000)
        let activity = MailingListActivity(newestByRootEmailID: [42: newestReply])

        #expect(activity.lastActivity(rootEmailID: 42, fallback: rootInsert) == newestReply)
    }

    @Test
    func fallsBackForThreadsOutsideTheScannedWindow() {
        // Threads with nothing new are absent from the feed scan; they keep the
        // root timestamp, which is older than any cutoff and so reads as read.
        let rootInsert = Date(timeIntervalSince1970: 1_000)
        let activity = MailingListActivity(newestByRootEmailID: [:])

        #expect(activity.lastActivity(rootEmailID: 42, fallback: rootInsert) == rootInsert)
    }

    @Test
    func neverGoesBackwardsFromTheFallback() {
        // A root inserted after the newest scanned reply must not age the thread
        // backwards.
        let rootInsert = Date(timeIntervalSince1970: 9_000)
        let staleReply = Date(timeIntervalSince1970: 5_000)
        let activity = MailingListActivity(newestByRootEmailID: [42: staleReply])

        #expect(activity.lastActivity(rootEmailID: 42, fallback: rootInsert) == rootInsert)
    }

    @Test
    func tracksThreadsIndependently() {
        let activity = MailingListActivity(newestByRootEmailID: [
            1: Date(timeIntervalSince1970: 5_000),
            2: Date(timeIntervalSince1970: 7_000)
        ])
        let fallback = Date(timeIntervalSince1970: 1_000)

        #expect(activity.lastActivity(rootEmailID: 1, fallback: fallback) == Date(timeIntervalSince1970: 5_000))
        #expect(activity.lastActivity(rootEmailID: 2, fallback: fallback) == Date(timeIntervalSince1970: 7_000))
        #expect(activity.lastActivity(rootEmailID: 3, fallback: fallback) == fallback)
    }

    @Test
    func newMailInAnOldThreadReadsAsUnread() {
        let suiteName = "MailingListActivityTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let signIn = Date(timeIntervalSince1970: 5_000)
        InboxReadStateStore.establishBaselineIfNeeded(now: signIn, defaults: defaults)

        // A thread rooted long before sign-in, with a reply after it. Keyed on
        // thread.updated this reads as read, which was the bug.
        let rootInsert = Date(timeIntervalSince1970: 1_000)
        let replyAfterSignIn = Date(timeIntervalSince1970: 6_000)
        let activity = MailingListActivity(newestByRootEmailID: [42: replyAfterSignIn])
        let lastActivityAt = activity.lastActivity(rootEmailID: 42, fallback: rootInsert)

        #expect(
            InboxReadStateStore.isUnread(
                threadID: "list#old thread",
                lastActivityAt: lastActivityAt,
                defaults: defaults
            )
        )
    }
}
