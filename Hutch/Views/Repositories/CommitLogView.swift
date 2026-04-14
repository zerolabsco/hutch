import SwiftUI

struct CommitLogView: View {
    let viewModel: RepositoryDetailViewModel

    var body: some View {
        List {
            ForEach(viewModel.commits) { commit in
                NavigationLink(value: commit) {
                    CommitRowView(commit: commit, repository: viewModel.repository)
                }
                .task {
                    await viewModel.loadMoreCommitsIfNeeded(currentItem: commit)
                }
            }
            .themedRow()

            if viewModel.isLoadingMoreCommits {
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
        .overlay {
            if viewModel.isLoadingCommits, viewModel.commits.isEmpty {
                SRHTLoadingStateView(message: "Loading commits…")
            } else if let error = viewModel.error, viewModel.commits.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Commits",
                    message: error,
                    retryAction: { await viewModel.loadCommits() }
                )
            } else if viewModel.commits.isEmpty {
                ContentUnavailableView(
                    "No Commits",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("This repository has no commit history.")
                )
            }
        }
        .task {
            if viewModel.commits.isEmpty {
                await viewModel.loadCommits()
            }
        }
        .refreshable {
            await viewModel.loadCommits()
        }
        .navigationDestination(for: CommitSummary.self) { commit in
            CommitDetailView(
                commitSummary: commit,
                repository: viewModel.repository
            )
        }
    }
}
