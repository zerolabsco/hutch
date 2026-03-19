import SwiftUI

struct RepositorySettingsView: View {
    let repository: RepositorySummary
    let branches: [Reference]
    let client: SRHTClient
    let onRenamed: (String) -> Void
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RepositorySettingsViewModel?
    @State private var showDeleteConfirmation = false
    @State private var pendingACLDeletion: ACLEntry?
    @State private var saveResultAlert: SaveResultAlert?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    settingsForm(viewModel)
                } else {
                    SRHTLoadingStateView(message: "Loading settings…")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            if viewModel == nil {
                let vm = RepositorySettingsViewModel(
                    repository: repository,
                    branches: branches,
                    client: client
                )
                viewModel = vm
                await vm.loadACLs()
            }
        }
    }

    @ViewBuilder
    private func settingsForm(_ viewModel: RepositorySettingsViewModel) -> some View {
        @Bindable var vm = viewModel

        Form {
            infoSection(viewModel)
            renameSection(viewModel)
            accessSection(viewModel)
            deleteSection(viewModel)
        }
        .srhtErrorBanner(error: $vm.error)
        .alert(
            "Permanently delete \(repository.owner.canonicalName)/\(repository.name)?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteRepository()
                    if viewModel.didDelete {
                        dismiss()
                        onDeleted()
                    }
                }
            }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Remove Access?", isPresented: Binding(
            get: { pendingACLDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingACLDeletion = nil
                }
            }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Access", role: .destructive) {
                guard let entry = pendingACLDeletion else { return }
                Task {
                    await viewModel.deleteACL(entry)
                    pendingACLDeletion = nil
                }
            }
        } message: {
            if let entry = pendingACLDeletion {
                Text("\(entry.entity.canonicalName) will lose \(entry.mode) access to this repository.")
            }
        }
        .alert(item: $saveResultAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Info Section

    @ViewBuilder
    private func infoSection(_ viewModel: RepositorySettingsViewModel) -> some View {
        Section("Info") {
            LabeledContent("Name") {
                Text(repository.name)
                    .font(.body.monospaced())
            }

            TextField("Description", text: Bindable(viewModel).editedDescription, axis: .vertical)
                .lineLimit(3...6)

            Picker("Visibility", selection: Bindable(viewModel).editedVisibility) {
                Text("Public").tag(Visibility.public)
                Text("Unlisted").tag(Visibility.unlisted)
                Text("Private").tag(Visibility.private)
            }

            if !viewModel.branches.isEmpty {
                Picker("Default Branch", selection: Bindable(viewModel).editedHead) {
                    ForEach(viewModel.branches, id: \.name) { branch in
                        let name = branch.name.replacingOccurrences(of: "refs/heads/", with: "")
                        Text(name).tag(name)
                    }
                }
            }

            Button {
                Task {
                    let didSave = await viewModel.saveInfo()
                    saveResultAlert = SaveResultAlert(
                        title: didSave ? "Settings Updated" : "Couldn't Update Settings",
                        message: didSave ? "Repository settings were saved." : (viewModel.error ?? "Please try again.")
                    )
                }
            } label: {
                if viewModel.isSavingInfo {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Save Changes")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(viewModel.isSavingInfo)
        }
    }

    // MARK: - Rename Section

    @ViewBuilder
    private func renameSection(_ viewModel: RepositorySettingsViewModel) -> some View {
        Section {
            TextField("New repository name", text: Bindable(viewModel).editedName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Text("This will change the repository URL. Existing clones will be redirected but links may break.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await viewModel.rename()
                    if let newName = viewModel.updatedName {
                        onRenamed(newName)
                        dismiss()
                    }
                }
            } label: {
                if viewModel.isRenaming {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Rename Repository")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(viewModel.isRenaming || viewModel.editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("Rename")
        }
    }

    // MARK: - Access Section

    @ViewBuilder
    private func accessSection(_ viewModel: RepositorySettingsViewModel) -> some View {
        Section {
            if viewModel.isLoadingACLs {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if viewModel.acls.isEmpty {
                Text("No access entries yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.acls) { entry in
                    HStack {
                        Text(entry.entity.canonicalName)
                        Spacer()
                        Text(entry.mode)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingACLDeletion = entry
                        } label: {
                            Label("Remove Access", systemImage: "trash")
                        }
                    }
                }
            }

            // Add ACL form
            HStack {
                TextField("Username or ~username", text: Bindable(viewModel).newACLEntity)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Picker("", selection: Bindable(viewModel).newACLMode) {
                    Text("RO").tag("RO")
                    Text("RW").tag("RW")
                }
                .pickerStyle(.segmented)
                .frame(width: 100)

                Button {
                    Task { await viewModel.addACL() }
                } label: {
                    if viewModel.isAddingACL {
                        ProgressView()
                    } else {
                        Text("Add")
                    }
                }
                .disabled(viewModel.isAddingACL || viewModel.newACLEntity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Add a SourceHut user and choose read-only or read/write access.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Access")
        }
    }

    // MARK: - Delete Section

    @ViewBuilder
    private func deleteSection(_ viewModel: RepositorySettingsViewModel) -> some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                if viewModel.isDeleting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Delete Repository")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(viewModel.isDeleting)
        }
    }

    private struct SaveResultAlert: Identifiable {
        let title: String
        let message: String

        var id: String { "\(title)-\(message)" }
    }
}
