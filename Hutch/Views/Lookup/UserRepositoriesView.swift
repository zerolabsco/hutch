import SwiftUI

struct UserRepositoriesView: View {
    let viewModel: UserProfileViewModel

    var body: some View {
        List {
            ForEach(viewModel.repositories) { repo in
                NavigationLink {
                    RepositoryDetailView(repository: repo) { updatedRepository in
                        viewModel.updateRepository(updatedRepository)
                    }
                } label: {
                    RepositoryRowView(repository: repo, buildStatus: .none)
                }
            }
            .themedRow()
        }
        .themedList()
        .listStyle(.plain)
        .navigationTitle("Repositories")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isLoadingRepositories && viewModel.repositories.isEmpty {
                SRHTLoadingStateView(message: "Loading repositories…")
            }
        }
        .refreshable {
            await viewModel.loadRepositories()
        }
    }
}
