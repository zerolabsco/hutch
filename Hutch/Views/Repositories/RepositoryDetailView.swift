import SwiftUI

struct RepositoryDetailView: View {
    @Environment(\.openURL) private var openURL

    let onRepositoryUpdated: ((RepositorySummary) -> Void)?
    var onDeleted: (() -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RepositoryDetailViewModel?
    @State private var selectedTab: RepositoryDetailViewModel.Tab = .summary
    @State private var showSettings = false
    @State private var showACLs = false
    @State private var currentRepository: RepositorySummary

    private var canManageRepository: Bool {
        guard let currentUser = appState.currentUser else { return false }
        return normalizedUsername(currentUser.username) == normalizedUsername(currentRepository.owner.canonicalName)
    }

    init(
        repository: RepositorySummary,
        onRepositoryUpdated: ((RepositorySummary) -> Void)? = nil,
        onDeleted: (() -> Void)? = nil
    ) {
        self.onRepositoryUpdated = onRepositoryUpdated
        self.onDeleted = onDeleted
        self._currentRepository = State(initialValue: repository)
    }

    var body: some View {
        if currentRepository.service == .hg {
            HgRepositoryDetailView(repository: currentRepository, onDeleted: onDeleted)
        } else {
            Group {
                if let viewModel {
                    detailContent(viewModel)
                } else {
                    SRHTLoadingStateView(message: "Loading repository…")
                }
            }
            .navigationTitle(currentRepository.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    repositoryActionsMenu

                    SRHTShareButton(url: SRHTWebURL.repository(currentRepository), target: .repository) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                RepositorySettingsView(
                    repository: currentRepository,
                    branches: viewModel?.branches ?? [],
                    client: appState.client,
                    onUpdated: { updatedRepository in
                        currentRepository = updatedRepository
                        onRepositoryUpdated?(updatedRepository)
                    },
                    onDeleted: {
                        dismiss()
                        onDeleted?()
                    }
                )
            }
            .sheet(isPresented: $showACLs) {
                NavigationStack {
                    RepositoryACLView(
                        repository: currentRepository,
                        client: appState.client,
                        showsDoneButton: true
                    )
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = RepositoryDetailViewModel(
                        repository: currentRepository,
                        client: appState.client
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func detailContent(_ viewModel: RepositoryDetailViewModel) -> some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(RepositoryDetailViewModel.Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case .summary:
                ReadmeView(viewModel: viewModel)
            case .tree:
                FileTreeView(
                    repository: currentRepository,
                    client: appState.client
                )
            case .log:
                CommitLogView(viewModel: viewModel)
            case .refs:
                ReferencesListView(viewModel: viewModel)
            case .artifacts:
                ArtifactsView(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .srhtErrorBanner(error: Binding(
            get: { viewModel.error },
            set: { viewModel.error = $0 }
        ))
    }

    private func normalizedUsername(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("~") ? String(trimmed.dropFirst()) : trimmed
    }

    private var repositoryActionsMenu: some View {
        Menu {
            if let repositoryURL = SRHTWebURL.repository(currentRepository) {
                Button {
                    openURL(repositoryURL)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }

                Button {
                    appState.copyToPasteboard(repositoryURL.absoluteString, label: "repository URL")
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                }
            }

            if let httpsURL = SRHTWebURL.httpsCloneURL(currentRepository) {
                Button {
                    appState.copyToPasteboard(httpsURL, label: "HTTPS clone URL")
                } label: {
                    Label("Copy HTTPS URL", systemImage: "doc.on.doc")
                }
            }

            Button {
                appState.copyToPasteboard(SRHTWebURL.sshCloneURL(currentRepository), label: "SSH clone URL")
            } label: {
                Label("Copy SSH URL", systemImage: "terminal")
            }

            Button {
                appState.copyToPasteboard(currentRepository.rid, label: "repository RID")
            } label: {
                Label("Copy RID", systemImage: "number")
            }

            if canManageRepository {
                Divider()

                Button {
                    showACLs = true
                } label: {
                    Label("Manage ACLs", systemImage: "person.2")
                }

                Button {
                    showSettings = true
                } label: {
                    Label("Repository Settings", systemImage: "gear")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Repository actions")
    }
}
