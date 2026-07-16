import SwiftUI

@Observable
@MainActor
final class MailingListListViewModel {
    private(set) var mailingLists: [InboxMailingListReference] = []
    private(set) var isLoading = false
    private(set) var isPerformingAction = false
    var error: String?
    var searchText = ""

    private let client: SRHTClient

    private static let subscriptionsQuery = """
    query mailingLists($cursor: Cursor) {
        subscriptions(cursor: $cursor) {
            results {
                ... on MailingListSubscription {
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

    private static let unsubscribeMutation = """
    mutation mailingListUnsubscribe($listID: Int!) {
        subscription: mailingListUnsubscribe(listID: $listID) { id }
    }
    """

    init(client: SRHTClient) {
        self.client = client
    }

    /// Unsubscribes from a list and drops it from the list on success. This view
    /// is built from the subscriptions query, so a successful unsubscribe means
    /// the row no longer belongs here.
    func unsubscribe(from mailingList: InboxMailingListReference) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        error = nil
        defer { isPerformingAction = false }

        let previousLists = mailingLists
        mailingLists.removeAll { $0.rid == mailingList.rid }

        do {
            struct Response: Decodable, Sendable {
                // mailingListUnsubscribe is nullable: sr.ht returns null when there
                // was no subscription to remove, which is still a success.
                let subscription: SubscriptionPayload?
            }

            struct SubscriptionPayload: Decodable, Sendable {
                let id: Int
            }

            _ = try await client.execute(
                service: .lists,
                query: Self.unsubscribeMutation,
                variables: ["listID": mailingList.id],
                responseType: Response.self
            )
        } catch {
            mailingLists = previousLists
            self.error = "Couldn't unsubscribe from \(mailingList.name). \(error.userFacingMessage)"
        }
    }

    var filteredMailingLists: [InboxMailingListReference] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return mailingLists }
        return mailingLists.filter {
            $0.name.lowercased().contains(q) ||
            $0.owner.canonicalName.lowercased().contains(q)
        }
    }

    func loadMailingLists() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            mailingLists = try await fetchMailingLists()
        } catch {
            self.error = "Failed to load mailing lists"
        }
    }

    private func fetchMailingLists() async throws -> [InboxMailingListReference] {
        struct Response: Decodable, Sendable {
            let subscriptions: Page
        }

        struct Page: Decodable, Sendable {
            let results: [Subscription]
            let cursor: String?
        }

        struct Subscription: Decodable, Sendable {
            let list: InboxMailingListReference?
        }

        var results: [InboxMailingListReference] = []
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
                responseType: Response.self
            )

            results.append(contentsOf: response.subscriptions.results.compactMap(\.list))
            guard let nextCursor = response.subscriptions.cursor else {
                break
            }
            cursor = nextCursor
        }

        var seen = Set<String>()
        return results
            .filter { seen.insert($0.rid).inserted }
            .sorted {
                if $0.owner.canonicalName == $1.owner.canonicalName {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.owner.canonicalName.localizedCaseInsensitiveCompare($1.owner.canonicalName) == .orderedAscending
            }
    }
}

struct MailingListListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: MailingListListViewModel?
    @State private var pendingUnsubscribe: InboxMailingListReference?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading mailing lists…")
            }
        }
        .navigationTitle("Mailing Lists")
        .task {
            if viewModel == nil {
                let vm = MailingListListViewModel(client: appState.client)
                viewModel = vm
                await vm.loadMailingLists()
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: MailingListListViewModel) -> some View {
        @Bindable var vm = viewModel

        List {
            ForEach(viewModel.filteredMailingLists, id: \.rid) { mailingList in
                NavigationLink(value: MoreRoute.mailingList(mailingList)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mailingList.name)
                            .font(.subheadline.weight(.medium))
                        Text(mailingList.owner.canonicalName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .swipeActions(edge: .trailing) {
                    Button {
                        pendingUnsubscribe = mailingList
                    } label: {
                        SwiftUI.Label("Unsubscribe", systemImage: "bell.slash")
                    }
                    .tint(.orange)
                }
            }
            .themedRow()
        }
        .themedList()
        .listStyle(.plain)
        .searchable(
            text: $vm.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search lists"
        )
        .confirmationDialog(
            pendingUnsubscribe.map { "Unsubscribe from \($0.name)?" } ?? "",
            isPresented: .init(
                get: { pendingUnsubscribe != nil },
                set: { if !$0 { pendingUnsubscribe = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingUnsubscribe
        ) { mailingList in
            Button("Unsubscribe", role: .destructive) {
                Task { await viewModel.unsubscribe(from: mailingList) }
            }
            Button("Cancel", role: .cancel) { pendingUnsubscribe = nil }
        } message: { _ in
            Text("You will stop receiving email from this list. Hutch cannot resubscribe you — you would need to do that from the list's page on the web.")
        }
        .overlay {
            if viewModel.isLoading, viewModel.mailingLists.isEmpty {
                SRHTLoadingStateView(message: "Loading mailing lists…")
            } else if let error = viewModel.error, viewModel.mailingLists.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Mailing Lists",
                    message: error,
                    retryAction: { await viewModel.loadMailingLists() }
                )
            } else if !viewModel.mailingLists.isEmpty, viewModel.filteredMailingLists.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else if viewModel.mailingLists.isEmpty {
                ContentUnavailableView(
                    "No Mailing Lists",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Your subscribed mailing lists will appear here.")
                )
            }
        }
        .srhtErrorBanner(error: $vm.error)
        .refreshable {
            await viewModel.loadMailingLists()
        }
    }
}
