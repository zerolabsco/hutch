import SwiftUI

struct RepositorySettingsView: View {
    let repository: RepositorySummary
    let branches: [ReferenceDetail]
    let client: SRHTClient
    let onUpdated: (RepositorySummary) -> Void
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RepositorySettingsViewModel?
    @State private var showVisibilityConfirmation = false
    @State private var showDeleteConfirmation = false

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
                viewModel = RepositorySettingsViewModel(
                    repository: repository,
                    branches: branches,
                    client: client
                )
            }
        }
    }

    @ViewBuilder
    private func settingsForm(_ viewModel: RepositorySettingsViewModel) -> some View {
        @Bindable var vm = viewModel

        Form {
            currentConfigurationSection(viewModel)
            metadataSection(viewModel)
            defaultBranchSection(viewModel)
            visibilitySection(viewModel)
            deleteSection(viewModel)
        }
        .themedList()
        .srhtErrorBanner(error: $vm.error)
        .alert(
            visibilityConfirmationTitle(for: viewModel),
            isPresented: $showVisibilityConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                viewModel.editedVisibility = viewModel.repository.visibility
            }
            Button("Apply", role: .destructive) {
                Task {
                    if let updatedRepository = await viewModel.updateVisibility() {
                        onUpdated(updatedRepository)
                    }
                }
            }
        } message: {
            Text(visibilityConfirmationMessage(for: viewModel))
        }
        .alert(
            "Permanently delete \(viewModel.repository.owner.canonicalName)/\(viewModel.repository.name)?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                // Alert dismissal is implicit.
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
    }

    @ViewBuilder
    private func currentConfigurationSection(_ viewModel: RepositorySettingsViewModel) -> some View {
        Section("Current Configuration") {
            LabeledContent("Repository") {
                Text("\(viewModel.repository.owner.canonicalName)/\(viewModel.repository.name)")
                    .font(.body.monospaced())
            }
            .themedRow()

            LabeledContent("Default Branch") {
                Text(viewModel.currentDefaultBranchName)
                    .font(.body.monospaced())
            }
            .themedRow()

            LabeledContent("Visibility") {
                Text(repositoryVisibilityLabel(viewModel.repository.visibility))
            }
            .themedRow()
        }
    }

    @ViewBuilder
    private func metadataSection(_ viewModel: RepositorySettingsViewModel) -> some View {
        Section {
            TextField("Repository name", text: Bindable(viewModel).editedName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .themedRow()

            TextField("Description", text: Bindable(viewModel).editedDescription, axis: .vertical)
                .lineLimit(2...4)
                .themedRow()

            if let metadataValidationMessage = viewModel.metadataValidationMessage {
                Text(metadataValidationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .themedRow()
            } else if viewModel.normalizedEditedName != viewModel.repository.name {
                Text("Changing the repository name updates the repository URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .themedRow()
            } else {
                Text("Name and description stay pending until you save this section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .themedRow()
            }

            Button {
                Task {
                    if let updatedRepository = await viewModel.saveMetadata() {
                        onUpdated(updatedRepository)
                    }
                }
            } label: {
                if viewModel.isSavingMetadata {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Save Details")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(
                viewModel.isMutating ||
                !viewModel.isMetadataDirty ||
                viewModel.metadataValidationMessage != nil
            )
            .themedRow()
        } header: {
            Text("Repository Details")
        }
    }

    @ViewBuilder
    private func defaultBranchSection(_ viewModel: RepositorySettingsViewModel) -> some View {
        Section {
            LabeledContent("Current") {
                Text(viewModel.currentDefaultBranchName)
                    .font(.body.monospaced())
            }
            .themedRow()

            if viewModel.branches.isEmpty {
                Text("This repository doesn't have any branches yet.")
                    .foregroundStyle(.secondary)
                    .themedRow()
            } else {
                Picker("Branch", selection: Bindable(viewModel).editedHead) {
                    ForEach(viewModel.availableBranchNames, id: \.self) { branch in
                        Text(branch)
                            .font(.body.monospaced())
                            .tag(branch)
                    }
                }
                .themedRow()

                Text("Changes stay pending until you set the new default branch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .themedRow()

                Button {
                    Task {
                        if let updatedRepository = await viewModel.saveDefaultBranch() {
                            onUpdated(updatedRepository)
                        }
                    }
                } label: {
                    if viewModel.isSavingDefaultBranch {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Set Default Branch")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(
                    viewModel.isMutating ||
                    !viewModel.isDefaultBranchDirty ||
                    viewModel.defaultBranchValidationMessage != nil
                )
                .themedRow()
            }
        } header: {
            Text("Default Branch")
        }
    }

    @ViewBuilder
    private func visibilitySection(_ viewModel: RepositorySettingsViewModel) -> some View {
        Section {
            Picker("Visibility", selection: Bindable(viewModel).editedVisibility) {
                Text("Public").tag(Visibility.publicVisibility)
                Text("Unlisted").tag(Visibility.unlisted)
                Text("Private").tag(Visibility.privateVisibility)
            }
            .themedRow()

            Text("Visibility changes apply immediately after you confirm them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .themedRow()

            Button {
                showVisibilityConfirmation = true
            } label: {
                if viewModel.isUpdatingVisibility {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Apply Visibility Change")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(viewModel.isMutating || !viewModel.isVisibilityDirty)
            .themedRow()
        } header: {
            Text("Sensitive Settings")
        }
    }

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
            .disabled(viewModel.isMutating)
            .themedRow()
        } header: {
            Text("Danger Zone")
        }
    }

    private func visibilityConfirmationTitle(for viewModel: RepositorySettingsViewModel) -> String {
        "Change visibility to \(repositoryVisibilityLabel(viewModel.editedVisibility))?"
    }

    private func visibilityConfirmationMessage(for viewModel: RepositorySettingsViewModel) -> String {
        switch viewModel.editedVisibility {
        case .publicVisibility:
            "Anyone will be able to find and view this repository."
        case .unlisted:
            "People with the link can view this repository, but it won't appear in public listings."
        case .privateVisibility:
            "Only people with explicit access will be able to view this repository."
        }
    }
}
