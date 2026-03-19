import SwiftUI

struct PasteListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: PasteListViewModel?
    @State private var showCreatePasteSheet = false
    @State private var createdPaste: Paste?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading pastes…")
            }
        }
        .navigationTitle("Pastes")
        .toolbar {
            if viewModel != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreatePasteSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showCreatePasteSheet) {
            if let viewModel {
                CreatePasteSheet(viewModel: viewModel) { paste in
                    showCreatePasteSheet = false
                    createdPaste = paste
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { createdPaste != nil },
            set: { isPresented in
                if !isPresented {
                    createdPaste = nil
                }
            }
        )) {
            if let createdPaste {
                PasteDetailView(
                    paste: createdPaste,
                    onUpdated: { updated in
                        viewModel?.upsertPaste(updated)
                    },
                    onDeleted: { id in
                        viewModel?.removePaste(id: id)
                    }
                )
            }
        }
        .task {
            if viewModel == nil {
                let vm = PasteListViewModel(service: PasteService(client: appState.client))
                viewModel = vm
                await vm.loadPastes()
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: PasteListViewModel) -> some View {
        @Bindable var vm = viewModel

        List {
            ForEach(viewModel.pastes) { paste in
                NavigationLink(value: paste) {
                    PasteRowView(paste: paste)
                }
                .task {
                    await viewModel.loadMoreIfNeeded(currentItem: paste)
                }
            }

            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.isLoading, viewModel.pastes.isEmpty {
                SRHTLoadingStateView(message: "Loading pastes…")
            } else if let error = viewModel.error, viewModel.pastes.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Pastes",
                    message: error,
                    retryAction: { await viewModel.loadPastes() }
                )
            } else if viewModel.pastes.isEmpty {
                ContentUnavailableView(
                    "No Pastes",
                    systemImage: "doc.on.clipboard",
                    description: Text("Your pastes will appear here.")
                )
            }
        }
        .connectivityOverlay(hasContent: !viewModel.pastes.isEmpty) {
            await viewModel.loadPastes()
        }
        .srhtErrorBanner(error: $vm.error)
        .refreshable {
            await viewModel.loadPastes()
        }
        .navigationDestination(for: Paste.self) { paste in
            PasteDetailView(
                paste: paste,
                onUpdated: { updated in
                    viewModel.upsertPaste(updated)
                },
                onDeleted: { id in
                    viewModel.removePaste(id: id)
                }
            )
        }
    }
}

private struct PasteRowView: View {
    let paste: Paste

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(primaryTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(secondaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    VisibilityBadge(visibility: paste.visibility)
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(paste.created.relativeDescription)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption2)
            }
        }
        .padding(.vertical, 2)
    }

    private var primaryTitle: String {
        if let filename = paste.files.first?.filename, !filename.isEmpty {
            return filename
        }
        return paste.files.count > 1 ? "Untitled Paste (\(paste.files.count) files)" : "Untitled Paste"
    }

    private var secondaryLine: String {
        var parts: [String] = [paste.user.canonicalName]
        if paste.files.count > 1 {
            parts.append("\(paste.files.count) files")
        } else {
            parts.append("1 file")
        }
        if let firstHash = paste.files.first?.hash {
            parts.append(String(firstHash.prefix(8)))
        }
        return parts.joined(separator: " • ")
    }
}

private struct CreatePasteSheet: View {
    let viewModel: PasteListViewModel
    let onCreated: (Paste) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var files = [PasteUploadDraft()]
    @State private var visibility: Visibility = .unlisted

    var body: some View {
        NavigationStack {
            Form {
                Section("Files") {
                    ForEach($files) { $file in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Filename (optional)", text: $file.filename)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)

                            ZStack(alignment: .topLeading) {
                                if file.contents.isEmpty {
                                    Text("Paste contents")
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                        .allowsHitTesting(false)
                                }

                                TextEditor(text: $file.contents)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minHeight: 180)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        files.remove(atOffsets: offsets)
                        if files.isEmpty {
                            files = [PasteUploadDraft()]
                        }
                    }

                    Button {
                        files.append(PasteUploadDraft())
                    } label: {
                        Label("Add File", systemImage: "plus")
                    }
                }

                Section("Visibility") {
                    Picker("Visibility", selection: $visibility) {
                        Text("Public").tag(Visibility.public)
                        Text("Unlisted").tag(Visibility.unlisted)
                        Text("Private").tag(Visibility.private)
                    }
                }

                Section {
                    Text("Paste contents are uploaded as UTF-8 text files. Hutch can change visibility later, but the API does not support editing file contents after creation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Paste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let paste = await viewModel.createPaste(files: files, visibility: visibility) {
                                onCreated(paste)
                            }
                        }
                    } label: {
                        if viewModel.isCreatingPaste {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Create Paste")
                        }
                    }
                    .disabled(!hasValidContent || viewModel.isCreatingPaste)
                }
            }
        }
    }

    private var hasValidContent: Bool {
        files.contains { !$0.contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
