import SwiftUI

struct HgRepositorySettingsView: View {
    let repository: RepositorySummary
    let client: SRHTClient
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: HgRepositorySettingsViewModel?
    @State private var showDeleteConfirmation = false
    @State private var pendingACLDeletion: HgACLEntry?

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
                let vm = HgRepositorySettingsViewModel(repository: repository, client: client)
                viewModel = vm
                async let info: () = vm.loadRepositoryInfo()
                async let acls: () = vm.loadACLs()
                _ = await (info, acls)
            }
        }
    }

    @ViewBuilder
    private func settingsForm(_ viewModel: HgRepositorySettingsViewModel) -> some View {
        @Bindable var vm = viewModel

        Form {
            infoSection(viewModel)
            accessSection(viewModel)
            featuresSection(viewModel)
            histeditSection(viewModel)
            deleteSection(viewModel)
        }
        .themedList()
        .srhtErrorBanner(error: $vm.error)
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
        .alert("Remove Access?", isPresented: Binding(
            get: { pendingACLDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingACLDeletion = nil
                }
            }
        )) {
            Button("Cancel", role: .cancel) {
                // Alert dismissal is implicit; no additional action required.
            }
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
    }

    @ViewBuilder
    private func infoSection(_ viewModel: HgRepositorySettingsViewModel) -> some View {
        Section("Current Configuration") {
            LabeledContent("Repository") {
                Text("\(repository.owner.canonicalName)/\(repository.name)")
                    .font(.body.monospaced())
            }
            .themedRow()

            LabeledContent("Forge") {
                Text(repositoryForgeLabel(repository.service))
            }
            .themedRow()

            LabeledContent("Visibility") {
                Text(repositoryVisibilityLabel(viewModel.editedVisibility))
            }
            .themedRow()
        }

        Section("Repository Details") {
            TextField("Description", text: Bindable(viewModel).editedDescription, axis: .vertical)
                .lineLimit(3...6)
                .themedRow()

            Picker("Visibility", selection: Bindable(viewModel).editedVisibility) {
                Text("Public").tag(Visibility.publicVisibility)
                Text("Unlisted").tag(Visibility.unlisted)
                Text("Private").tag(Visibility.privateVisibility)
            }
            .themedRow()

            Button {
                Task {
                    _ = await viewModel.saveInfo()
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
            .disabled(viewModel.isSavingInfo || !viewModel.isInfoDirty)
            .themedRow()
        }
    }

    @ViewBuilder
    private func accessSection(_ viewModel: HgRepositorySettingsViewModel) -> some View {
        Section("Access") {
            if viewModel.isLoadingACLs {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .themedRow()
            } else if viewModel.acls.isEmpty {
                Text("No access entries yet.")
                    .foregroundStyle(.secondary)
                    .themedRow()
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
                .themedRow()
            }

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
            .themedRow()
            Text("Add a SourceHut user and choose read-only or read/write access.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .themedRow()
        }
    }

    @ViewBuilder
    private func featuresSection(_ viewModel: HgRepositorySettingsViewModel) -> some View {
        Section("Sensitive Settings") {
            Toggle("Hide this repository from public listings", isOn: Bindable(viewModel).editedNonPublishing)
                .themedRow()
            Text("Changes stay pending until you save this section.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .themedRow()

            Button {
                Task {
                    _ = await viewModel.saveInfo()
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
            .disabled(viewModel.isSavingInfo || !viewModel.isInfoDirty)
            .themedRow()
        }
    }

    @ViewBuilder
    private func histeditSection(_ viewModel: HgRepositorySettingsViewModel) -> some View {
        Section("Histedit") {
            TextField("Revision hash", text: Bindable(viewModel).histeditRevision)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .disabled(true)
                .themedRow()

            Text("Removing revisions is not available through the public hg.sr.ht API, so Hutch can’t do this yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .themedRow()

            Button("Remove Revision", role: .destructive) {
                // Not implemented: the hg.sr.ht API does not expose a histedit endpoint.
                // This button is disabled until the API supports revision removal.
            }
                .disabled(true)
                .themedRow()
        }
    }

    @ViewBuilder
    private func deleteSection(_ viewModel: HgRepositorySettingsViewModel) -> some View {
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
            .themedRow()
        } header: {
            Text("Danger Zone")
        }
    }
}
