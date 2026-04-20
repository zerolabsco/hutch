import SwiftUI

struct ReferencesListView: View {
    let viewModel: RepositoryDetailViewModel

    var body: some View {
        List {
            if let defaultBranch = viewModel.defaultBranchReference {
                Section {
                    ReferenceRow(reference: defaultBranch, prefix: "refs/heads/")
                        .themedRow()

                    NavigationLink("See All Branches") {
                        ReferencesDetailListView(
                            title: "Branches",
                            references: viewModel.branches,
                            prefix: "refs/heads/"
                        )
                    }
                    .themedRow()
                } header: {
                    sectionHeader(title: "Default Branch")
                }
            }

            if let latestTag = viewModel.latestTagReference {
                Section {
                    ReferenceRow(reference: latestTag, prefix: "refs/tags/")
                        .themedRow()

                    NavigationLink("See All Tags") {
                        ReferencesDetailListView(
                            title: "Tags",
                            references: viewModel.tags,
                            prefix: "refs/tags/"
                        )
                    }
                    .themedRow()
                } header: {
                    sectionHeader(title: "Latest Tag")
                }
            }
        }
        .themedList()
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

    @ViewBuilder
    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
        }
    }
}

private struct ReferencesDetailListView: View {
    let title: String
    let references: [ReferenceDetail]
    let prefix: String

    var body: some View {
        List {
            ForEach(references, id: \.name) { reference in
                ReferenceRow(reference: reference, prefix: prefix)
                    .themedRow()
            }
        }
        .themedList()
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .overlay {
            if references.isEmpty {
                ContentUnavailableView(
                    "No \(title)",
                    systemImage: prefix.contains("tags") ? "tag" : "arrow.triangle.branch",
                    description: Text("This repository does not have any \(title.lowercased()).")
                )
            }
        }
    }
}

private struct ReferenceRow: View {
    let reference: ReferenceDetail
    let prefix: String

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shortName)
                        .font(.body.monospaced())
                    if let date = reference.date {
                        Text(date.relativeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
            }

            Spacer()

            Text(String((reference.target ?? "").prefix(8)))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
