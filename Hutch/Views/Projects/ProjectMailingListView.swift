import SwiftUI

private struct ProjectMailingListThreadsResponse: Decodable, Sendable {
    let list: ProjectMailingListThreads
}

private struct ProjectMailingListThreads: Decodable, Sendable {
    let threads: ProjectMailingListThreadPage
}

private struct ProjectMailingListThreadPage: Decodable, Sendable {
    let results: [ProjectMailingListThreadPayload]
}

private struct ProjectMailingListThreadPayload: Decodable, Sendable {
    let updated: Date
    let subject: String
    let replies: Int
    let sender: Entity
    let root: ProjectMailingListRootPayload
}

private struct ProjectMailingListRootPayload: Decodable, Sendable {
    let id: Int
    let messageID: String
    let patch: InboxPatchPreview?
}

@Observable
@MainActor
final class MailingListDetailViewModel {
    private(set) var threads: [InboxThreadSummary] = []
    private(set) var isLoading = false
    var error: String?

    private let mailingList: InboxMailingListReference
    private let client: SRHTClient

    private static let listThreadsQuery = """
    query projectMailingListThreads($rid: ID!) {
        list(rid: $rid) {
            threads {
                results {
                    updated
                    subject
                    replies
                    sender { canonicalName }
                    root {
                        id
                        messageID
                        patch { subject }
                    }
                }
            }
        }
    }
    """

    init(mailingList: InboxMailingListReference, client: SRHTClient) {
        self.mailingList = mailingList
        self.client = client
    }

    func loadThreads() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response = try await client.execute(
                service: .lists,
                query: Self.listThreadsQuery,
                variables: ["rid": mailingList.rid],
                responseType: ProjectMailingListThreadsResponse.self
            )

            threads = deduplicateThreads(
                response.list.threads.results.map(makeSummary(from:))
            )
        } catch {
            self.error = "Failed to load mailing list"
        }
    }

    func markThreadRead(_ thread: InboxThreadSummary) {
        let viewedAt = max(Date(), thread.lastActivityAt)
        InboxReadStateStore.markViewed(viewedAt, for: thread.id)
        updateThread(thread, isUnread: false)
    }

    func markThreadUnread(_ thread: InboxThreadSummary) {
        InboxReadStateStore.markUnread(for: thread.id)
        updateThread(thread, isUnread: true)
    }

    private func makeSummary(from thread: ProjectMailingListThreadPayload) -> InboxThreadSummary {
        let normalizedSubject = thread.subject
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(?:(?:re|fwd?)\s*:\s*)+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .lowercased()
        let threadID = "\(mailingList.rid)#\(normalizedSubject)"

        return InboxThreadSummary(
            rootEmailID: thread.root.id,
            rootMessageID: thread.root.messageID,
            threadRootEmailIDs: [thread.root.id],
            threadRootMessageIDs: [thread.root.messageID],
            listID: 0,
            listRID: mailingList.rid,
            listName: mailingList.name,
            listOwner: mailingList.owner,
            subject: thread.subject,
            latestSender: thread.sender,
            lastActivityAt: thread.updated,
            messageCount: thread.replies + 1,
            repo: nil,
            containsPatch: thread.root.patch != nil || thread.subject.localizedCaseInsensitiveContains("[patch"),
            isUnread: InboxReadStateStore.isUnread(threadID: threadID, lastActivityAt: thread.updated)
        )
    }

    private func updateThread(_ thread: InboxThreadSummary, isUnread: Bool) {
        guard let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        let current = threads[index]
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
}

struct MailingListDetailView: View {
    let mailingList: InboxMailingListReference

    @Environment(AppState.self) private var appState
    @State private var viewModel: MailingListDetailViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading mailing list…")
            }
        }
        .navigationTitle(mailingList.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                let viewModel = MailingListDetailViewModel(mailingList: mailingList, client: appState.client)
                self.viewModel = viewModel
                await viewModel.loadThreads()
            }
        }
        .onAppear {
            guard let viewModel else { return }
            Task {
                await viewModel.loadThreads()
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: MailingListDetailViewModel) -> some View {
        @Bindable var vm = viewModel

        List {
            ForEach(viewModel.threads) { thread in
                NavigationLink(value: MoreRoute.thread(thread)) {
                    InboxThreadRow(thread: thread)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if thread.isUnread {
                                viewModel.markThreadRead(thread)
                            } else {
                                viewModel.markThreadUnread(thread)
                            }
                        }
                    } label: {
                        Label(
                            thread.isUnread ? "Mark as Read" : "Mark as Unread",
                            systemImage: thread.isUnread ? "envelope.open" : "envelope.badge"
                        )
                    }
                    .tint(thread.isUnread ? .blue : .gray)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.isLoading, viewModel.threads.isEmpty {
                SRHTLoadingStateView(message: "Loading mailing list…")
            } else if let error = viewModel.error, viewModel.threads.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Mailing List",
                    message: error,
                    retryAction: { await viewModel.loadThreads() }
                )
            } else if viewModel.threads.isEmpty {
                ContentUnavailableView(
                    "No Threads",
                    systemImage: "tray",
                    description: Text("This mailing list does not have any recent threads.")
                )
            }
        }
        .refreshable {
            await viewModel.loadThreads()
        }
        .srhtErrorBanner(error: $vm.error)
    }
}

struct ProjectMailingListView: View {
    let mailingList: Project.MailingList

    var body: some View {
        MailingListDetailView(mailingList: mailingList.inboxReference)
    }
}
