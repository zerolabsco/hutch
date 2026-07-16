import SwiftUI
import UniformTypeIdentifiers
import os

#if DEBUG
/// Temporary: diagnosing why the upload menu swallows taps.
private let artifactsLogger = Logger(subsystem: "net.cleberg.Hutch", category: "Artifacts")
#endif

struct ArtifactsView: View {
    let viewModel: RepositoryDetailViewModel
    /// Passed in rather than recomputed: RepositoryDetailView already owns this
    /// check and gates its other management surfaces on it.
    var canManage: Bool = false

    @State private var uploadTargetRef: String?
    @State private var isImporting = false
    @State private var pendingDeletion: ArtifactInfo?
    @State private var downloadedFile: DownloadedArtifact?

    private var isOwnedByCurrentUser: Bool { canManage }

    /// A menu rather than a confirmation dialog: this view already presents one
    /// for delete, and two .confirmationDialog modifiers on the same view leave
    /// one of them silently dead. A menu also puts the tags one tap away.
    @ViewBuilder
    private var uploadMenu: some View {
        Menu {
            if viewModel.tags.isEmpty {
                Text("This repository has no tags")
            } else {
                ForEach(viewModel.tags.prefix(12), id: \.name) { tag in
                    Button(RepositorySummary.displayBranchName(for: tag.name)) {
                        uploadTargetRef = tag.name
                        isImporting = true
                    }
                }
            }
        } label: {
            SwiftUI.Label("Upload Artifact…", systemImage: "square.and.arrow.up")
        }
        // Deliberately not disabled when there are no tags. The explanation for
        // that state lives inside the menu, and disabling the control makes the
        // explanation unreachable — the tap just dies with no reason given.
        .disabled(viewModel.isMutatingArtifact)
    }

    var body: some View {
        @Bindable var vm = viewModel

        return List {
            // In the list rather than the toolbar: this view is a segment inside
            // RepositoryDetailView's tab switch, not its own navigation
            // destination, and a toolbar declared from there does not reliably
            // reach the navigation bar. It also has to be reachable when there are
            // no artifacts at all, which is the state a new tag is in.
            if isOwnedByCurrentUser {
                uploadMenu
                    .themedRow()
            }

            ForEach(viewModel.referenceArtifacts) { refArtifacts in
                Section {
                    ForEach(refArtifacts.artifacts) { artifact in
                        ArtifactRow(artifact: artifact) {
                            Task {
                                // Artifact.url is on the API origin and 401s
                                // without a bearer token, so it cannot be handed
                                // to a browser. Fetch it and share the file.
                                if let fileURL = await viewModel.downloadArtifact(artifact) {
                                    downloadedFile = DownloadedArtifact(url: fileURL)
                                }
                            }
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
                                isImporting = true
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
        // isImporting drives presentation; uploadTargetRef carries the tag. They
        // have to be separate: a binding derived from uploadTargetRef clears it on
        // dismissal, and dismissal happens before the completion runs — so the
        // completion read nil and returned without uploading anything.
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.data]
        ) { result in
            let revspec = uploadTargetRef
            uploadTargetRef = nil
            guard let revspec, case .success(let fileURL) = result else { return }
            Task { await viewModel.uploadArtifact(revspec: revspec, fileURL: fileURL) }
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
        .themedList()
        .listStyle(.insetGrouped)
        .srhtErrorBanner(error: $vm.error)
        .sheet(item: $downloadedFile) { download in
            FileContentShareSheet(activityItems: [download.url])
        }
        .task {
            // Tags drive the picker above and are not otherwise needed by this tab.
            if isOwnedByCurrentUser, viewModel.tags.isEmpty {
                await viewModel.loadReferences()
            }
            #if DEBUG
            // Temporary: diagnosing why the upload menu swallows taps.
            artifactsLogger.debug(
                """
                canManage=\(canManage, privacy: .public) \
                tags=\(viewModel.tags.count, privacy: .public) \
                isMutating=\(viewModel.isMutatingArtifact, privacy: .public) \
                menuDisabled=\(viewModel.isMutatingArtifact || viewModel.tags.isEmpty, privacy: .public) \
                error=\(viewModel.error ?? "nil", privacy: .public)
                """
            )
            #endif
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
                        uploadMenu
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

/// Wraps the downloaded file for `.sheet(item:)`. URL is not Identifiable, and
/// conforming a stdlib type retroactively is worse than a four-line struct.
private struct DownloadedArtifact: Identifiable {
    let id = UUID()
    let url: URL
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
