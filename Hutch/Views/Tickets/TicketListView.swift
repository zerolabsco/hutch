import SwiftUI

struct TicketListView: View {
    let onTrackerUpdated: (TrackerSummary) -> Void
    let onTrackerDeleted: (TrackerSummary) -> Void

    @AppStorage(AppStorageKeys.swipeActionsEnabled, store: .standard) private var swipeActionsEnabled = true
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var tracker: TrackerSummary
    @State private var viewModel: TicketListViewModel?
    @State private var trackerManagementViewModel: TrackerManagementViewModel?
    @State private var showCreateTicketSheet = false
    @State private var createdTicket: TicketSummary?
    @State private var labelEditorTicket: LabelEditorTicket?
    @State private var showLabelFilterSheet = false
    @State private var showSaveFilterSheet = false
    @State private var showTrackerEditor = false
    @State private var showTrackerACLs = false
    @State private var showTrackerLabels = false
    @State private var showDeleteTrackerConfirmation = false
    @State private var showBulkCloseSheet = false
    @State private var showBulkAssignSheet = false
    @State private var bulkActionResult: TicketBulkActionResult?

    private var isOwnedByCurrentUser: Bool {
        guard let currentUser = appState.currentUser else { return false }
        return normalizedUsername(currentUser.username) == normalizedUsername(tracker.owner.canonicalName)
    }

    init(
        tracker: TrackerSummary,
        onTrackerUpdated: @escaping (TrackerSummary) -> Void = { _ in /* no-op: default for callers that don't handle this event */ },
        onTrackerDeleted: @escaping (TrackerSummary) -> Void = { _ in /* no-op: default for callers that don't handle this event */ }
    ) {
        self._tracker = State(initialValue: tracker)
        self.onTrackerUpdated = onTrackerUpdated
        self.onTrackerDeleted = onTrackerDeleted
    }

    var body: some View {
        Group {
            if let viewModel {
                listContent(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading tickets…")
            }
        }
        .navigationTitle(tracker.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let viewModel, viewModel.isSelectionMode {
                    Button("Cancel") {
                        viewModel.setSelectionMode(false)
                    }
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if viewModel != nil {
                    if let viewModel, viewModel.isSelectionMode {
                        Button("All") {
                            viewModel.selectVisibleTickets(viewModel.filteredTickets)
                        }
                        .disabled(viewModel.filteredTickets.isEmpty || viewModel.isPerformingAction)
                    } else {
                        SRHTShareButton(
                            url: SRHTWebURL.tracker(
                                ownerUsername: String(tracker.owner.canonicalName.dropFirst()),
                                trackerName: tracker.name
                            ),
                            target: .tracker
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }

                        Button {
                            showCreateTicketSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Create ticket")

                        Button("Select") {
                            viewModel?.setSelectionMode(true)
                        }

                        trackerActionsMenu
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateTicketSheet) {
            if let viewModel {
                CreateTicketSheet(viewModel: viewModel) { ticket in
                    showCreateTicketSheet = false
                    createdTicket = ticket
                }
            }
        }
        .sheet(item: $labelEditorTicket) { item in
            if let viewModel {
                TicketLabelsSheet(
                    ticketId: item.id,
                    viewModel: viewModel
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showLabelFilterSheet) {
            if let viewModel {
                TicketFilterLabelsSheet(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showSaveFilterSheet) {
            if let viewModel {
                SaveTicketFilterSheet(viewModel: viewModel)
                    .presentationDetents([.height(220)])
            }
        }
        .sheet(isPresented: $showTrackerEditor) {
            if let trackerManagementViewModel {
                TrackerEditorSheet(
                    title: "Update Tracker",
                    confirmationTitle: "Save",
                    isSaving: trackerManagementViewModel.isSavingTracker,
                    error: trackerManagementViewModel.error,
                    initialName: tracker.name,
                    initialDescription: tracker.description ?? "",
                    initialVisibility: tracker.visibility
                ) { name, description, visibility in
                    if let updatedTracker = await trackerManagementViewModel.updateTracker(
                        name: name,
                        description: description,
                        visibility: visibility
                    ) {
                        tracker = updatedTracker
                        onTrackerUpdated(updatedTracker)
                        return true
                    }
                    return false
                }
            }
        }
        .sheet(isPresented: $showTrackerACLs) {
            if let trackerManagementViewModel {
                TrackerACLManagementSheet(viewModel: trackerManagementViewModel)
                    .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showTrackerLabels, onDismiss: syncTrackerLabelsIntoTicketList) {
            if let trackerManagementViewModel {
                TrackerLabelManagementSheet(viewModel: trackerManagementViewModel)
                    .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showBulkCloseSheet) {
            if let viewModel {
                BulkResolveSheet(
                    viewModel: viewModel,
                    isPresented: $showBulkCloseSheet,
                    onComplete: { result in
                        bulkActionResult = result
                    }
                )
                    .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showBulkAssignSheet) {
            if let viewModel {
                BulkAssignSheet(
                    viewModel: viewModel,
                    currentUser: appState.currentUser,
                    isPresented: $showBulkAssignSheet,
                    onComplete: { result in
                        bulkActionResult = result
                    }
                )
                .presentationDetents([.medium])
            }
        }
        .alert("Delete Tracker?", isPresented: $showDeleteTrackerConfirmation) {
            Button("Cancel", role: .cancel) {
                // no-op: .cancel role handles alert dismissal
            }
            Button("Delete", role: .destructive) {
                guard let trackerManagementViewModel else { return }
                Task {
                    let didDelete = await trackerManagementViewModel.deleteTracker()
                    if didDelete {
                        onTrackerDeleted(tracker)
                        dismiss()
                    }
                }
            }
        } message: {
            Text("“\(tracker.name)” will be permanently deleted.")
        }
        .alert(item: $bulkActionResult) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .navigationDestination(isPresented: Binding(
            get: { createdTicket != nil },
            set: { isPresented in
                if !isPresented {
                    createdTicket = nil
                }
            }
        )) {
            if let createdTicket {
                TicketDetailView(
                    ownerUsername: String(tracker.owner.canonicalName.dropFirst()),
                    trackerName: tracker.name,
                    trackerId: tracker.id,
                    trackerRid: tracker.rid,
                    ticketId: createdTicket.id
                )
            }
        }
        .task {
            if viewModel == nil {
                let vm = TicketListViewModel(
                    ownerUsername: String(tracker.owner.canonicalName.dropFirst()),
                    trackerName: tracker.name,
                    trackerId: tracker.id,
                    trackerRid: tracker.rid,
                    client: appState.client,
                    defaults: appState.accountDefaults
                )
                viewModel = vm
                trackerManagementViewModel = TrackerManagementViewModel(tracker: tracker, client: appState.client)
                await vm.loadTickets()
                await vm.loadTrackerLabels()
            }
        }
    }

    @ViewBuilder
    private func listContent(_ viewModel: TicketListViewModel) -> some View {
        @Bindable var vm = viewModel

        List {
            Section {
                TicketListFilterHeader(
                    selectedLabels: viewModel.selectedLabels,
                    savedFilters: viewModel.savedFilters,
                    activeSavedFilterID: viewModel.activeSavedFilterID,
                    canSaveCurrentFilter: viewModel.hasCustomFilterSelection,
                    isSelectionMode: viewModel.isSelectionMode,
                    selectedTicketCount: viewModel.selectedTicketCount,
                    filter: $vm.filter
                ) {
                    showLabelFilterSheet = true
                } onSaveFilter: {
                    showSaveFilterSheet = true
                } onResetFilters: {
                    vm.resetFilters()
                } onApplySavedFilter: { savedFilter in
                    vm.applySavedFilter(savedFilter)
                } onDeleteSavedFilter: { savedFilter in
                    vm.deleteSavedFilter(savedFilter)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                ForEach(viewModel.filteredTickets) { ticket in
                    Group {
                        if viewModel.isSelectionMode {
                            Button {
                                viewModel.toggleTicketSelection(ticket)
                            } label: {
                                SelectableTicketRow(
                                    ticket: ticket,
                                    isSelected: viewModel.selectedTicketIDs.contains(ticket.id)
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                TicketDetailView(
                                    ownerUsername: String(tracker.owner.canonicalName.dropFirst()),
                                    trackerName: tracker.name,
                                    trackerId: tracker.id,
                                    trackerRid: tracker.rid,
                                    ticketId: ticket.id
                                )
                            } label: {
                                TicketRowView(ticket: ticket)
                            }
                            .contextMenu {
                                if let url = SRHTWebURL.ticket(ownerUsername: ownerUsername(for: tracker), trackerName: tracker.name, ticketId: ticket.id) {
                                    Button {
                                        openURL(url)
                                    } label: {
                                        Label("Open in Browser", systemImage: "safari")
                                    }

                                    Button {
                                        appState.copyToPasteboard(url.absoluteString, label: "ticket URL")
                                    } label: {
                                        Label("Copy URL", systemImage: "doc.on.doc")
                                    }
                                }

                                Button {
                                    appState.copyToPasteboard(String(ticket.id), label: "ticket ID")
                                } label: {
                                    Label("Copy Ticket ID", systemImage: "number")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if swipeActionsEnabled {
                                    ticketAssignSwipeAction(ticket, viewModel: viewModel)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if swipeActionsEnabled {
                                    ticketStatusSwipeAction(ticket, viewModel: viewModel)
                                    ticketLabelSwipeAction(ticket, viewModel: viewModel)
                                }
                            }
                        }
                    }
                    .task {
                        await viewModel.loadMoreIfNeeded(currentItem: ticket)
                    }
                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .searchable(
            text: $vm.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search tickets in \(tracker.name)"
        )
        .searchSuggestions {
            if viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                RecentSearchSuggestions(
                    title: "Recent Ticket Searches",
                    entries: viewModel.recentSearches
                ) { query in
                    vm.searchText = query
                } onClear: {
                    viewModel.clearRecentSearches()
                }
            }
        }
        .onSubmit(of: .search) {
            let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }
            viewModel.recordRecentSearch(query)
        }
        .overlay {
            if viewModel.isLoading, viewModel.tickets.isEmpty {
                SRHTLoadingStateView(message: "Loading tickets…")
            } else if let error = viewModel.error, viewModel.tickets.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Tickets",
                    message: error,
                    retryAction: { await viewModel.loadTickets() }
                )
            } else if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      viewModel.filteredTickets.isEmpty {
                ContentUnavailableView(
                    "No Ticket Matches",
                    systemImage: "magnifyingglass",
                    description: Text("No tickets in \(tracker.name) matched “\(viewModel.searchText)”.")
                )
            } else if viewModel.filteredTickets.isEmpty, viewModel.error == nil {
                ContentUnavailableView(
                    "No Tickets",
                    systemImage: "ticket",
                    description: Text(emptyStateDescription(for: viewModel))
                )
            }
        }
        .connectivityOverlay(hasContent: !viewModel.filteredTickets.isEmpty) {
            await viewModel.loadTickets()
        }
        .srhtErrorBanner(error: $vm.error)
        .refreshable {
            await viewModel.loadTickets()
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.isSelectionMode {
                TicketBulkActionBar(
                    selectedCount: viewModel.selectedTicketCount,
                    isPerformingAction: viewModel.isPerformingAction,
                    onClose: {
                        showBulkCloseSheet = true
                    },
                    onAssign: {
                        showBulkAssignSheet = true
                    }
                )
            }
        }
    }

    private func emptyStateDescription(for viewModel: TicketListViewModel) -> String {
        if !viewModel.selectedLabelIDs.isEmpty {
            return "No \(viewModel.filter.rawValue.lowercased()) tickets found for the selected labels."
        }
        return "No \(viewModel.filter.rawValue.lowercased()) tickets found."
    }

    private func syncTrackerLabelsIntoTicketList() {
        guard let trackerManagementViewModel, let viewModel else { return }
        viewModel.syncTrackerLabels(trackerManagementViewModel.labels)
    }

    private var trackerActionsMenu: some View {
        Menu {
            if let trackerURL = SRHTWebURL.tracker(tracker) {
                Button {
                    openURL(trackerURL)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }

                Button {
                    appState.copyToPasteboard(trackerURL.absoluteString, label: "tracker URL")
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                }
            }

            Button {
                appState.copyToPasteboard(String(tracker.id), label: "tracker ID")
            } label: {
                Label("Copy Tracker ID", systemImage: "number")
            }

            Button {
                appState.copyToPasteboard(tracker.rid, label: "tracker RID")
            } label: {
                Label("Copy RID", systemImage: "number")
            }

            if isOwnedByCurrentUser {
                Divider()

            Button {
                showTrackerEditor = true
            } label: {
                Label("Update Tracker", systemImage: "pencil")
            }

            Button {
                showTrackerACLs = true
            } label: {
                Label("Manage ACLs", systemImage: "person.2")
            }

            Button {
                showTrackerLabels = true
            } label: {
                Label("Manage Labels", systemImage: "tag")
            }

            Button(role: .destructive) {
                showDeleteTrackerConfirmation = true
            } label: {
                Label("Delete Tracker", systemImage: "trash")
            }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Tracker actions")
    }

    private func ownerUsername(for tracker: TrackerSummary) -> String {
        tracker.owner.canonicalName.srhtUsername
    }

    @ViewBuilder
    private func ticketAssignSwipeAction(
        _ ticket: TicketSummary,
        viewModel: TicketListViewModel
    ) -> some View {
        if let currentUser = appState.currentUser {
            let isAssigned = ticket.assignees.contains { assignee in
                matchesAssignee(assignee, user: currentUser)
            }

            if isAssigned {
                Button {
                    Task {
                        await viewModel.unassignFromMe(ticket: ticket, user: currentUser)
                    }
                } label: {
                    Label("Unassign Me", systemImage: "person.badge.minus")
                }
                .tint(.orange)
            } else {
                Button {
                    Task {
                        await viewModel.assignToMe(ticket: ticket, user: currentUser)
                    }
                } label: {
                    Label("Assign Me", systemImage: "person.badge.plus")
                }
                .tint(.cyan)
            }
        }
    }

    @ViewBuilder
    private func ticketStatusSwipeAction(
        _ ticket: TicketSummary,
        viewModel: TicketListViewModel
    ) -> some View {
        if ticket.status.isOpen {
            Button {
                Task { await viewModel.resolveTicket(ticket) }
            } label: {
                Label("Close", systemImage: "xmark.circle")
            }
            .tint(.red)
        } else {
            Button {
                Task { await viewModel.reopenTicket(ticket) }
            } label: {
                Label("Reopen", systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private func ticketLabelSwipeAction(
        _ ticket: TicketSummary,
        viewModel: TicketListViewModel
    ) -> some View {
        Button {
            labelEditorTicket = LabelEditorTicket(id: ticket.id)
            Task { await viewModel.loadTrackerLabels() }
        } label: {
            Label("Labels", systemImage: "tag")
        }
        .tint(.purple)
    }

    private func matchesAssignee(_ entity: Entity, user: User) -> Bool {
        let assigneeCanonical = normalizedCanonicalName(entity.canonicalName)
        let userCanonical = normalizedCanonicalName(user.canonicalName)
        if assigneeCanonical == userCanonical {
            return true
        }
        return normalizedUsername(entity.canonicalName) == normalizedUsername(user.username)
    }

    private func normalizedCanonicalName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("~") {
            return trimmed
        }
        return "~\(trimmed)"
    }

    private func normalizedUsername(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("~") ? String(trimmed.dropFirst()) : trimmed
    }
}

private struct LabelEditorTicket: Identifiable {
    let id: Int
}

private struct CreateTicketSheet: View {
    let viewModel: TicketListViewModel
    let onCreated: (TicketSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var descriptionText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Ticket Details") {
                    TextField("Title", text: $subject)
                    TextField("Description (optional)", text: $descriptionText, axis: .vertical)
                        .lineLimit(6...12)
                }
            }
            .navigationTitle("New Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let ticket = await viewModel.createTicket(subject: subject, body: descriptionText) {
                                onCreated(ticket)
                            }
                        }
                    } label: {
                        if viewModel.isCreatingTicket {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Create Ticket")
                        }
                    }
                    .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isCreatingTicket)
                }
            }
        }
    }
}

private struct TicketLabelsSheet: View {
    let ticketId: Int
    let viewModel: TicketListViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let ticket = viewModel.ticket(withId: ticketId) {
                    if viewModel.trackerLabels.isEmpty {
                        if viewModel.isPerformingAction {
                            ProgressView()
                        } else {
                            ContentUnavailableView(
                                "No Labels",
                                systemImage: "tag",
                                description: Text("This tracker has no labels defined.")
                            )
                        }
                    } else {
                        List {
                            ForEach(viewModel.trackerLabels) { label in
                                TicketListLabelToggleRow(
                                    label: label,
                                    isApplied: ticket.labels.contains(where: { $0.id == label.id }),
                                    isLoading: viewModel.isPerformingAction
                                ) { shouldApply in
                                    Task {
                                        if shouldApply {
                                            await viewModel.labelTicket(ticket, label: label)
                                        } else {
                                            await viewModel.unlabelTicket(ticket, label: label)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Ticket Unavailable",
                        systemImage: "ticket",
                        description: Text("This ticket is no longer in the current list.")
                    )
                }
            }
            .navigationTitle("Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if viewModel.trackerLabels.isEmpty {
                    await viewModel.loadTrackerLabels()
                }
            }
        }
    }
}

private struct TicketListFilterHeader: View {
    let selectedLabels: [TicketLabel]
    let savedFilters: [SavedTicketFilter]
    let activeSavedFilterID: SavedTicketFilter.ID?
    let canSaveCurrentFilter: Bool
    let isSelectionMode: Bool
    let selectedTicketCount: Int
    @Binding var filter: TicketFilter
    let onShowLabels: () -> Void
    let onSaveFilter: () -> Void
    let onResetFilters: () -> Void
    let onApplySavedFilter: (SavedTicketFilter) -> Void
    let onDeleteSavedFilter: (SavedTicketFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isSelectionMode {
                Text(selectionSummary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Picker("Filter", selection: $filter) {
                ForEach(TicketFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isSelectionMode)

            TicketQuickFilterBar(
                selectedLabels: selectedLabels,
                savedFilters: savedFilters,
                activeSavedFilterID: activeSavedFilterID,
                canSaveCurrentFilter: canSaveCurrentFilter,
                onShowLabels: onShowLabels,
                onSaveFilter: onSaveFilter,
                onResetFilters: onResetFilters,
                onApplySavedFilter: onApplySavedFilter,
                onDeleteSavedFilter: onDeleteSavedFilter
            )
            .disabled(isSelectionMode)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var selectionSummary: String {
        selectedTicketCount == 0 ? "Select tickets for bulk actions." : "\(selectedTicketCount) selected"
    }
}

private struct TicketQuickFilterBar: View {
    let selectedLabels: [TicketLabel]
    let savedFilters: [SavedTicketFilter]
    let activeSavedFilterID: SavedTicketFilter.ID?
    let canSaveCurrentFilter: Bool
    let onShowLabels: () -> Void
    let onSaveFilter: () -> Void
    let onResetFilters: () -> Void
    let onApplySavedFilter: (SavedTicketFilter) -> Void
    let onDeleteSavedFilter: (SavedTicketFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionButtons

            if !selectedLabels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedLabels) { label in
                            LabelPill(label: label)
                        }
                    }
                }
            }

            if !savedFilters.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(savedFilters) { savedFilter in
                            Button {
                                onApplySavedFilter(savedFilter)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: activeSavedFilterID == savedFilter.id ? "checkmark.circle.fill" : "line.3.horizontal.decrease.circle")
                                        .imageScale(.small)
                                    Text(savedFilter.name)
                                        .lineLimit(1)
                                }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .foregroundStyle(activeSavedFilterID == savedFilter.id ? Color.accentColor : Color.primary)
                                .background(
                                    activeSavedFilterID == savedFilter.id ?
                                    Color.accentColor.opacity(0.14) :
                                    Color(.secondarySystemFill),
                                    in: Capsule()
                                )
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    onDeleteSavedFilter(savedFilter)
                                } label: {
                                    Label("Delete Filter", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var labelButtonTitle: String {
        selectedLabels.isEmpty ? "Labels" : "Labels (\(selectedLabels.count))"
    }

    @ViewBuilder
    private var actionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                labelsButton
                saveFilterButton
                if canSaveCurrentFilter {
                    resetButton
                }
                Spacer(minLength: 0)
            }

            FlowLayout(spacing: 8) {
                labelsButton
                saveFilterButton
                if canSaveCurrentFilter {
                    resetButton
                }
            }
        }
    }

    private var labelsButton: some View {
        Button(action: onShowLabels) {
            Label(labelButtonTitle, systemImage: "tag")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
    }

    private var saveFilterButton: some View {
        Button(action: onSaveFilter) {
            Label("Save Filter", systemImage: "square.and.arrow.down")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .disabled(!canSaveCurrentFilter)
    }

    private var resetButton: some View {
        Button("Reset", action: onResetFilters)
            .font(.caption.weight(.medium))
            .buttonStyle(.bordered)
    }
}

private struct TicketFilterLabelsSheet: View {
    let viewModel: TicketListViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.availableLabels.isEmpty {
                    ContentUnavailableView(
                        "No Labels",
                        systemImage: "tag",
                        description: Text("This tracker has no labels available for filtering yet.")
                    )
                } else {
                    List {
                        if !viewModel.selectedLabels.isEmpty {
                            Section("Selected") {
                                FlowLayout(spacing: 6) {
                                    ForEach(viewModel.selectedLabels) { label in
                                        LabelPill(label: label)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        Section("Labels") {
                            ForEach(viewModel.availableLabels) { label in
                                Button {
                                    viewModel.toggleLabelSelection(label)
                                } label: {
                                    HStack {
                                        LabelPill(label: label)
                                        Spacer()
                                        if viewModel.selectedLabelIDs.contains(label.id) {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !viewModel.selectedLabelIDs.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Clear") { viewModel.clearLabelSelection() }
                    }
                }
            }
            .task {
                if viewModel.availableLabels.isEmpty {
                    await viewModel.loadTrackerLabels()
                }
            }
        }
    }
}

private struct SaveTicketFilterSheet: View {
    let viewModel: TicketListViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(viewModel: TicketListViewModel) {
        self.viewModel = viewModel
        self._name = State(initialValue: viewModel.suggestedSavedFilterName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Filter name", text: $name)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("Save Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveCurrentFilter(named: name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct TicketListLabelToggleRow: View {
    let label: TicketLabel
    let isApplied: Bool
    let isLoading: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isApplied)
        } label: {
            HStack {
                LabelPill(label: label)
                Spacer()
                if isApplied {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
        .disabled(isLoading)
    }
}

private struct TicketBulkActionBar: View {
    let selectedCount: Int
    let isPerformingAction: Bool
    let onClose: () -> Void
    let onAssign: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(selectedCount == 0 ? "Select tickets to continue" : "\(selectedCount) selected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 12) {
                Button("Close") {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedCount == 0 || isPerformingAction)

                Button("Assign") {
                    onAssign()
                }
                .buttonStyle(.bordered)
                .disabled(selectedCount == 0 || isPerformingAction)

                if isPerformingAction {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }
}

private struct BulkResolveSheet: View {
    let viewModel: TicketListViewModel
    @Binding var isPresented: Bool
    let onComplete: (TicketBulkActionResult) -> Void
    @State private var selectedResolution: TicketResolution = .fixed

    private static let resolutionOptions: [TicketResolution] = [
        .closed, .fixed, .implemented, .wontFix,
        .byDesign, .invalid, .duplicate, .notOurBug
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(viewModel.selectedTicketCount) ticket\(viewModel.selectedTicketCount == 1 ? "" : "s") selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Resolution") {
                    Picker("Resolution", selection: $selectedResolution) {
                        ForEach(Self.resolutionOptions, id: \.self) { resolution in
                            Text(resolution.displayName).tag(resolution)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Close Tickets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        Task {
                            if let result = await viewModel.closeSelectedTickets(resolution: selectedResolution) {
                                onComplete(result)
                                isPresented = false
                            }
                        }
                    }
                    .disabled(viewModel.selectedTicketCount == 0 || viewModel.isPerformingAction)
                }
            }
        }
    }
}

private struct BulkAssignSheet: View {
    let viewModel: TicketListViewModel
    let currentUser: User?
    @Binding var isPresented: Bool
    let onComplete: (TicketBulkActionResult) -> Void
    @State private var username = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(viewModel.selectedTicketCount) ticket\(viewModel.selectedTicketCount == 1 ? "" : "s") selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let currentUser {
                    Section {
                        Button("Assign to Me") {
                            Task {
                                if let result = await viewModel.assignSelectedTickets(username: currentUser.username) {
                                    onComplete(result)
                                    isPresented = false
                                }
                            }
                        }
                        .disabled(viewModel.selectedTicketCount == 0 || viewModel.isPerformingAction)
                    }
                }

                Section("Assign User") {
                    TextField("Username or ~username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Assign Tickets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Assign") {
                        Task {
                            if let result = await viewModel.assignSelectedTickets(username: username) {
                                onComplete(result)
                                isPresented = false
                            }
                        }
                    }
                    .disabled(
                        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || viewModel.selectedTicketCount == 0
                        || viewModel.isPerformingAction
                    )
                }
            }
        }
    }
}

private struct SelectableTicketRow: View {
    let ticket: TicketSummary
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.top, 4)

            TicketRowView(ticket: ticket)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Ticket Row

private struct TicketRowView: View {
    let ticket: TicketSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                TicketStatusIcon(status: ticket.status)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(ticket.id)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    + Text(" ")
                    + Text(ticket.title)
                        .font(.subheadline)
                }

                Spacer()

                TicketStatusBadge(status: ticket.status)
            }

            HStack(spacing: 8) {
                Text(ticket.submitter.canonicalName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(ticket.created.relativeDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !ticket.labels.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(ticket.labels) { label in
                        LabelPill(label: label)
                    }
                }
            }

            if !ticket.assignees.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(ticket.assignees.map(\.canonicalName).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Ticket Status Badge

private struct TicketStatusBadge: View {
    let status: TicketStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .reported:   .gray
        case .confirmed:  .blue
        case .inProgress: .yellow
        case .pending:    .orange
        case .resolved:   .green
        }
    }
}

// MARK: - Ticket Status Icon

struct TicketStatusIcon: View {
    let status: TicketStatus

    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(color)
    }

    private var iconName: String {
        switch status {
        case .reported:   "circle"
        case .confirmed:  "circle.inset.filled"
        case .inProgress: "arrow.trianglehead.2.clockwise.rotate.90"
        case .pending:    "clock.fill"
        case .resolved:   "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .reported:   .gray
        case .confirmed:  .blue
        case .inProgress: .yellow
        case .pending:    .orange
        case .resolved:   .green
        }
    }
}

// MARK: - Label Pill

struct LabelPill: View {
    let label: TicketLabel

    var body: some View {
        Text(label.name)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        Color(hex: label.backgroundColor) ?? .gray.opacity(0.2)
    }

    private var foregroundColor: Color {
        Color(hex: label.foregroundColor) ?? .primary
    }
}

// MARK: - Color from hex string

extension Color {
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        guard hexString.count == 6,
              let hexNumber = UInt64(hexString, radix: 16) else {
            return nil
        }

        let r = Double((hexNumber & 0xFF0000) >> 16) / 255
        let g = Double((hexNumber & 0x00FF00) >> 8) / 255
        let b = Double(hexNumber & 0x0000FF) / 255

        self.init(red: r, green: g, blue: b)
    }

    /// Returns a `#rrggbb` hex string for this color.
    var hexString: String {
        let resolved = resolve(in: .init())
        let r = Int(max(0, min(1, resolved.red)) * 255)
        let g = Int(max(0, min(1, resolved.green)) * 255)
        let b = Int(max(0, min(1, resolved.blue)) * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

// MARK: - Flow Layout (for label pills)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private struct LayoutResult {
        var positions: [CGPoint]
        var sizes: [CGSize]
        var size: CGSize
    }

    private func layoutSubviews(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = currentY + lineHeight
        }

        return LayoutResult(
            positions: positions,
            sizes: sizes,
            size: CGSize(width: totalWidth, height: totalHeight)
        )
    }
}
