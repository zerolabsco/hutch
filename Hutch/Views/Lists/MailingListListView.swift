import SwiftUI

private struct ListIDPayload: Decodable, Sendable {
    let id: Int
}

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

    private static let createMailingListMutation = """
    mutation createMailingList($name: String!, $description: String, $visibility: Visibility!) {
        createMailingList(name: $name, description: $description, visibility: $visibility) {
            id
            rid
            name
            owner { canonicalName }
        }
    }
    """

    /// InboxMailingListReference carries only id/rid/name/owner, so the settings
    /// sheet has to read the current values before it can offer to change them —
    /// otherwise saving would blank the description and reset visibility.
    private static let listSettingsQuery = """
    query listSettings($rid: ID!) {
        list(rid: $rid) {
            description
            visibility
        }
    }
    """

    private static let updateMailingListMutation = """
    mutation updateMailingList($id: Int!, $input: MailingListInput!) {
        updateMailingList(id: $id, input: $input) { id }
    }
    """

    private static let deleteMailingListMutation = """
    mutation deleteMailingList($id: Int!) {
        deleteMailingList(id: $id) { id }
    }
    """

    init(client: SRHTClient) {
        self.client = client
    }

    /// Creates a list. sr.ht subscribes the owner automatically, so a reload is
    /// enough to surface it — this view is built from the subscriptions query.
    @discardableResult
    func createMailingList(name: String, description: String, visibility: Visibility) async -> Bool {
        guard !isPerformingAction else { return false }
        isPerformingAction = true
        error = nil
        defer { isPerformingAction = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            struct Response: Decodable, Sendable {
                let createMailingList: InboxMailingListReference
            }

            _ = try await client.execute(
                service: .lists,
                query: Self.createMailingListMutation,
                variables: [
                    "name": trimmedName,
                    "description": trimmedDescription.isEmpty ? nil as String? as Any : trimmedDescription,
                    "visibility": visibility.rawValue
                ],
                responseType: Response.self
            )
            await loadMailingLists()
            return true
        } catch {
            self.error = "Couldn't create \(trimmedName). \(error.userFacingMessage)"
            return false
        }
    }

    /// Reads a list's current description and visibility, so the settings sheet
    /// can seed itself rather than overwrite with blanks.
    func listSettings(rid: String) async -> (description: String, visibility: Visibility)? {
        struct Response: Decodable, Sendable {
            let list: ListSettingsPayload?
        }

        struct ListSettingsPayload: Decodable, Sendable {
            let description: String?
            let visibility: Visibility
        }

        do {
            let response = try await client.execute(
                service: .lists,
                query: Self.listSettingsQuery,
                variables: ["rid": rid],
                responseType: Response.self
            )
            guard let list = response.list else { return nil }
            return (list.description ?? "", list.visibility)
        } catch {
            self.error = "Couldn't load the list's settings. \(error.userFacingMessage)"
            return nil
        }
    }

    /// Edits a list's description and visibility.
    ///
    /// `MailingListInput` also carries `permitMime` / `rejectMime`; those are left
    /// alone rather than sent as empty, which would clear the list's filters.
    @discardableResult
    func updateMailingList(id: Int, description: String, visibility: Visibility) async -> Bool {
        guard !isPerformingAction else { return false }
        isPerformingAction = true
        error = nil
        defer { isPerformingAction = false }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var input: [String: any Sendable] = ["visibility": visibility.rawValue]
        if trimmedDescription.isEmpty {
            // A nil subscript assignment would drop the key and leave the old
            // description in place instead of clearing it.
            input.updateValue(Optional<String>.none as any Sendable, forKey: "description")
        } else {
            input["description"] = trimmedDescription
        }

        do {
            struct Response: Decodable, Sendable {
                let updateMailingList: ListIDPayload?
            }

            _ = try await client.execute(
                service: .lists,
                query: Self.updateMailingListMutation,
                variables: ["id": id, "input": input],
                responseType: Response.self
            )
            await loadMailingLists()
            return true
        } catch {
            self.error = "Couldn't update the list. \(error.userFacingMessage)"
            return false
        }
    }

    @discardableResult
    func deleteMailingList(_ mailingList: InboxMailingListReference) async -> Bool {
        guard !isPerformingAction else { return false }
        isPerformingAction = true
        error = nil
        defer { isPerformingAction = false }

        let previousLists = mailingLists
        mailingLists.removeAll { $0.rid == mailingList.rid }

        do {
            struct Response: Decodable, Sendable {
                let deleteMailingList: ListIDPayload?
            }

            _ = try await client.execute(
                service: .lists,
                query: Self.deleteMailingListMutation,
                variables: ["id": mailingList.id],
                responseType: Response.self
            )
            return true
        } catch {
            mailingLists = previousLists
            self.error = "Couldn't delete \(mailingList.name). \(error.userFacingMessage)"
            return false
        }
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
    @State private var pendingDeletion: InboxMailingListReference?
    @State private var editingList: InboxMailingListReference?
    @State private var showCreateSheet = false

    /// The subscriptions query returns lists the user follows, which is not the
    /// same as lists they own — only the owner may edit or delete one.
    private func isOwned(_ mailingList: InboxMailingListReference) -> Bool {
        guard let currentUser = appState.currentUser else { return false }
        let owner = mailingList.owner.canonicalName.hasPrefix("~")
            ? String(mailingList.owner.canonicalName.dropFirst())
            : mailingList.owner.canonicalName
        return owner.caseInsensitiveCompare(currentUser.username) == .orderedSame
    }

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
                // allowsFullSwipe: false, as in PasteListView. A destructive
                // action left to full-swipe animates the row out on the gesture,
                // before the confirmation is answered, so it flickers back when
                // the data has not actually changed.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if isOwned(mailingList) {
                        Button(role: .destructive) {
                            pendingDeletion = mailingList
                        } label: {
                            SwiftUI.Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editingList = mailingList
                        } label: {
                            SwiftUI.Label("Settings", systemImage: "gear")
                        }
                        .tint(.gray)
                    } else {
                        Button {
                            pendingUnsubscribe = mailingList
                        } label: {
                            SwiftUI.Label("Unsubscribe", systemImage: "bell.slash")
                        }
                        .tint(.orange)
                    }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    SwiftUI.Label("New List", systemImage: "plus")
                }
                .disabled(viewModel.isPerformingAction)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            MailingListEditSheet(mode: .create, isPresented: $showCreateSheet) { name, description, visibility in
                await viewModel.createMailingList(name: name, description: description, visibility: visibility)
            }
        }
        .sheet(item: $editingList) { mailingList in
            MailingListEditSheet(
                mode: .edit(mailingList.name),
                isPresented: .init(get: { true }, set: { if !$0 { editingList = nil } }),
                loadInitialValues: { await viewModel.listSettings(rid: mailingList.rid) }
            ) { _, description, visibility in
                await viewModel.updateMailingList(id: mailingList.id, description: description, visibility: visibility)
            }
        }
        .confirmationDialog(
            pendingDeletion.map { "Delete \($0.name)?" } ?? "",
            isPresented: .init(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { mailingList in
            Button("Delete List", role: .destructive) {
                Task { await viewModel.deleteMailingList(mailingList) }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text("This permanently deletes the list and its entire archive, for everyone. This cannot be undone.")
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

// MARK: - Edit Sheet

/// Create and settings share a sheet: sr.ht takes name only at creation, and
/// description plus visibility in both cases.
private struct MailingListEditSheet: View {
    enum Mode {
        case create
        case edit(String)

        var title: String {
            switch self {
            case .create: "New Mailing List"
            case .edit(let name): name
            }
        }

        var isCreate: Bool {
            if case .create = self { return true }
            return false
        }
    }

    let mode: Mode
    @Binding var isPresented: Bool
    /// Seeds the sheet with the list's current values. Editing without this would
    /// save blanks over whatever is already there.
    var loadInitialValues: (() async -> (description: String, visibility: Visibility)?)?
    let onSubmit: (String, String, Visibility) async -> Bool

    @State private var name = ""
    @State private var description = ""
    @State private var visibility: Visibility = .publicVisibility
    @State private var isSubmitting = false
    @State private var isLoadingInitialValues = false
    @State private var hasLoadedInitialValues = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        guard !isSubmitting, !isLoadingInitialValues else { return false }
        if mode.isCreate { return !trimmedName.isEmpty }
        // Never offer to save values we have not read back yet.
        return hasLoadedInitialValues
    }

    var body: some View {
        NavigationStack {
            Form {
                if mode.isCreate {
                    Section("Name") {
                        TextField("list-name", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .themedRow()
                    }
                }

                Section("Description") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...6)
                        .themedRow()
                }

                Section("Visibility") {
                    Picker("Visibility", selection: $visibility) {
                        Text("Public").tag(Visibility.publicVisibility)
                        Text("Unlisted").tag(Visibility.unlisted)
                        Text("Private").tag(Visibility.privateVisibility)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .themedRow()
                }
            }
            .themedList()
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                guard let loadInitialValues, !hasLoadedInitialValues else { return }
                isLoadingInitialValues = true
                if let current = await loadInitialValues() {
                    description = current.description
                    visibility = current.visibility
                    hasLoadedInitialValues = true
                }
                isLoadingInitialValues = false
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.isCreate ? "Create" : "Save") {
                        Task {
                            isSubmitting = true
                            let ok = await onSubmit(trimmedName, description, visibility)
                            isSubmitting = false
                            if ok { isPresented = false }
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .overlay {
                if isSubmitting || isLoadingInitialValues {
                    ProgressView()
                }
            }
        }
    }
}
