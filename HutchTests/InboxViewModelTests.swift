import Foundation
import Testing
@testable import Hutch

struct InboxViewModelTests {

    @Test
    func derivesRepositoryNameFromCommonPatchListSuffixes() {
        #expect(InboxViewModel.deriveRepositoryName(from: "hut-devel") == "hut")
        #expect(InboxViewModel.deriveRepositoryName(from: "git.patches") == "git")
        #expect(InboxViewModel.deriveRepositoryName(from: "discuss") == nil)
    }

    @Test
    func parsesMailtoDraft() {
        let draft = ThreadViewModel.mailComposeDraft(
            from: "mailto:list@example.com?cc=author@example.com&subject=Re:%20PATCH&body=LGTM"
        )

        #expect(draft?.recipients == ["list@example.com"])
        #expect(draft?.ccRecipients == ["author@example.com"])
        #expect(draft?.subject == "Re: PATCH")
        #expect(draft?.body == "LGTM")
    }

    @Test
    func computesLocalUnreadStateFromLastViewedMarker() {
        let suiteName = "InboxViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let threadID = "list#message"
        let lastActivity = Date(timeIntervalSince1970: 2_000)

        #expect(InboxReadStateStore.isUnread(threadID: threadID, lastActivityAt: lastActivity, defaults: defaults))

        InboxReadStateStore.markViewed(Date(timeIntervalSince1970: 1_000), for: threadID, defaults: defaults)
        #expect(InboxReadStateStore.isUnread(threadID: threadID, lastActivityAt: lastActivity, defaults: defaults))

        InboxReadStateStore.markViewed(Date(timeIntervalSince1970: 2_500), for: threadID, defaults: defaults)
        #expect(!InboxReadStateStore.isUnread(threadID: threadID, lastActivityAt: lastActivity, defaults: defaults))
    }

    @Test
    func normalizesThreadSubjectsForDisplay() {
        let summary = InboxThreadSummary(
            rootEmailID: 1,
            rootMessageID: "message",
            threadRootEmailIDs: [1],
            threadRootMessageIDs: ["message"],
            listID: 2,
            listRID: "list",
            listName: "hut-devel",
            listOwner: Entity(canonicalName: "~owner"),
            subject: "Re: Fwd:   [PATCH] test: add parser  ",
            latestSender: Entity(canonicalName: "~sender"),
            lastActivityAt: Date(timeIntervalSince1970: 2_000),
            messageCount: 3,
            repo: "hut",
            containsPatch: true,
            isUnread: true
        )

        #expect(summary.displaySubject == "[PATCH] test: add parser")
        #expect(summary.metadataLine.contains("~sender"))
        #expect(summary.metadataLine.contains("2 replies"))
    }

    @Test
    func keepsDistinctThreadsDistinctByRootMessageID() {
        let baseList = InboxMailingListReference(
            id: 1,
            rid: "list",
            name: "hut-devel",
            owner: Entity(canonicalName: "~owner")
        )

        let first = InboxThreadSummary(
            rootEmailID: 10,
            rootMessageID: "message-1",
            threadRootEmailIDs: [10],
            threadRootMessageIDs: ["message-1"],
            listID: baseList.id,
            listRID: baseList.rid,
            listName: baseList.name,
            listOwner: baseList.owner,
            subject: "[PATCH] test",
            latestSender: Entity(canonicalName: "~a"),
            lastActivityAt: Date(timeIntervalSince1970: 100),
            messageCount: 1,
            repo: "hut",
            containsPatch: true,
            isUnread: true
        )
        let second = InboxThreadSummary(
            rootEmailID: 11,
            rootMessageID: "message-2",
            threadRootEmailIDs: [11],
            threadRootMessageIDs: ["message-2"],
            listID: baseList.id,
            listRID: baseList.rid,
            listName: baseList.name,
            listOwner: baseList.owner,
            subject: "[PATCH] test",
            latestSender: Entity(canonicalName: "~b"),
            lastActivityAt: Date(timeIntervalSince1970: 200),
            messageCount: 2,
            repo: "hut",
            containsPatch: true,
            isUnread: true
        )

        #expect(first.id != second.id)
    }

    @Test
    func segmentsPatchBodyAndTreatsSignatureAsPlainText() {
        let body = """
        From: Christian Cleberg <hello@cleberg.net>

        ---
         test-patch.txt | 1 +
         1 file changed, 1 insertion(+)
         create mode 100644 test-patch.txt

        diff --git a/test-patch.txt b/test-patch.txt
        new file mode 100644
        index 0000000..c7b6eed
        --- /dev/null
        +++ b/test-patch.txt
        @@ -0,0 +1 @@
        +test Wed Mar 18 23:19:03 CDT 2026
        -- 
        2.50.1 (Apple Git-155)
        """

        let segments = ThreadViewModel.segmentMessageBodyForTesting(body, isPatch: true)

        #expect(segments.count == 3)

        guard case let .plainText(leadingPlainText) = segments[0] else {
            Issue.record("Expected first segment to be plain text")
            return
        }
        #expect(leadingPlainText.contains("From: Christian Cleberg <hello@cleberg.net>"))
        #expect(leadingPlainText.contains("---"))
        #expect(leadingPlainText.contains(" test-patch.txt | 1 +"))
        #expect(leadingPlainText.contains(" 1 file changed, 1 insertion(+)"))
        #expect(leadingPlainText.contains(" create mode 100644 test-patch.txt"))

        guard case let .diff(diff) = segments[1] else {
            Issue.record("Expected second segment to be diff")
            return
        }
        #expect(diff.contains("diff --git a/test-patch.txt b/test-patch.txt"))
        #expect(diff.contains("--- /dev/null"))
        #expect(diff.contains("+++ b/test-patch.txt"))
        #expect(diff.contains("+test Wed Mar 18 23:19:03 CDT 2026"))
        #expect(!diff.contains("-- \n2.50.1 (Apple Git-155)"))

        guard case let .plainText(trailingPlainText) = segments[2] else {
            Issue.record("Expected third segment to be plain text")
            return
        }
        #expect(trailingPlainText.contains("--"))
        #expect(trailingPlainText.contains("2.50.1 (Apple Git-155)"))
    }
}
