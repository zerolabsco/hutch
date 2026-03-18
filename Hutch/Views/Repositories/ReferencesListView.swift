import SwiftUI

struct ReferencesListView: View {
    let viewModel: RepositoryDetailViewModel

    var body: some View {
        List {
            if !viewModel.branches.isEmpty {
                Section("Branches") {
                    ForEach(viewModel.branches, id: \.name) { ref in
                        ReferenceRow(reference: ref, prefix: "refs/heads/")
                    }
                }
            }

            if !viewModel.tags.isEmpty {
                Section("Tags") {
                    ForEach(viewModel.tags, id: \.name) { ref in
                        ReferenceRow(reference: ref, prefix: "refs/tags/")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.isLoadingRefs, viewModel.branches.isEmpty, viewModel.tags.isEmpty {
                SRHTLoadingStateView(message: "Loading references…")
            } else if let error = viewModel.error, viewModel.branches.isEmpty, viewModel.tags.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load References",
                    message: error,
                    retryAction: { await viewModel.loadReferences() }
                )
            } else if viewModel.branches.isEmpty, viewModel.tags.isEmpty {
                ContentUnavailableView(
                    "No References",
                    systemImage: "arrow.triangle.branch",
                    description: Text("This repository has no branches or tags.")
                )
            }
        }
        .task {
            if viewModel.branches.isEmpty, viewModel.tags.isEmpty {
                await viewModel.loadReferences()
            }
        }
        .refreshable {
            await viewModel.loadReferences()
        }
    }
}

private struct ReferenceRow: View {
    let reference: Reference
    let prefix: String

    var body: some View {
        HStack {
            Label {
                Text(shortName)
                    .font(.body.monospaced())
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
            }

            Spacer()

            Text(String((reference.target ?? "").prefix(8)))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var shortName: String {
        if reference.name.hasPrefix(prefix) {
            String(reference.name.dropFirst(prefix.count))
        } else {
            reference.name
        }
    }

    private var icon: String {
        prefix.contains("tags") ? "tag" : "arrow.triangle.branch"
    }

    private var iconColor: Color {
        prefix.contains("tags") ? .orange : .blue
    }
}
