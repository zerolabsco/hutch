import SwiftUI

@Observable
@MainActor
final class MailingListListViewModel {
    private(set) var mailingLists: [InboxMailingListReference] = []
    private(set) var isLoading = false
    var error: String?

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

    init(client: SRHTClient) {
        self.client = client
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

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading mailing lists…")
            }
        }
        .navigationTitle("Lists")
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
            ForEach(viewModel.mailingLists, id: \.rid) { mailingList in
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
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.isLoading, viewModel.mailingLists.isEmpty {
                SRHTLoadingStateView(message: "Loading mailing lists…")
            } else if let error = viewModel.error, viewModel.mailingLists.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Mailing Lists",
                    message: error,
                    retryAction: { await viewModel.loadMailingLists() }
                )
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
