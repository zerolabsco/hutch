import SwiftUI

struct PasteDetailView: View {
    let paste: Paste
    var onUpdated: ((Paste) -> Void)? = nil
    var onDeleted: ((String) -> Void)? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PasteDetailViewModel?
    @State private var showVisibilitySheet = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading paste…")
            }
        }
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SRHTShareButton(
                    url: currentPaste.flatMap { SRHTWebURL.paste(ownerCanonicalName: $0.user.canonicalName, pasteId: $0.id) },
                    target: .paste
                ) {
                    Image(systemName: "square.and.arrow.up")
                }

                if viewModel != nil {
                    Menu {
                        Button {
                            showVisibilitySheet = true
                        } label: {
                            Label("Change Visibility", systemImage: "eye")
                        }

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Paste", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showVisibilitySheet) {
            if let viewModel, let currentPaste {
                PasteVisibilitySheet(
                    currentVisibility: currentPaste.visibility,
                    isUpdating: viewModel.isUpdatingVisibility
                ) { visibility in
                    if let updated = await viewModel.updateVisibility(visibility) {
                        onUpdated?(updated)
                        showVisibilitySheet = false
                    }
                }
            }
        }
        .alert("Delete Paste?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    if await viewModel?.deletePaste() == true {
                        onDeleted?(paste.id)
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This paste will be permanently removed.")
        }
        .task {
            if viewModel == nil {
                let vm = PasteDetailViewModel(
                    pasteID: paste.id,
                    initialPaste: paste,
                    service: PasteService(client: appState.client)
                )
                viewModel = vm
                await vm.loadPaste()
            }
        }
    }

    private var currentPaste: Paste? {
        viewModel?.paste ?? paste
    }

    private var displayTitle: String {
        if let filename = currentPaste?.files.first?.filename, !filename.isEmpty {
            return filename
        }
        return "Paste \(paste.id)"
    }

    @ViewBuilder
    private func content(_ viewModel: PasteDetailViewModel) -> some View {
        @Bindable var vm = viewModel

        if viewModel.isLoading, viewModel.paste == nil {
            SRHTLoadingStateView(message: "Loading paste…")
        } else if let error = viewModel.error, viewModel.paste == nil {
            SRHTErrorStateView(
                title: "Couldn't Load Paste",
                message: error,
                retryAction: { await viewModel.loadPaste() }
            )
        } else if let paste = viewModel.paste {
            List {
                Section("Details") {
                    LabeledContent("ID", value: paste.id)
                    LabeledContent("Owner", value: paste.user.canonicalName)
                    LabeledContent("Created", value: paste.created.relativeDescription)
                    LabeledContent("Visibility", value: visibilityLabel(paste.visibility))
                    LabeledContent("Files", value: "\(paste.files.count)")
                }

                if paste.files.count > 1 {
                    Section("Files") {
                        Picker("Selected File", selection: Binding(
                            get: { viewModel.selectedFileHash ?? paste.files.first?.hash ?? "" },
                            set: { viewModel.selectFile(hash: $0) }
                        )) {
                            ForEach(paste.files) { file in
                                Text(file.filename ?? String(file.hash.prefix(8)))
                                    .tag(file.hash)
                            }
                        }
                    }
                }

                if let file = viewModel.selectedFile {
                    Section("Current File") {
                        if let filename = file.filename, !filename.isEmpty {
                            LabeledContent("Filename", value: filename)
                        }
                        LabeledContent("Hash", value: file.hash)
                    }

                    Section {
                        if viewModel.loadingFileHashes.contains(file.hash) && viewModel.selectedFileContents == nil {
                            SRHTLoadingStateView(message: "Loading paste contents…")
                                .frame(minHeight: 180)
                        } else if let contents = viewModel.selectedFileContents {
                            PasteCodeBlock(text: contents)
                        } else {
                            Text("This file’s contents are unavailable.")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Contents")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .srhtErrorBanner(error: $vm.error)
            .refreshable {
                await viewModel.loadPaste()
            }
        }
    }

    private func visibilityLabel(_ visibility: Visibility) -> String {
        switch visibility {
        case .public:
            return "Public"
        case .unlisted:
            return "Unlisted"
        case .private:
            return "Private"
        }
    }
}

private struct PasteCodeBlock: View {
    let text: String

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            Text(text.isEmpty ? " " : text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
        .frame(minHeight: 220)
    }
}

private struct PasteVisibilitySheet: View {
    let currentVisibility: Visibility
    let isUpdating: Bool
    let onSave: (Visibility) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var visibility: Visibility

    init(currentVisibility: Visibility, isUpdating: Bool, onSave: @escaping (Visibility) async -> Void) {
        self.currentVisibility = currentVisibility
        self.isUpdating = isUpdating
        self.onSave = onSave
        _visibility = State(initialValue: currentVisibility)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibilityOptions, id: \.self) { option in
                    Button {
                        visibility = option
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(for: option))
                                    .foregroundStyle(.primary)
                                Text(description(for: option))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if visibility == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Visibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await onSave(visibility)
                        }
                    }
                    .disabled(isUpdating || visibility == currentVisibility)
                }
            }
            .overlay {
                if isUpdating {
                    ProgressView()
                }
            }
        }
    }

    private var visibilityOptions: [Visibility] {
        [.public, .unlisted, .private]
    }

    private func title(for visibility: Visibility) -> String {
        switch visibility {
        case .public:
            "Public"
        case .unlisted:
            "Unlisted"
        case .private:
            "Private"
        }
    }

    private func description(for visibility: Visibility) -> String {
        switch visibility {
        case .public:
            "Visible to everyone and listed on your profile."
        case .unlisted:
            "Visible to anyone with the URL, but not listed on your profile."
        case .private:
            "Visible only to explicitly allowed viewers."
        }
    }
}
