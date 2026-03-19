import SwiftUI

struct InboxView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: InboxViewModel?

    var body: some View {
        Group {
            if let viewModel {
                listContent(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading inbox…")
            }
        }
        .navigationTitle("Inbox")
        .task {
            if viewModel == nil {
                let vm = InboxViewModel(client: appState.client)
                viewModel = vm
                await vm.loadThreads()
            }
        }
    }

    @ViewBuilder
    private func listContent(_ viewModel: InboxViewModel) -> some View {
        @Bindable var vm = viewModel

        List {
            ForEach(viewModel.threads) { thread in
                NavigationLink(value: thread) {
                    InboxThreadRow(thread: thread)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.isLoading, viewModel.threads.isEmpty {
                SRHTLoadingStateView(message: "Loading inbox…")
            } else if let error = viewModel.error, viewModel.threads.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Threads",
                    message: error,
                    retryAction: { await viewModel.loadThreads() }
                )
            } else if viewModel.threads.isEmpty, viewModel.error == nil {
                ContentUnavailableView(
                    "No Threads",
                    systemImage: "tray",
                    description: Text("Patch threads will appear here.")
                )
            }
        }
        .connectivityOverlay(hasContent: !viewModel.threads.isEmpty) {
            await viewModel.loadThreads()
        }
        .srhtErrorBanner(error: $vm.error)
        .refreshable {
            await viewModel.loadThreads()
        }
        .navigationDestination(for: InboxThreadSummary.self) { thread in
            ThreadDetailView(thread: thread) {
                viewModel.markThreadRead(thread)
            }
        }
    }
}

private struct InboxThreadRow: View {
    let thread: InboxThreadSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(thread.isUnread ? .blue : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(thread.displaySubject)
                    .font(.subheadline.weight(thread.isUnread ? .semibold : .medium))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if thread.containsPatch {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(thread.metadataLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(thread.lastActivityAt.relativeDescription)
                .font(.caption)
                .foregroundStyle(.tertiary.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
