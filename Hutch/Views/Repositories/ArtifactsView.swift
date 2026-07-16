import SwiftUI
import UniformTypeIdentifiers

struct ArtifactsView: View {
    let viewModel: RepositoryDetailViewModel
    /// Passed in rather than recomputed: RepositoryDetailView already owns this
    /// check and gates its other management surfaces on it.
    var canManage: Bool = false
    @Environment(\.openURL) private var openURL

    @State private var uploadTargetRef: String?
    @State private var pendingDeletion: ArtifactInfo?
    @State private var showTagPicker = false

    private var isOwnedByCurrentUser: Bool { canManage }

    var body: some View {
        List {
            // In the list rather than the toolbar: this view is a segment inside
            // RepositoryDetailView's tab switch, not its own navigation
            // destination, and a toolbar declared from there does not reliably
            // reach the navigation bar. It also has to be reachable when there are
            // no artifacts at all, which is the state a new tag is in.
            if isOwnedByCurrentUser {
                Button {
                    showTagPicker = true
                } label: {
                    SwiftUI.Label("Upload Artifact…", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.isMutatingArtifact || viewModel.tags.isEmpty)
                .themedRow()
            }

            ForEach(viewModel.referenceArtifacts) { refArtifacts in
                Section {
                    ForEach(refArtifacts.artifacts) { artifact in
                        ArtifactRow(artifact: artifact) {
                            openURL(artifact.url)
                        }
                        // See MailingListListView: a full-swipe destructive
                        // action animates the row out before the confirmation.
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isOwnedByCurrentUser {
                                Button {
                                    pendingDeletion = artifact
                                } label: {
                                    SwiftUI.Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                        }
                    }
                    .themedRow()
                } header: {
                    HStack {
                        Text(refArtifacts.name)
                        if isOwnedByCurrentUser {
                            Spacer()
                            // Upload targets a specific tag, so the control belongs
                            // on the tag rather than in the toolbar.
                            Button {
                                uploadTargetRef = refArtifacts.name
                            } label: {
                                SwiftUI.Label("Upload", systemImage: "plus.circle")
                                    .font(.caption)
                            }
                            .disabled(viewModel.isMutatingArtifact)
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: .init(
                get: { uploadTargetRef != nil },
                set: { if !$0 { uploadTargetRef = nil } }
            ),
            allowedContentTypes: [.data]
        ) { result in
            guard let revspec = uploadTargetRef else { return }
            uploadTargetRef = nil
            if case .success(let fileURL) = result {
                Task { await viewModel.uploadArtifact(revspec: revspec, fileURL: fileURL) }
            }
        }
        .confirmationDialog(
            pendingDeletion.map { "Delete \($0.filename)?" } ?? "",
            isPresented: .init(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { artifact in
            Button("Delete Artifact", role: .destructive) {
                Task { await viewModel.deleteArtifact(id: artifact.id) }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text("This permanently removes the artifact from the tag. This cannot be undone.")
        }
        .confirmationDialog("Upload to Tag", isPresented: $showTagPicker, titleVisibility: .visible) {
            ForEach(viewModel.tags.prefix(12), id: \.name) { tag in
                Button(RepositorySummary.displayBranchName(for: tag.name)) {
                    uploadTargetRef = tag.name
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Artifacts attach to a tag. Filenames must be unique within the repository.")
        }
        .themedList()
        .listStyle(.insetGrouped)
        .task {
            // Tags drive the picker above and are not otherwise needed by this tab.
            if isOwnedByCurrentUser, viewModel.tags.isEmpty {
                await viewModel.loadReferences()
            }
        }
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
                // The overlay covers the whole list, so the upload row above is
                // hidden underneath it — and a repository with no artifacts is
                // exactly the one that needs uploading. Offer it here too.
                ContentUnavailableView {
                    SwiftUI.Label("No Artifacts", systemImage: "archivebox")
                } description: {
                    Text("This repository has no release artifacts.")
                } actions: {
                    if isOwnedByCurrentUser {
                        Button("Upload Artifact…") {
                            showTagPicker = true
                        }
                        .disabled(viewModel.isMutatingArtifact || viewModel.tags.isEmpty)
                    }
                }
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
