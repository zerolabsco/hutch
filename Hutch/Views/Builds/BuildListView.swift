import SwiftUI

struct BuildListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: BuildListViewModel?
    @State private var showSubmitSheet = false
    @State private var submittedJobId: Int?

    var body: some View {
        Group {
            if let viewModel {
                listContent(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading builds…")
            }
        }
        .navigationTitle("Builds")
        .toolbar {
            if viewModel != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSubmitSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showSubmitSheet) {
            if let viewModel {
                SubmitBuildSheet(viewModel: viewModel) { jobId in
                    showSubmitSheet = false
                    submittedJobId = jobId
                }
            }
        }
        .navigationDestination(for: JobSummary.self) { job in
            BuildDetailView(jobId: job.id)
        }
        .navigationDestination(isPresented: Binding(
            get: { submittedJobId != nil },
            set: { isPresented in
                if !isPresented {
                    submittedJobId = nil
                }
            }
        )) {
            if let submittedJobId {
                BuildDetailView(jobId: submittedJobId)
            }
        }
        .task {
            if viewModel == nil {
                let vm = BuildListViewModel(client: appState.client)
                viewModel = vm
                await vm.loadJobs()
            }
        }
    }

    @ViewBuilder
    private func listContent(_ viewModel: BuildListViewModel) -> some View {
        @Bindable var vm = viewModel

        List {
            ForEach(viewModel.jobs) { job in
                NavigationLink(value: job) {
                    BuildRowView(job: job)
                }
                .task {
                    await viewModel.loadMoreIfNeeded(currentItem: job)
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
            if viewModel.isLoading, viewModel.jobs.isEmpty {
                SRHTLoadingStateView(message: "Loading builds…")
            } else if let error = viewModel.error, viewModel.jobs.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Builds",
                    message: error,
                    retryAction: { await viewModel.loadJobs() }
                )
            } else if viewModel.jobs.isEmpty, viewModel.error == nil {
                ContentUnavailableView(
                    "No Builds",
                    systemImage: "hammer",
                    description: Text("Your build jobs will appear here.")
                )
            }
        }
        .connectivityOverlay(hasContent: !viewModel.jobs.isEmpty) {
            await viewModel.loadJobs()
        }
        .srhtErrorBanner(error: $vm.error)
        .refreshable {
            await viewModel.loadJobs()
        }
    }
}

private struct SubmitBuildSheet: View {
    let viewModel: BuildListViewModel
    let onSubmitted: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModelBindable: BuildListViewModel
    @State private var manifest = ""
    @State private var tagsText = ""
    @State private var note = ""
    @State private var secrets = false
    @State private var execute = true
    @State private var visibility: Visibility = .public

    init(viewModel: BuildListViewModel, onSubmitted: @escaping (Int) -> Void) {
        self.viewModel = viewModel
        self._viewModelBindable = Bindable(viewModel)
        self.onSubmitted = onSubmitted
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Build Manifest") {
                    TextField("Paste a build manifest", text: $manifest, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(12...24)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Build Options") {
                    TextField("Note (optional)", text: $note)
                    TextField("Tags (comma-separated, optional)", text: $tagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Visibility", selection: $visibility) {
                        Text("Public").tag(Visibility.public)
                        Text("Unlisted").tag(Visibility.unlisted)
                        Text("Private").tag(Visibility.private)
                    }
                    Toggle("Start build now", isOn: $execute)
                    Toggle("Allow build secrets", isOn: $secrets)
                }

                Section {
                    Text("You need a valid builds.sr.ht manifest and a token with BUILDS:RW.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.error {
                    Section {
                        Label {
                            Text(error)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Submit Build")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                viewModelBindable.error = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModelBindable.error = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let tags = tagsText
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            if let jobId = await viewModel.submitBuild(
                                manifest: manifest,
                                tags: tags,
                                note: note,
                                secrets: secrets,
                                execute: execute,
                                visibility: visibility
                            ) {
                                onSubmitted(jobId)
                            }
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Submit Build")
                        }
                    }
                    .disabled(manifest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmitting)
                }
            }
        }
    }
}
