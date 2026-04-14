import SwiftUI

struct ArtifactsView: View {
    let viewModel: RepositoryDetailViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            ForEach(viewModel.referenceArtifacts) { refArtifacts in
                Section(refArtifacts.name) {
                    ForEach(refArtifacts.artifacts) { artifact in
                        ArtifactRow(artifact: artifact) {
                            openURL(artifact.url)
                        }
                    }
                    .themedRow()
                }
            }
        }
        .themedList()
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.isLoadingArtifacts, viewModel.referenceArtifacts.isEmpty {
                SRHTLoadingStateView(message: "Loading artifacts…")
            } else if let error = viewModel.error, viewModel.referenceArtifacts.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Artifacts",
                    message: error,
                    retryAction: { await viewModel.loadArtifacts() }
                )
            } else if viewModel.referenceArtifacts.isEmpty {
                ContentUnavailableView(
                    "No Artifacts",
                    systemImage: "archivebox",
                    description: Text("This repository has no release artifacts.")
                )
            }
        }
        .task {
            if viewModel.referenceArtifacts.isEmpty {
                await viewModel.loadArtifacts()
            }
        }
        .refreshable {
            await viewModel.loadArtifacts()
        }
    }
}

private struct ArtifactRow: View {
    let artifact: ArtifactInfo
    let onDownload: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(artifact.filename)
                    .font(.subheadline)

                Text(artifact.size.formattedByteCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onDownload()
            } label: {
                Image(systemName: "arrow.down.circle")
                    .imageScale(.large)
            }
        }
    }
}
