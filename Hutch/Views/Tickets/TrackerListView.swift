import SwiftUI

struct TrackerListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: TrackerListViewModel?
    @State private var showCreateTrackerSheet = false
    @State private var createdTracker: TrackerSummary?

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
                CreateTrackerSheet(viewModel: viewModel) { tracker in
                    showCreateTrackerSheet = false
                    createdTracker = tracker
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
                TicketListView(
                    ownerUsername: String(createdTracker.owner.canonicalName.dropFirst()),
                    trackerName: createdTracker.name,
                    trackerId: createdTracker.id,
                    trackerRid: createdTracker.rid
                )
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
            ForEach(viewModel.trackers) { tracker in
                NavigationLink(value: tracker) {
                    TrackerRowView(tracker: tracker)
                }
                .task {
                    await viewModel.loadMoreIfNeeded(currentItem: tracker)
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
        .listStyle(.plain)
        .overlay {
            if viewModel.isLoading, viewModel.trackers.isEmpty {
                SRHTLoadingStateView(message: "Loading trackers…")
            } else if let error = viewModel.error, viewModel.trackers.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Trackers",
                    message: error,
                    retryAction: { await viewModel.loadTrackers() }
                )
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
            TicketListView(
                ownerUsername: String(tracker.owner.canonicalName.dropFirst()),
                trackerName: tracker.name,
                trackerId: tracker.id,
                trackerRid: tracker.rid
            )
        }
    }
}

private struct CreateTrackerSheet: View {
    let viewModel: TrackerListViewModel
    let onCreated: (TrackerSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var visibility: Visibility = .public

    var body: some View {
        NavigationStack {
            Form {
                Section("Tracker Details") {
                    TextField("Tracker name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Short description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Visibility", selection: $visibility) {
                        Text("Public").tag(Visibility.public)
                        Text("Unlisted").tag(Visibility.unlisted)
                        Text("Private").tag(Visibility.private)
                    }
                }
            }
            .navigationTitle("New Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let tracker = await viewModel.createTracker(
                                name: name,
                                description: description,
                                visibility: visibility
                            ) {
                                onCreated(tracker)
                            }
                        }
                    } label: {
                        if viewModel.isCreatingTracker {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Create Tracker")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isCreatingTracker)
                }
            }
        }
    }
}

// MARK: - Tracker Row

private struct TrackerRowView: View {
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
    }
}
