import SwiftUI

struct HgRepositorySettingsView: View {
    let repository: RepositorySummary
    let client: SRHTClient
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: HgRepositorySettingsViewModel?
    @State private var showDeleteConfirmation = false
    @State private var pendingACLDeletion: HgACLEntry?
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

    @ViewBuilder
    private func infoSection(_ viewModel: HgRepositorySettingsViewModel) -> some View {
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

    @ViewBuilder
    private func accessSection(_ viewModel: HgRepositorySettingsViewModel) -> some View {
        Section("Access") {
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
        }
    }

    @ViewBuilder
    private func featuresSection(_ viewModel: HgRepositorySettingsViewModel) -> some View {
        Section("Features") {
            Toggle("Hide this repository from public listings", isOn: Bindable(viewModel).editedNonPublishing)

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

    @ViewBuilder
    private func histeditSection(_ viewModel: HgRepositorySettingsViewModel) -> some View {
        Section("Histedit") {
            TextField("Revision hash", text: Bindable(viewModel).histeditRevision)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .disabled(true)

            Text("Removing revisions is not available through the public hg.sr.ht API, so Hutch can’t do this yet.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Remove Revision", role: .destructive) {}
                .disabled(true)
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
        }
    }

    private struct SaveResultAlert: Identifiable {
        let title: String
        let message: String

        var id: String { "\(title)-\(message)" }
    }
}
