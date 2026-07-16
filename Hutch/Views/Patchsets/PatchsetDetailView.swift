import SwiftUI

struct PatchsetDetailView: View {
    let patchsetID: Int
    let listName: String?

    @Environment(AppState.self) private var appState
    @State private var viewModel: PatchsetDetailViewModel?
    @State private var showStatusPicker = false
    @State private var expandedPatchIDs: Set<Int> = []

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading Patchset…")
            }
        }
        .navigationTitle("Patchset")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let viewModel, viewModel.patchset != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    actionsMenu(viewModel)
                }
            }
        }
        .task {
            let model = viewModel ?? PatchsetDetailViewModel(patchsetID: patchsetID, client: appState.client)
            viewModel = model
            await model.loadPatchset()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: PatchsetDetailViewModel) -> some View {
        if viewModel.isLoading && viewModel.patchset == nil {
            SRHTLoadingStateView(message: "Loading Patchset…")
        } else if let patchset = viewModel.patchset {
            List {
                headerSection(patchset)
                if let coverLetter = patchset.coverLetter {
                    emailSection(coverLetter, title: "Cover Letter")
                }
                if !patchset.tools.isEmpty {
                    toolsSection(patchset)
                }
                patchesSection(patchset)
            }
            .themedList()
            // Inset grouped lays cells out at a rounded width while the content
            // measures itself at the unrounded one, so a long Text reflows to a
            // different height than the cell was sized for and the two chase each
            // other into a layout loop. ThreadDetailView renders the same bodies
            // through the same DiffView on a plain list without that fight.
            .listStyle(.plain)
            .refreshable { await viewModel.loadPatchset() }
            .overlay {
                if viewModel.isUpdatingStatus {
                    ProgressView()
                }
            }
            .confirmationDialog(
                "Set Status",
                isPresented: $showStatusPicker,
                titleVisibility: .visible
            ) {
                ForEach(PatchsetStatus.assignable, id: \.self) { status in
                    Button(status.displayName) {
                        Task { await viewModel.updateStatus(to: status) }
                    }
                }
                Button("Cancel", role: .cancel) {} // dismisses the dialog; no action needed
            }
            .alert(
                "Couldn't Update Patchset",
                isPresented: .init(
                    get: { viewModel.error != nil },
                    set: { if !$0 { viewModel.error = nil } }
                )
            ) {
                Button("OK", role: .cancel) { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
        } else if let error = viewModel.error {
            SRHTErrorStateView(
                title: "Couldn't Load Patchset",
                message: error,
                retryAction: { await viewModel.loadPatchset() }
            )
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func headerSection(_ patchset: PatchsetDetail) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(patchset.subject)
                    .font(.headline)

                HStack(spacing: 8) {
                    PatchsetStatusBadge(status: patchset.status)
                    if patchset.version > 1 {
                        Text("v\(patchset.version)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("\(patchset.patches.count) patch\(patchset.patches.count == 1 ? "" : "es")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(patchset.submitter.canonicalName) • \(patchset.updated.relativeDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let listName {
                    Text(listName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .themedRow()

            // The version chain matters during review: a superseded series should
            // usually be read at its newest version instead.
            //
            // Pushed directly rather than by value, for the same reason as the rows
            // that lead here — this view inherits whatever stack presented it, and
            // not all of them declare a MoreRoute destination.
            if let supersededBy = patchset.supersededBy {
                NavigationLink {
                    PatchsetDetailView(patchsetID: supersededBy, listName: listName)
                } label: {
                    SwiftUI.Label("Superseded by a newer version", systemImage: "arrow.right.circle")
                        .font(.subheadline)
                }
                .themedRow()
            }

            if let supersedes = patchset.supersedes {
                NavigationLink {
                    PatchsetDetailView(patchsetID: supersedes, listName: listName)
                } label: {
                    SwiftUI.Label("Revises an earlier version", systemImage: "arrow.left.circle")
                        .font(.subheadline)
                }
                .themedRow()
            }
        }
    }

    @ViewBuilder
    private func toolsSection(_ patchset: PatchsetDetail) -> some View {
        Section("Checks") {
            ForEach(patchset.tools) { tool in
                HStack(spacing: 8) {
                    Image(systemName: tool.icon.systemImage)
                        .foregroundStyle(tool.icon == .failed ? .red : .secondary)
                    Text(tool.details)
                        .font(.subheadline)
                }
                .themedRow()
            }
        }
    }

    /// Patches start collapsed.
    ///
    /// A diff is tall, and a series is many of them. Rendering every patch expanded
    /// puts a dozen self-sizing diffs in one List, which drives UICollectionView
    /// into a recursive layout loop and wedges the app. The inbox thread view
    /// collapses all but the last message for the same reason.
    @ViewBuilder
    private func patchesSection(_ patchset: PatchsetDetail) -> some View {
        Section("Patches") {
            ForEach(patchset.patches) { patch in
                PatchRow(
                    patch: patch,
                    isExpanded: expandedPatchIDs.contains(patch.id),
                    onToggle: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedPatchIDs.contains(patch.id) {
                                expandedPatchIDs.remove(patch.id)
                            } else {
                                expandedPatchIDs.insert(patch.id)
                            }
                        }
                    }
                )
                .themedRow()
            }
        }
    }

    @ViewBuilder
    private func emailSection(_ email: PatchsetEmail, title: String) -> some View {
        Section(title) {
            VStack(alignment: .leading, spacing: 10) {
                Text(email.subject)
                    .font(.subheadline.weight(.semibold))
                    .textSelection(.enabled)

                PatchsetContentBlocks(blocks: email.contentBlocks)
            }
            .padding(.vertical, 4)
            .themedRow()
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionsMenu(_ viewModel: PatchsetDetailViewModel) -> some View {
        Menu {
            Button {
                showStatusPicker = true
            } label: {
                SwiftUI.Label("Set Status", systemImage: "flag")
            }
            .disabled(viewModel.isUpdatingStatus)

            if let mbox = viewModel.patchset?.mbox {
                Divider()
                ShareLink(item: mbox) {
                    SwiftUI.Label("Share mbox", systemImage: "square.and.arrow.up")
                }
                Button {
                    appState.copyToPasteboard(mbox.absoluteString, label: "mbox URL")
                } label: {
                    SwiftUI.Label("Copy mbox URL", systemImage: "doc.on.doc")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Patchset actions")
    }
}

// MARK: - Patch Row

private struct PatchRow: View {
    let patch: PatchsetEmail
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(patch.subject)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let seriesLabel = patch.seriesLabel {
                            Text(seriesLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Collapses this patch" : "Expands this patch")

            if isExpanded {
                PatchsetContentBlocks(blocks: patch.contentBlocks)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Content Blocks

private struct PatchsetContentBlocks: View {
    let blocks: [InboxMessageContentBlock]

    var body: some View {
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
            switch block {
            case .plainText(let text):
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            case .diff(let diff):
                DiffView(diff: diff)
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - Status Badge

struct PatchsetStatusBadge: View {
    let status: PatchsetStatus

    var body: some View {
        SwiftUI.Label(status.displayName, systemImage: status.systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var foreground: Color {
        switch status {
        case .applied, .approved: .green
        case .rejected: .red
        case .needsRevision: .orange
        case .superseded, .unknown, .proposed: .secondary
        }
    }

    private var background: Color {
        foreground.opacity(0.12)
    }
}
