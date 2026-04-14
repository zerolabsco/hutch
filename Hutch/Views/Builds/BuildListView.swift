import SwiftUI

struct BuildListView: View {
    @AppStorage(AppStorageKeys.swipeActionsEnabled, store: .standard) private var swipeActionsEnabled = true
    @AppStorage(AppStorageKeys.buildsAutoRefreshInterval) private var autoRefreshRawValue = 0
    @AppStorage(AppStorageKeys.buildsRepoFilter) private var savedRepoFilter = ""
    @Environment(AppState.self) private var appState
    @Environment(\.isAMOLEDTheme) private var isAMOLED
    @State private var viewModel: BuildListViewModel?
    @State private var showSubmitSheet = false
    @State private var submittedJobId: Int?

    private var autoRefreshInterval: AutoRefreshInterval {
        AutoRefreshInterval(rawValue: autoRefreshRawValue) ?? .off
    }

    var body: some View {
        Group {
            if let viewModel {
                listContent(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading builds…")
            }
        }
        .navigationTitle("Builds")
        .toolbar {
            if let viewModel {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Section("Auto-Refresh") {
                            ForEach(AutoRefreshInterval.allCases, id: \.self) { interval in
                                Button {
                                    autoRefreshRawValue = interval.rawValue
                                    viewModel.startAutoRefresh(interval: interval)
                                } label: {
                                    if interval.rawValue == autoRefreshRawValue {
                                        Label(interval.label, systemImage: "checkmark")
                                    } else {
                                        Text(interval.label)
                                    }
                                }
                            }
                        }
                        Section("Filter by Tag") {
                            Button {
                                savedRepoFilter = ""
                                viewModel.repoFilter = ""
                            } label: {
                                if savedRepoFilter.isEmpty {
                                    Label("All", systemImage: "checkmark")
                                } else {
                                    Text("All")
                                }
                            }
                            ForEach(viewModel.availableTags, id: \.self) { tag in
                                Button {
                                    savedRepoFilter = tag
                                    viewModel.repoFilter = tag
                                } label: {
                                    if savedRepoFilter == tag {
                                        Label(tag, systemImage: "checkmark")
                                    } else {
                                        Text(tag)
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Build filters")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSubmitSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Submit build")
                }
            }
        }
        .sheet(isPresented: $showSubmitSheet) {
            if let viewModel {
                SubmitBuildSheet(viewModel: viewModel) { jobId in
                    showSubmitSheet = false
                    submittedJobId = jobId
                }
            }
        }
        .navigationDestination(for: JobSummary.self) { job in
            BuildDetailView(jobId: job.id)
        }
        .navigationDestination(isPresented: Binding(
            get: { submittedJobId != nil },
            set: { isPresented in
                if !isPresented {
                    submittedJobId = nil
                }
            }
        )) {
            if let submittedJobId {
                BuildDetailView(jobId: submittedJobId)
            }
        }
        .task {
            if viewModel == nil {
                let vm = BuildListViewModel(client: appState.client, defaults: appState.accountDefaults)
                vm.repoFilter = savedRepoFilter
                viewModel = vm
                await vm.loadJobs()
            }
            // Restart auto-refresh every time the view (re)appears, since
            // onDisappear stops it when navigating away.
            viewModel?.startAutoRefresh(interval: autoRefreshInterval)
        }
        .onDisappear {
            viewModel?.stopAutoRefresh()
        }
    }

    @ViewBuilder
    private func listContent(_ viewModel: BuildListViewModel) -> some View {
        @Bindable var vm = viewModel

        List {
            Section {
                Picker("Filter", selection: $vm.filter) {
                    ForEach(BuildListFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .listRowInsets(EdgeInsets())
                .listRowBackground(isAMOLED ? Color.black : Color.clear)
                .listRowSeparator(.hidden)

                ForEach(viewModel.filteredJobs) { job in
                    NavigationLink(value: job) {
                        BuildRowView(job: job)
                            .equatable()
                    }
                    .contextMenu {
                        Button {
                            appState.copyToPasteboard(String(job.id), label: "job ID")
                        } label: {
                            Label("Copy Job ID", systemImage: "doc.on.doc")
                        }

                        if let note = job.note, !note.isEmpty {
                            Button {
                                appState.copyToPasteboard(note, label: "build note")
                            } label: {
                                Label("Copy Note", systemImage: "text.alignleft")
                            }
                        }

                        if !job.tags.isEmpty {
                            Button {
                                appState.copyToPasteboard(job.tags.joined(separator: ", "), label: "build tags")
                            } label: {
                                Label("Copy Tags", systemImage: "tag")
                            }
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if swipeActionsEnabled, job.status.isCancellable {
                            Button {
                                Task {
                                    await viewModel.cancelJob(job)
                                }
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle")
                            }
                            .tint(.red)
                        }
                    }
                    .task {
                        await viewModel.loadMoreIfNeeded(currentItem: job)
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
        }
        .themedList()
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .searchable(
            text: $vm.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search builds by job ID, tag, note, or status"
        )
        .searchSuggestions {
            if viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                RecentSearchSuggestions(
                    title: "Recent Build Searches",
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
            if viewModel.isLoading, viewModel.jobs.isEmpty {
                SRHTLoadingStateView(message: "Loading builds…")
            } else if let error = viewModel.error, viewModel.jobs.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Builds",
                    message: error,
                    retryAction: { await viewModel.loadJobs() }
                )
            } else if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      viewModel.filteredJobs.isEmpty {
                ContentUnavailableView(
                    "No Build Matches",
                    systemImage: "magnifyingglass",
                    description: Text("No builds matched “\(viewModel.searchText)”.")
                )
            } else if viewModel.jobs.isEmpty, viewModel.error == nil {
                ContentUnavailableView(
                    "No Builds",
                    systemImage: "hammer",
                    description: Text("Your build jobs will appear here.")
                )
            }
        }
        .connectivityOverlay(hasContent: !viewModel.jobs.isEmpty) {
            await viewModel.loadJobs()
        }
        .srhtErrorBanner(error: $vm.error)
        .refreshable {
            await viewModel.loadJobs()
        }
    }
}

private struct SubmitBuildSheet: View {
    let viewModel: BuildListViewModel
    let onSubmitted: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModelBindable: BuildListViewModel
    @State private var manifest = ""
    @State private var tagsText = ""
    @State private var note = ""
    @State private var secrets = false
    @State private var execute = true
    @State private var visibility: Visibility = .public

    init(viewModel: BuildListViewModel, onSubmitted: @escaping (Int) -> Void) {
        self.viewModel = viewModel
        self._viewModelBindable = Bindable(viewModel)
        self.onSubmitted = onSubmitted
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Build Manifest") {
                    TextField("Paste a build manifest", text: $manifest, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(12...24)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .themedRow()
                }

                Section("Build Options") {
                    TextField("Note (optional)", text: $note)
                        .themedRow()
                    TextField("Tags (comma-separated, optional)", text: $tagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .themedRow()
                    Picker("Visibility", selection: $visibility) {
                        Text("Public").tag(Visibility.public)
                        Text("Unlisted").tag(Visibility.unlisted)
                        Text("Private").tag(Visibility.private)
                    }
                    .themedRow()
                    Toggle("Start build now", isOn: $execute)
                        .themedRow()
                    Toggle("Allow build secrets", isOn: $secrets)
                        .themedRow()
                }

                Section {
                    Text("You need a valid builds.sr.ht manifest and a token with BUILDS:RW.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .themedRow()
                }

                if let error = viewModel.error {
                    Section {
                        Label {
                            Text(error)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                        .foregroundStyle(.red)
                        .themedRow()
                    }
                }
            }
            .themedList()
            .navigationTitle("Submit Build")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                viewModelBindable.error = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModelBindable.error = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let tags = tagsText
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            if let jobId = await viewModel.submitBuild(
                                manifest: manifest,
                                tags: tags,
                                note: note,
                                secrets: secrets,
                                execute: execute,
                                visibility: visibility
                            ) {
                                onSubmitted(jobId)
                            }
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Submit Build")
                        }
                    }
                    .disabled(manifest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmitting)
                }
            }
        }
    }
}
