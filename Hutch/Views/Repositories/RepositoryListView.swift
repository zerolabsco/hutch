import SwiftUI

struct RepositoryListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: RepositoryListViewModel?
    @State private var searchTask: Task<Void, Never>?
    @State private var immediateSearchTask: Task<Void, Never>?
    @State private var showCreateRepositorySheet = false
    @State private var createdRepository: RepositorySummary?

    var body: some View {
        Group {
            if let viewModel {
                listContent(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading repositories…")
            }
        }
        .navigationTitle("Repositories")
        .toolbar {
            if viewModel != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateRepositorySheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create repository")
                }
            }
        }
        .sheet(isPresented: $showCreateRepositorySheet) {
            if let viewModel {
                CreateRepositorySheet(viewModel: viewModel) { repository in
                    showCreateRepositorySheet = false
                    createdRepository = repository
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { createdRepository != nil },
            set: { isPresented in
                if !isPresented {
                    createdRepository = nil
                }
            }
        )) {
            if let createdRepository {
                RepositoryDetailView(
                    repository: createdRepository,
                    onRepositoryUpdated: { updatedRepository in
                        self.createdRepository = updatedRepository
                        viewModel?.updateRepository(updatedRepository)
                    }
                ) {
                    viewModel?.removeRepository(id: createdRepository.id)
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = RepositoryListViewModel(client: appState.client, defaults: appState.accountDefaults)
            }
        }
    }

    @ViewBuilder
    private func listContent(_ viewModel: RepositoryListViewModel) -> some View {
        @Bindable var vm = viewModel

        List {
            if viewModel.isSearching {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching repositories…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
            }

            ForEach(viewModel.repositories) { repo in
                NavigationLink(value: repo) {
                    RepositoryRowView(
                        repository: repo,
                        buildStatus: viewModel.latestBuildStatus(for: repo)
                    )
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .task {
                    await viewModel.loadMoreIfNeeded(currentItem: repo)
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
        .themedList()
        .listStyle(.plain)
        .searchable(
            text: $vm.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search repositories by name, owner, or description"
        )
        .searchSuggestions {
            if viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                RecentSearchSuggestions(
                    title: "Recent Repository Searches",
                    entries: viewModel.recentSearches
                ) { query in
                    searchTask?.cancel()
                    immediateSearchTask?.cancel()
                    vm.searchText = query
                    immediateSearchTask = Task {
                        await viewModel.loadRepositories(search: query)
                    }
                } onClear: {
                    viewModel.clearRecentSearches()
                }
            }
        }
        .overlay {
            if viewModel.isLoading, viewModel.repositories.isEmpty {
                SRHTLoadingStateView(message: "Loading repositories…")
            } else if let error = viewModel.error, viewModel.repositories.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Repositories",
                    message: error,
                    retryAction: { await viewModel.loadRepositories() }
                )
            } else if viewModel.repositories.isEmpty, viewModel.error == nil {
                if viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "No Repositories",
                        systemImage: "book.closed",
                        description: Text("You don't have any repositories yet.")
                    )
                } else {
                    ContentUnavailableView(
                        "No Repository Matches",
                        systemImage: "magnifyingglass",
                        description: Text("No repositories matched “\(viewModel.searchText)”.")
                    )
                }
            }
        }
        .connectivityOverlay(hasContent: !viewModel.repositories.isEmpty) {
            await viewModel.loadRepositories()
        }
        .srhtErrorBanner(error: $vm.error)
        .refreshable {
            await viewModel.loadRepositories()
        }
        .task {
            await viewModel.loadRepositories()
        }
        .onSubmit(of: .search) {
            let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }

            searchTask?.cancel()
            immediateSearchTask?.cancel()
            viewModel.recordRecentSearch(query)
            immediateSearchTask = Task {
                await viewModel.loadRepositories(search: query)
            }
        }
        .onChange(of: viewModel.searchText) { oldValue, newValue in
            // Cancel previous search task
            searchTask?.cancel()
            immediateSearchTask?.cancel()
            
            // Clear results immediately when search text is cleared
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.resetSearch()
                Task {
                    await viewModel.loadRepositories()
                }
                return
            }
            
            // Debounce search to avoid excessive API calls
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await viewModel.loadRepositories(search: newValue)
            }
        }
        .navigationDestination(for: RepositorySummary.self) { repo in
            RepositoryDetailView(
                repository: repo,
                onRepositoryUpdated: { updatedRepository in
                    viewModel.updateRepository(updatedRepository)
                }
            ) {
                viewModel.removeRepository(id: repo.id)
            }
        }
    }
}

private struct CreateRepositorySheet: View {
    let viewModel: RepositoryListViewModel
    let onCreated: (RepositorySummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var cloneURL = ""
    @State private var visibility: Visibility = .public
    @State private var service: RepositoryCreationService = .git

    var body: some View {
        NavigationStack {
            Form {
                Section("Repository Details") {
                    Picker("Version Control", selection: $service) {
                        ForEach(RepositoryCreationService.allCases) { service in
                            Text(service.displayName).tag(service)
                        }
                    }
                    TextField("Repository name", text: $name)
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

                Section("Import Existing Repository") {
                    if service == .git {
                        TextField("Remote URL (optional)", text: $cloneURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Text("Import an existing Git repository from a remote URL.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Importing a Mercurial repository from a remote URL is not available through the public API.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(service == .git ? "New Git Repository" : "New Mercurial Repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let repository = await viewModel.createRepository(
                                service: service,
                                name: name,
                                description: description,
                                visibility: visibility,
                                cloneURL: cloneURL
                            ) {
                                onCreated(repository)
                            }
                        }
                    } label: {
                        if viewModel.isCreatingRepository {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isCreatingRepository)
                }
            }
        }
    }
}
