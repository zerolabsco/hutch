import SwiftUI

struct InboxView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: InboxViewModel?
    @State private var selectedThreadID: InboxThreadSummary.ID?
    @State private var selectedThreadSnapshot: InboxThreadSummary?
    @State private var isShowingThreadDetail = false

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
            ForEach(viewModel.filteredThreads) { thread in
                Button {
                    selectThread(thread)
                } label: {
                    InboxThreadRow(thread: thread)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    readStateAction(for: thread, in: viewModel)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    readStateAction(for: thread, in: viewModel)
                }
            }
        }
        .searchable(
            text: $vm.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search inbox"
        )
        .listStyle(.plain)
        .overlay {
            if viewModel.isLoading, viewModel.threads.isEmpty {
                SRHTLoadingStateView(message: "Loading inbox…")
            } else if let error = viewModel.error, viewModel.threads.isEmpty {
                SRHTErrorStateView(
                    title: "Failed to load inbox",
                    message: error,
                    retryAction: { await viewModel.loadThreads() }
                )
            } else if !viewModel.threads.isEmpty, viewModel.filteredThreads.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else if viewModel.threads.isEmpty, viewModel.error == nil {
                ContentUnavailableView(
                    "Inbox Zero",
                    systemImage: "tray",
                    description: Text("Unread threads will appear here.")
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
        .onChange(of: viewModel.threads) { _, threads in
            syncSelectedThreadSnapshot(with: threads)
        }
        .navigationDestination(isPresented: Binding(
            get: { isShowingThreadDetail && selectedThread(for: viewModel) != nil },
            set: { isPresented in
                if !isPresented {
                    clearSelection()
                }
                isShowingThreadDetail = isPresented
            }
        )) {
            if let thread = selectedThread(for: viewModel) {
                ThreadDetailView(thread: thread) {
                    viewModel.markThreadRead(thread)
                }
                .onAppear {
                    cacheSelectedThread(thread)
                }
                .onDisappear {
                    handleThreadDetailDisappear(for: thread.id)
                }
            } else {
                ContentUnavailableView(
                    "Thread Unavailable",
                    systemImage: "tray",
                    description: Text("This thread could not be restored.")
                )
            }
        }
    }

    @ViewBuilder
    private func readStateAction(for thread: InboxThreadSummary, in viewModel: InboxViewModel) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.markThreadRead(thread)
            }
        } label: {
            Label("Mark as Read", systemImage: "envelope.open")
        }
        .tint(.blue)
    }

    private func selectThread(_ thread: InboxThreadSummary) {
        cacheSelectedThread(thread)
        isShowingThreadDetail = true
    }

    private func cacheSelectedThread(_ thread: InboxThreadSummary) {
        selectedThreadID = thread.id
        selectedThreadSnapshot = thread
    }

    private func selectedThread(for viewModel: InboxViewModel) -> InboxThreadSummary? {
        guard let selectedThreadID else { return selectedThreadSnapshot }
        return viewModel.thread(withID: selectedThreadID) ?? (selectedThreadSnapshot?.id == selectedThreadID ? selectedThreadSnapshot : nil)
    }

    private func handleThreadDetailDisappear(for threadID: String) {
        let isActiveSelection = selectedThreadID == threadID
        guard isActiveSelection else { return }
        clearSelection()
    }

    private func syncSelectedThreadSnapshot(with threads: [InboxThreadSummary]) {
        guard let selectedThreadID else { return }
        guard let updatedThread = threads.first(where: { $0.id == selectedThreadID }) else { return }
        selectedThreadSnapshot = updatedThread
    }

    private func clearSelection() {
        selectedThreadID = nil
        selectedThreadSnapshot = nil
        isShowingThreadDetail = false
    }
}

struct InboxThreadRow: View {
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
