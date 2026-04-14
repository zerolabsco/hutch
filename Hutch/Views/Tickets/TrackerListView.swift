import SwiftUI

struct TrackerListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: TrackerListViewModel?
    @State private var showCreateTrackerSheet = false
    @State private var createdTracker: TrackerSummary?
    @State private var editingTracker: TrackerSummary?
    @State private var pendingDeletion: TrackerSummary?

    var body: some View {
        Group {
            if let viewModel {
                listContent(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading trackers…")
            }
        }
        .navigationTitle("Trackers")
        .toolbar {
            if viewModel != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateTrackerSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateTrackerSheet) {
            if let viewModel {
                TrackerEditorSheet(
                    title: "New Tracker",
                    confirmationTitle: "Create Tracker",
                    isSaving: viewModel.isCreatingTracker,
                    error: viewModel.error,
                    initialName: "",
                    initialDescription: "",
                    initialVisibility: .public
                ) { name, description, visibility in
                    if let tracker = await viewModel.createTracker(
                        name: name,
                        description: description,
                        visibility: visibility
                    ) {
                        createdTracker = tracker
                        showCreateTrackerSheet = false
                        return true
                    }
                    return false
                }
            }
        }
        .sheet(item: $editingTracker) { tracker in
            if let viewModel {
                TrackerEditorSheet(
                    title: "Update Tracker",
                    confirmationTitle: "Save",
                    isSaving: viewModel.isCreatingTracker,
                    error: viewModel.error,
                    initialName: tracker.name,
                    initialDescription: tracker.description ?? "",
                    initialVisibility: tracker.visibility
                ) { name, description, visibility in
                    if let updatedTracker = await viewModel.updateTracker(
                        tracker,
                        name: name,
                        description: description,
                        visibility: visibility
                    ) {
                        createdTracker = createdTracker?.id == tracker.id ? updatedTracker : createdTracker
                        editingTracker = nil
                        return true
                    }
                    return false
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { createdTracker != nil },
            set: { isPresented in
                if !isPresented {
                    createdTracker = nil
                }
            }
        )) {
            if let createdTracker {
                TicketListView(tracker: createdTracker) { updatedTracker in
                    viewModel?.applyTrackerUpdate(updatedTracker)
                    self.createdTracker = updatedTracker
                } onTrackerDeleted: { deletedTracker in
                    viewModel?.applyTrackerDeletion(deletedTracker)
                    if let viewModel {
                        Task { await viewModel.loadTrackers() }
                    }
                    self.createdTracker = nil
                }
            }
        }
        .alert("Delete Tracker?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )) {
            Button("Cancel", role: .cancel) {
                // no-op: .cancel role handles alert dismissal
            }
            Button("Delete", role: .destructive) {
                guard let pendingDeletion, let viewModel else { return }
                Task {
                    let didDelete = await viewModel.deleteTracker(pendingDeletion)
                    if didDelete {
                        if createdTracker?.id == pendingDeletion.id {
                            createdTracker = nil
                        }
                        self.pendingDeletion = nil
                    }
                }
            }
        } message: {
            if let pendingDeletion {
                Text("“\(pendingDeletion.name)” will be permanently deleted.")
            }
        }
        .task {
            if viewModel == nil {
                let vm = TrackerListViewModel(client: appState.client)
                viewModel = vm
                await vm.loadTrackers()
            }
        }
    }

    @ViewBuilder
    private func listContent(_ viewModel: TrackerListViewModel) -> some View {
        @Bindable var vm = viewModel

        List {
            ForEach(viewModel.filteredTrackers) { tracker in
                NavigationLink(value: tracker) {
                    TrackerRowView(tracker: tracker)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeletion = tracker
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        editingTracker = tracker
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .task {
                    await viewModel.loadMoreIfNeeded(currentItem: tracker)
                }
            }
            .themedRow()

            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .themedRow()
            }
        }
        .themedList()
        .listStyle(.plain)
        .searchable(
            text: $vm.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search trackers"
        )
        .overlay {
            if viewModel.isLoading, viewModel.trackers.isEmpty {
                SRHTLoadingStateView(message: "Loading trackers…")
            } else if let error = viewModel.error, viewModel.trackers.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Trackers",
                    message: error,
                    retryAction: { await viewModel.loadTrackers() }
                )
            } else if !viewModel.trackers.isEmpty, viewModel.filteredTrackers.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else if viewModel.trackers.isEmpty, viewModel.error == nil {
                ContentUnavailableView(
                    "No Trackers",
                    systemImage: "checklist",
                    description: Text("Your bug trackers will appear here.")
                )
            }
        }
        .connectivityOverlay(hasContent: !viewModel.trackers.isEmpty) {
            await viewModel.loadTrackers()
        }
        .srhtErrorBanner(error: $vm.error)
        .refreshable {
            await viewModel.loadTrackers()
        }
        .navigationDestination(for: TrackerSummary.self) { tracker in
            TicketListView(tracker: tracker) { updatedTracker in
                viewModel.applyTrackerUpdate(updatedTracker)
                if createdTracker?.id == updatedTracker.id {
                    createdTracker = updatedTracker
                }
            } onTrackerDeleted: { deletedTracker in
                viewModel.applyTrackerDeletion(deletedTracker)
                Task { await viewModel.loadTrackers() }
                if createdTracker?.id == deletedTracker.id {
                    createdTracker = nil
                }
            }
        }
    }
}

// MARK: - Tracker Row

private struct TrackerRowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    let tracker: TrackerSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tracker.name)
                    .font(.subheadline.weight(.medium))

                Spacer()

                VisibilityBadge(visibility: tracker.visibility)
            }

            if let owner = tracker.owner.canonicalName.split(separator: "~").last {
                Text("~\(owner)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let description = tracker.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(tracker.updated.relativeDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let url = SRHTWebURL.tracker(tracker) {
                Button {
                    openURL(url)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }

                Button {
                    appState.copyToPasteboard(url.absoluteString, label: "tracker URL")
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
        }
    }
}
