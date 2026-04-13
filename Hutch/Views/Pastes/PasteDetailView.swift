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
    @State private var showInfoSheet = false
    @State private var showFileShareSheet = false
    @State private var showShareUnavailableAlert = false
    @State private var didCopyContents = false
    @State private var copyResetTask: Task<Void, Never>?
    @AppStorage(AppStorageKeys.wrapPasteFileLines) private var wrapLines = false

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
                if viewModel != nil {
                    Menu {
                        if let url = currentPaste.flatMap({ SRHTWebURL.paste(ownerCanonicalName: $0.user.canonicalName, pasteId: $0.id) }) {
                            ShareLink(item: url) {
                                Label("Share Link", systemImage: "link")
                            }
                        }

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
            Button("Cancel", role: .cancel) {
                // Alert dismissal is implicit; no additional action required.
            }
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
            VStack(spacing: 0) {
                fileHeaderBar(paste: paste, viewModel: viewModel)
                Divider()
                fileContentArea(viewModel: viewModel)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionToolbar(viewModel: viewModel)
            }
            .srhtErrorBanner(error: $vm.error)
            .sheet(isPresented: $showInfoSheet) {
                PasteInfoSheet(paste: paste, selectedFile: viewModel.selectedFile)
            }
            .sheet(isPresented: $showFileShareSheet) {
                if let contents = viewModel.selectedFileContents {
                    FileContentShareSheet(activityItems: [contents])
                }
            }
            .alert("Share Unavailable", isPresented: $showShareUnavailableAlert) {
                Button("OK", role: .cancel) {
                    // Alert dismissal is implicit; no additional action required.
                }
            } message: {
                Text(SRHTShareTarget.file.fallbackMessage)
            }
        }
    }

    // MARK: - File Header Bar

    private func fileHeaderBar(paste: Paste, viewModel: PasteDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                let filename = viewModel.selectedFile.flatMap { $0.filename.flatMap { $0.isEmpty ? nil : $0 } }
                Text(filename ?? "Untitled")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                VisibilityBadge(visibility: paste.visibility)
            }

            HStack(spacing: 4) {
                Text(paste.user.canonicalName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(paste.created.relativeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let hash = viewModel.selectedFile?.hash {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(hash.prefix(8))
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }

            if paste.files.count > 1 {
                Picker(
                    "File",
                    selection: Binding(
                        get: { viewModel.selectedFileHash ?? paste.files.first?.hash ?? "" },
                        set: { viewModel.selectFile(hash: $0) }
                    )
                ) {
                    ForEach(paste.files) { file in
                        Text(file.filename ?? String(file.hash.prefix(8)))
                            .tag(file.hash)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - File Content Area

    @ViewBuilder
    private func fileContentArea(viewModel: PasteDetailViewModel) -> some View {
        if let file = viewModel.selectedFile {
            if viewModel.loadingFileHashes.contains(file.hash) && viewModel.selectedFileContents == nil {
                SRHTLoadingStateView(message: "Loading contents…")
            } else if let contents = viewModel.selectedFileContents {
                CodeFileTextView(
                    text: contents,
                    fileName: file.filename ?? "",
                    wrapLines: wrapLines
                )
            } else {
                ContentUnavailableView(
                    "Contents Unavailable",
                    systemImage: "doc.questionmark",
                    description: Text("This file's contents could not be loaded.")
                )
            }
        } else {
            ContentUnavailableView(
                "No File Selected",
                systemImage: "doc",
                description: Text("Select a file to view its contents.")
            )
        }
    }

    // MARK: - Action Toolbar

    private func actionToolbar(viewModel: PasteDetailViewModel) -> some View {
        HStack(spacing: 0) {
            toolbarButton(
                title: didCopyContents ? "Copied" : "Copy All",
                systemImage: didCopyContents ? "checkmark" : "doc.on.doc"
            ) {
                if let contents = viewModel.selectedFileContents {
                    UIPasteboard.general.string = contents
                    didCopyContents = true
                    copyResetTask?.cancel()
                    copyResetTask = Task {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        await MainActor.run { didCopyContents = false }
                    }
                }
            }
            .disabled(viewModel.selectedFileContents == nil)

            toolbarButton(
                title: "Share",
                systemImage: "square.and.arrow.up"
            ) {
                if let contents = viewModel.selectedFileContents, !contents.isEmpty {
                    showFileShareSheet = true
                } else {
                    showShareUnavailableAlert = true
                }
            }
            .disabled(viewModel.selectedFileContents == nil)

            toolbarButton(
                title: wrapLines ? "Wrap On" : "Wrap Off",
                systemImage: "text.word.spacing"
            ) {
                wrapLines.toggle()
            }

            toolbarButton(
                title: "Details",
                systemImage: "info.circle"
            ) {
                showInfoSheet = true
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

// MARK: - Paste Info Sheet

private struct PasteInfoSheet: View {
    let paste: Paste
    let selectedFile: PasteFile?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Paste") {
                    LabeledContent("ID", value: paste.id)
                    LabeledContent("Owner", value: paste.user.canonicalName)
                    LabeledContent("Created", value: paste.created.relativeDescription)
                    LabeledContent("Visibility") {
                        VisibilityBadge(visibility: paste.visibility)
                    }
                    if paste.files.count > 1 {
                        LabeledContent("Files", value: "\(paste.files.count)")
                    }
                }

                if let file = selectedFile {
                    Section("File") {
                        if let filename = file.filename, !filename.isEmpty {
                            LabeledContent("Filename", value: filename)
                        }
                        LabeledContent("Hash") {
                            Text(file.hash)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .themedList()
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Visibility Sheet

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
            .themedList()
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
