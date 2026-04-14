import SwiftUI

struct RepositoryACLView: View {
    let repository: RepositorySummary
    let client: SRHTClient
    let showsDoneButton: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.isAMOLEDTheme) private var isAMOLED
    @State private var viewModel: RepositoryACLViewModel?
    @State private var pendingDeletion: RepositoryACLEntry?
    @State private var showAddSheet = false

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading access…")
            }
        }
        .navigationTitle("Access")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }

            if viewModel != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add User")
                }
            }
        }
        .task {
            if viewModel == nil {
                let service = RepositoryACLService(client: client, service: repository.service)
                let vm = RepositoryACLViewModel(repository: repository, service: service)
                viewModel = vm
                await vm.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: RepositoryACLViewModel) -> some View {
        Group {
            if viewModel.isLoading && !viewModel.hasEntries && viewModel.loadError == nil {
                SRHTLoadingStateView(message: "Loading access…")
            } else if let loadError = viewModel.loadError, !viewModel.hasEntries {
                SRHTErrorStateView(
                    title: "Couldn't Load Access",
                    message: loadError,
                    retryAction: { await viewModel.load() }
                )
            } else {
                List {
                    if viewModel.visibleEntries.isEmpty {
                        ContentUnavailableView {
                            Label("No Additional Access", systemImage: "person.2.slash")
                        } description: {
                            Text("Only the repository owner currently has access.")
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(isAMOLED ? Color.black : Color.clear)
                    } else {
                        Section {
                            ForEach(viewModel.visibleEntries) { entry in
                                RepositoryACLEntryRow(
                                    entry: entry,
                                    isUpdating: viewModel.isUpdating(entry),
                                    isDeleting: viewModel.isDeleting(entry),
                                    onSelectMode: { mode in
                                        Task { await viewModel.updatePermission(for: entry, to: mode) }
                                    },
                                    onDelete: {
                                        pendingDeletion = entry
                                    }
                                )
                            }
                            .themedRow()
                        }
                    }
                }
                .themedList()
                .listStyle(.insetGrouped)
                .refreshable {
                    await viewModel.load()
                }
            }
        }
        .srhtErrorBanner(
            error: Binding(
                get: { viewModel.error },
                set: { viewModel.error = $0 }
            )
        )
        .alert("Remove Access?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )) {
            Button("Cancel", role: .cancel) {
                /* Dismiss only; removal is confirmed separately. */
            }
            Button("Remove Access", role: .destructive) {
                guard let entry = pendingDeletion else { return }
                Task {
                    await viewModel.removeEntry(entry)
                    pendingDeletion = nil
                }
            }
        } message: {
            if let entry = pendingDeletion {
                Text("\(entry.entity.canonicalName) will lose \(entry.mode.displayName.lowercased()) access to this repository.")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                RepositoryACLAddUserView(viewModel: viewModel) {
                    showAddSheet = false
                }
            }
        }
    }
}

private struct RepositoryACLEntryRow: View {
    let entry: RepositoryACLEntry
    let isUpdating: Bool
    let isDeleting: Bool
    let onSelectMode: (AccessMode) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(entry.entity.canonicalName)
                .font(.body.monospaced())
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isUpdating || isDeleting {
                ProgressView()
                    .controlSize(.small)
            }

            Menu {
                ForEach(AccessMode.allCases, id: \.self) { mode in
                    Button {
                        onSelectMode(mode)
                    } label: {
                        if mode == entry.mode {
                            Label(mode.displayName, systemImage: "checkmark")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                }
            } label: {
                Text(entry.mode.shortLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }
            .disabled(isUpdating || isDeleting)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .disabled(isUpdating || isDeleting)
        }
    }
}

private struct RepositoryACLAddUserView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var viewModel: RepositoryACLViewModel
    let onAdded: () -> Void

    var body: some View {
        Form {
            Section("User") {
                TextField("Username or ~username", text: $viewModel.addUsername)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .themedRow()

                if let validation = inlineValidationMessage {
                    Text(validation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .themedRow()
                }
            }

            Section("Permission") {
                Picker("Permission", selection: $viewModel.addMode) {
                    ForEach(AccessMode.allCases, id: \.self) { mode in
                        Text(mode.shortLabel).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .themedRow()
            }
        }
        .themedList()
        .navigationTitle("Add User")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    Task {
                        if await viewModel.addEntry() {
                            onAdded()
                        }
                    }
                }
                .disabled(!viewModel.canSubmitNewEntry)
            }
        }
    }

    private var inlineValidationMessage: String? {
        let trimmed = viewModel.addUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return viewModel.addValidationMessage
    }
}
