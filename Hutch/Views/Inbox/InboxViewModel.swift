import Foundation
import os

private let inboxListLogger = Logger(subsystem: "net.cleberg.Hutch", category: "InboxList")

private struct InboxSubscriptionsResponse: Decodable, Sendable {
    let subscriptions: InboxSubscriptionPage
}

private struct InboxSubscriptionPage: Decodable, Sendable {
    let results: [InboxActivitySubscription]
    let cursor: String?
}

private struct InboxActivitySubscription: Decodable, Sendable {
    let id: Int
    let created: Date
    let list: InboxMailingListReference?

    enum CodingKeys: String, CodingKey {
        case id
        case created
        case list
    }
}

private struct InboxListThreadsResponse: Decodable, Sendable {
    let list: InboxMailingListThreads
}

private struct InboxMailingListThreads: Decodable, Sendable {
    let threads: InboxThreadPage
}

private struct InboxThreadPage: Decodable, Sendable {
    let results: [InboxThreadPayload]
    let cursor: String?
}

private struct InboxThreadPayload: Decodable, Sendable {
    let created: Date
    let updated: Date
    let subject: String
    let replies: Int
    let sender: Entity
    let root: InboxEmailPreview
}

private struct InboxEmailPreview: Decodable, Sendable {
    let id: Int
    let subject: String
    let date: Date?
    let received: Date
    let messageID: String
    let body: String
    let patch: InboxPatchPreview?
}

@Observable
@MainActor
final class InboxViewModel {
    private(set) var threads: [InboxThreadSummary] = []
    private(set) var isLoading = false
    var error: String?

    private let client: SRHTClient
    private let listThreadFetchLimit = 10
    private let listFetchConcurrencyLimit = 4

    private static let subscriptionsQuery = """
    query inboxSubscriptions($cursor: Cursor) {
        subscriptions(cursor: $cursor) {
            results {
                ... on MailingListSubscription {
                    id
                    created
                    list {
                        id
                        rid
                        name
                        owner { canonicalName }
                    }
                }
            }
            cursor
        }
    }
    """

    private static let listThreadsQuery = """
    query inboxListThreads($rid: ID!, $cursor: Cursor) {
        list(rid: $rid) {
            threads(cursor: $cursor) {
                results {
                    created
                    updated
                    subject
                    replies
                    sender { canonicalName }
                    root {
                        id
                        subject
                        date
                        received
                        messageID
                        body
                        patch { subject }
                    }
                }
                cursor
            }
        }
    }
    """

    init(client: SRHTClient) {
        self.client = client
    }

    func loadThreads() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let subscriptions = try await fetchSubscriptions()
            let mailingLists = deduplicateMailingLists(subscriptions.compactMap(\.list))
            let fetchedThreads = try await fetchThreads(for: mailingLists)
            threads = fetchedThreads
                .filter(\.isUnread)
                .sorted { lhs, rhs in
                if lhs.lastActivityAt == rhs.lastActivityAt {
                    return lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending
                }
                return lhs.lastActivityAt > rhs.lastActivityAt
            }
        } catch {
            inboxListLogger.error("Inbox request failed: type=inbox error=\(error.localizedDescription, privacy: .public)")
            self.error = "Failed to load inbox"
        }
    }

    func markThreadRead(_ thread: InboxThreadSummary) {
        let viewedAt = max(Date(), thread.lastActivityAt)
        InboxReadStateStore.markViewed(viewedAt, for: thread.id)
        inboxListLogger.debug(
            "Inbox mark read: key=\(thread.id, privacy: .public) latestActivityAt=\(thread.lastActivityAt.ISO8601Format(), privacy: .public) storedLastViewedAt=\(viewedAt.ISO8601Format(), privacy: .public)"
        )
        threads.removeAll { $0.id == thread.id }
    }

    func markThreadUnread(_ thread: InboxThreadSummary) {
        InboxReadStateStore.markUnread(for: thread.id)
        inboxListLogger.debug(
            "Inbox mark unread: key=\(thread.id, privacy: .public) latestActivityAt=\(thread.lastActivityAt.ISO8601Format(), privacy: .public) storedLastViewedAt=nil"
        )
        updateThread(thread, isUnread: true)
    }

    func toggleThreadReadState(_ thread: InboxThreadSummary) {
        if thread.isUnread {
            markThreadRead(thread)
        } else {
            markThreadUnread(thread)
        }
    }

    private func fetchSubscriptions() async throws -> [InboxActivitySubscription] {
        var subscriptions: [InboxActivitySubscription] = []
        var cursor: String?

        while true {
            var variables: [String: any Sendable] = [:]
            if let cursor {
                variables["cursor"] = cursor
            }

            let response = try await client.execute(
                service: .lists,
                query: Self.subscriptionsQuery,
                variables: variables.isEmpty ? nil : variables,
                responseType: InboxSubscriptionsResponse.self
            )

            subscriptions.append(contentsOf: response.subscriptions.results)
            guard let nextCursor = response.subscriptions.cursor else {
                break
            }
            cursor = nextCursor
        }

        return subscriptions
    }

    private func fetchThreads(for mailingLists: [InboxMailingListReference]) async throws -> [InboxThreadSummary] {
        guard !mailingLists.isEmpty else { return [] }

        var summaries: [InboxThreadSummary] = []
        var startIndex = mailingLists.startIndex
        var failureMessages: [String] = []

        while startIndex < mailingLists.endIndex {
            let endIndex = mailingLists.index(
                startIndex,
                offsetBy: listFetchConcurrencyLimit,
                limitedBy: mailingLists.endIndex
            ) ?? mailingLists.endIndex
            let batch = Array(mailingLists[startIndex..<endIndex])

            let batchResult = await withTaskGroup(of: ([InboxThreadSummary], String?).self) { group in
                for mailingList in batch {
                    group.addTask {
                        do {
                            return (try await self.fetchThreads(for: mailingList), nil)
                        } catch {
                            return ([], "rid=\(mailingList.rid) error=\(error.localizedDescription)")
                        }
                    }
                }

                var batchSummaries: [InboxThreadSummary] = []
                var batchFailures: [String] = []
                for await result in group {
                    batchSummaries.append(contentsOf: result.0)
                    if let failure = result.1 {
                        batchFailures.append(failure)
                    }
                }
                return (batchSummaries, batchFailures)
            }

            summaries.append(contentsOf: batchResult.0)
            failureMessages.append(contentsOf: batchResult.1)
            for failure in batchResult.1 {
                inboxListLogger.error("Inbox request failed: type=listThreads \(failure, privacy: .public)")
            }
            startIndex = endIndex
        }

        if summaries.isEmpty, let firstFailure = failureMessages.first {
            throw SRHTError.graphQLErrors([GraphQLError(message: firstFailure, locations: nil)])
        }

        return deduplicateThreads(summaries)
    }

    private func fetchThreads(for mailingList: InboxMailingListReference) async throws -> [InboxThreadSummary] {
        let response = try await client.execute(
            service: .lists,
            query: Self.listThreadsQuery,
            variables: ["rid": mailingList.rid],
            responseType: InboxListThreadsResponse.self
        )

        return response.list.threads.results.prefix(listThreadFetchLimit).map { thread in
            let groupingKey = "\(mailingList.rid)#\(thread.subject.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"^(?:(?:re|fwd?)\s*:\s*)+"#, with: "", options: [.regularExpression, .caseInsensitive]).lowercased())"
            let lastViewedAt = InboxReadStateStore.lastViewedAt(for: groupingKey)
            let isUnread = InboxReadStateStore.isUnread(threadID: groupingKey, lastActivityAt: thread.updated)
            inboxListLogger.debug(
                "Inbox thread grouping candidate: listRID=\(mailingList.rid, privacy: .public) rootMessageID=\(thread.root.messageID, privacy: .public) rootEmailID=\(thread.root.id, privacy: .public) groupingKey=\(groupingKey, privacy: .public)"
            )
            inboxListLogger.debug(
                "Inbox unread state: key=\(groupingKey, privacy: .public) latestActivityAt=\(thread.updated.ISO8601Format(), privacy: .public) lastViewedAt=\(lastViewedAt?.ISO8601Format() ?? "nil", privacy: .public) isUnread=\(isUnread, privacy: .public)"
            )
            return InboxThreadSummary(
                rootEmailID: thread.root.id,
                rootMessageID: thread.root.messageID,
                threadRootEmailIDs: [thread.root.id],
                threadRootMessageIDs: [thread.root.messageID],
                listID: mailingList.id,
                listRID: mailingList.rid,
                listName: mailingList.name,
                listOwner: mailingList.owner,
                subject: thread.subject,
                latestSender: thread.sender,
                lastActivityAt: thread.updated,
                messageCount: thread.replies + 1,
                repo: Self.deriveRepositoryName(from: mailingList.name),
                containsPatch: thread.root.patch != nil || thread.subject.localizedCaseInsensitiveContains("[patch"),
                isUnread: isUnread
            )
        }
    }

    private func deduplicateThreads(_ threads: [InboxThreadSummary]) -> [InboxThreadSummary] {
        var grouped: [String: InboxThreadSummary] = [:]

        for thread in threads {
            guard let existing = grouped[thread.threadGroupingKey] else {
                grouped[thread.threadGroupingKey] = thread
                continue
            }

            let latest = thread.lastActivityAt >= existing.lastActivityAt ? thread : existing
            let mergedRootEmailIDs = Array(Set(existing.threadRootEmailIDs + thread.threadRootEmailIDs)).sorted()
            let mergedRootMessageIDs = Array(Set(existing.threadRootMessageIDs + thread.threadRootMessageIDs)).sorted()
            let mergedMessageCount = max(
                existing.messageCount ?? existing.threadRootMessageIDs.count,
                thread.messageCount ?? thread.threadRootMessageIDs.count,
                mergedRootMessageIDs.count
            )

            grouped[thread.threadGroupingKey] = InboxThreadSummary(
                rootEmailID: latest.rootEmailID,
                rootMessageID: latest.rootMessageID,
                threadRootEmailIDs: mergedRootEmailIDs,
                threadRootMessageIDs: mergedRootMessageIDs,
                listID: latest.listID,
                listRID: latest.listRID,
                listName: latest.listName,
                listOwner: latest.listOwner,
                subject: latest.subject,
                latestSender: latest.latestSender,
                lastActivityAt: max(existing.lastActivityAt, thread.lastActivityAt),
                messageCount: mergedMessageCount,
                repo: latest.repo ?? existing.repo,
                containsPatch: latest.containsPatch || existing.containsPatch,
                isUnread: latest.isUnread || existing.isUnread
            )
        }

        return grouped.values.sorted { lhs, rhs in
            if lhs.lastActivityAt == rhs.lastActivityAt {
                return lhs.displaySubject.localizedCaseInsensitiveCompare(rhs.displaySubject) == .orderedAscending
            }
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
    }

    private func updateThread(_ thread: InboxThreadSummary, isUnread: Bool) {
        guard let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        let current = threads[index]
        if !isUnread {
            threads.remove(at: index)
            return
        }
        threads[index] = InboxThreadSummary(
            rootEmailID: current.rootEmailID,
            rootMessageID: current.rootMessageID,
            threadRootEmailIDs: current.threadRootEmailIDs,
            threadRootMessageIDs: current.threadRootMessageIDs,
            listID: current.listID,
            listRID: current.listRID,
            listName: current.listName,
            listOwner: current.listOwner,
            subject: current.subject,
            latestSender: current.latestSender,
            lastActivityAt: current.lastActivityAt,
            messageCount: current.messageCount,
            repo: current.repo,
            containsPatch: current.containsPatch,
            isUnread: isUnread
        )
    }

    private func deduplicateMailingLists(_ mailingLists: [InboxMailingListReference]) -> [InboxMailingListReference] {
        var seen = Set<String>()
        return mailingLists.filter { mailingList in
            seen.insert(mailingList.rid).inserted
        }
    }

    nonisolated static func deriveRepositoryName(from listName: String) -> String? {
        let separators = ["-devel", "-patches", "-dev", ".patches"]
        for separator in separators where listName.hasSuffix(separator) {
            return String(listName.dropLast(separator.count))
        }
        return nil
    }
}
