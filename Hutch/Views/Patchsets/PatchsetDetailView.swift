import SwiftUI

struct PatchsetDetailView: View {
    let patchsetID: Int
    let listName: String?

    @Environment(AppState.self) private var appState
    @State private var viewModel: PatchsetDetailViewModel?
    @State private var showStatusPicker = false

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
                Button("Cancel", role: .cancel) {}
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

    @ViewBuilder
    private func patchesSection(_ patchset: PatchsetDetail) -> some View {
        ForEach(patchset.patches) { patch in
            emailSection(patch, title: patch.seriesLabel.map { "Patch \($0)" } ?? "Patch")
        }
    }

    @ViewBuilder
    private func emailSection(_ email: PatchsetEmail, title: String) -> some View {
        Section(title) {
            VStack(alignment: .leading, spacing: 10) {
                Text(email.subject)
                    .font(.subheadline.weight(.semibold))
                    .textSelection(.enabled)

                ForEach(Array(email.contentBlocks.enumerated()), id: \.offset) { _, block in
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
