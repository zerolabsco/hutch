import SwiftUI

struct RepositoryDetailView: View {
    var repository: RepositorySummary
    var onDeleted: (() -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RepositoryDetailViewModel?
    @State private var selectedTab: RepositoryDetailViewModel.Tab = .summary
    @State private var showSettings = false
    @State private var displayName: String

    init(repository: RepositorySummary, onDeleted: (() -> Void)? = nil) {
        self.repository = repository
        self.onDeleted = onDeleted
        self._displayName = State(initialValue: repository.name)
    }

    var body: some View {
        if repository.service == .hg {
            HgRepositoryDetailView(repository: repository, onDeleted: onDeleted)
        } else {
            Group {
                if let viewModel {
                    detailContent(viewModel)
                } else {
                    SRHTLoadingStateView(message: "Loading repository…")
                }
            }
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    SRHTShareButton(url: SRHTWebURL.repository(repository), target: .repository) {
                        Image(systemName: "square.and.arrow.up")
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                RepositorySettingsView(
                    repository: repository,
                    branches: viewModel?.branches ?? [],
                    client: appState.client,
                    onRenamed: { newName in
                        displayName = newName
                    },
                    onDeleted: {
                        dismiss()
                        onDeleted?()
                    }
                )
            }
            .task {
                if viewModel == nil {
                    viewModel = RepositoryDetailViewModel(
                        repository: repository,
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
                    repository: repository,
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
}
