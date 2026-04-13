import SwiftUI

struct RepositorySettingsView: View {
    let repository: RepositorySummary
    let branches: [ReferenceDetail]
    let client: SRHTClient
    let onRenamed: (String) -> Void
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RepositorySettingsViewModel?
    @State private var showDeleteConfirmation = false
    @State private var showRenameConfirmation = false
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
            }
        }
    }

    @ViewBuilder
    private func settingsForm(_ viewModel: RepositorySettingsViewModel) -> some View {
        @Bindable var vm = viewModel

        Form {
            infoSection(viewModel)
            renameSection(viewModel)
            accessSection()
            deleteSection(viewModel)
        }
        .srhtErrorBanner(error: $vm.error)
        .alert(
            "Rename repository to \(viewModel.editedName.trimmingCharacters(in: .whitespacesAndNewlines))?",
            isPresented: $showRenameConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                // Alert dismissal is implicit; no additional action required.
            }
            Button("Rename", role: .destructive) {
                Task {
                    await viewModel.rename()
                    if let newName = viewModel.updatedName {
                        onRenamed(newName)
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This will change the repository URL. Existing clones will be redirected but links may break.")
        }
        .alert(
            "Permanently delete \(repository.owner.canonicalName)/\(repository.name)?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                // Alert dismissal is implicit; no additional action required.
            }
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
                showRenameConfirmation = true
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
    private func accessSection() -> some View {
        Section {
            NavigationLink {
                RepositoryACLView(repository: repository, client: client, showsDoneButton: false)
            } label: {
                Label("Manage Access", systemImage: "person.2")
            }

            Text("Review and update repository access without leaving settings.")
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
