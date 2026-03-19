import SwiftUI

struct BuildDetailView: View {
    let jobId: Int

    @Environment(AppState.self) private var appState
    @State private var viewModel: BuildDetailViewModel?
    @State private var rebuiltJobId: Int?
    @State private var showEditResubmitSheet = false
    @State private var showCancelConfirmation = false

    var body: some View {
        Group {
            if let viewModel {
                detailContent(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading build…")
            }
        }
        .navigationTitle("Job #\(jobId)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SRHTShareButton(
                    url: viewModel?.job.flatMap { SRHTWebURL.build(jobId: $0.id, ownerCanonicalName: $0.owner.canonicalName) },
                    target: .build
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { rebuiltJobId != nil },
            set: { isPresented in
                if !isPresented {
                    rebuiltJobId = nil
                }
            }
        )) {
            if let rebuiltJobId {
                BuildDetailView(jobId: rebuiltJobId)
            }
        }
        .sheet(isPresented: $showEditResubmitSheet) {
            if let viewModel, let job = viewModel.job {
                EditResubmitBuildSheet(viewModel: viewModel, job: job) { jobId in
                    showEditResubmitSheet = false
                    rebuiltJobId = jobId
                }
            }
        }
        .alert("Cancel Build?", isPresented: $showCancelConfirmation) {
            Button("Keep Running", role: .cancel) {}
            Button("Cancel Build", role: .destructive) {
                Task { await viewModel?.cancelJob() }
            }
        } message: {
            Text("The build will stop as soon as possible.")
        }
        .task {
            if viewModel == nil {
                let vm = BuildDetailViewModel(jobId: jobId, client: appState.client)
                viewModel = vm
                await vm.loadJob()
            }
        }
    }

    @ViewBuilder
    private func detailContent(_ viewModel: BuildDetailViewModel) -> some View {
        if viewModel.isLoading, viewModel.job == nil {
            SRHTLoadingStateView(message: "Loading build…")
        } else if let error = viewModel.error, viewModel.job == nil {
            SRHTErrorStateView(
                title: "Couldn't Load Build",
                message: error,
                retryAction: { await viewModel.loadJob() }
            )
        } else if let job = viewModel.job {
            List {
                // Status & metadata
                Section("Details") {
                    HStack {
                        Text("Status")
                        Spacer()
                        HStack(spacing: 6) {
                            JobStatusIcon(status: job.status)
                            Text(job.status.rawValue)
                                .font(.subheadline.weight(.medium))
                        }
                    }

                    if let note = job.note, !note.isEmpty {
                        LabeledContent("Note", value: note)
                    }

                    if let image = job.image {
                        LabeledContent("Image", value: image)
                    }

                    if !job.tags.isEmpty {
                        LabeledContent("Tags", value: job.tags.joined(separator: ", "))
                    }

                    if let visibility = job.visibility {
                        LabeledContent("Visibility", value: visibility.rawValue.capitalized)
                    }

                    LabeledContent("Owner", value: job.owner.canonicalName)
                    LabeledContent("Created", value: job.created.relativeDescription)
                    LabeledContent("Updated", value: job.updated.relativeDescription)
                }

                // Per-task logs
                if !job.tasks.isEmpty {
                    ForEach(job.tasks) { task in
                        Section {
                            TaskLogSection(task: task, viewModel: viewModel)
                        } header: {
                            HStack(spacing: 6) {
                                TaskStatusIcon(status: task.status)
                                Text(task.name)
                            }
                        }
                    }
                }

                // Cancel button
                if job.status.isCancellable {
                    Section {
                        Button(role: .destructive) {
                            showCancelConfirmation = true
                        } label: {
                            HStack {
                                Text("Cancel Build")
                                if viewModel.isCancelling {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(viewModel.isCancelling)
                    }
                }

                if let manifest = job.manifest,
                   !manifest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Button {
                            Task {
                                rebuiltJobId = await viewModel.rebuildJob()
                            }
                        } label: {
                            HStack {
                                Text(job.status == .failed || job.status == .cancelled || job.status == .timeout ? "Retry Build" : "Rebuild")
                                if viewModel.isRebuilding {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(viewModel.isRebuilding)

                        Button {
                            showEditResubmitSheet = true
                        } label: {
                            Text("Edit & Resubmit")
                        }
                        .disabled(viewModel.isSubmittingEditedBuild)
                    } footer: {
                        Text("Creates a new build using this job’s saved manifest, tags, note, and visibility.")
                    }
                }
            }
            .refreshable {
                await viewModel.loadJob()
            }
            .srhtErrorBanner(error: Binding(
                get: { viewModel.error },
                set: { viewModel.error = $0 }
            ))
        }
    }
}

private struct EditResubmitBuildSheet: View {
    let viewModel: BuildDetailViewModel
    let job: JobDetail
    let onSubmitted: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModelBindable: BuildDetailViewModel
    @State private var manifest: String
    @State private var tagsText: String
    @State private var note: String
    @State private var secrets = false
    @State private var execute = true
    @State private var visibility: Visibility

    init(viewModel: BuildDetailViewModel, job: JobDetail, onSubmitted: @escaping (Int) -> Void) {
        self.viewModel = viewModel
        self._viewModelBindable = Bindable(viewModel)
        self.job = job
        self.onSubmitted = onSubmitted
        _manifest = State(initialValue: job.manifest ?? "")
        _tagsText = State(initialValue: job.tags.joined(separator: ", "))
        _note = State(initialValue: job.note ?? "")
        _visibility = State(initialValue: job.visibility ?? .public)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Build Manifest") {
                    TextField("Build manifest", text: $manifest, axis: .vertical)
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
                    Text("This submits a new build. “Start build now” and “Allow build secrets” use local defaults because the current job does not include those original values.")
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
            .navigationTitle("Edit & Resubmit")
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
                        if viewModel.isSubmittingEditedBuild {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Submit Build")
                        }
                    }
                    .disabled(manifest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmittingEditedBuild)
                }
            }
        }
    }
}

// MARK: - Task Log Section

private struct TaskLogSection: View {
    let task: BuildTask
    let viewModel: BuildDetailViewModel

    @State private var isExpanded: Bool

    init(task: BuildTask, viewModel: BuildDetailViewModel) {
        self.task = task
        self.viewModel = viewModel
        self._isExpanded = State(initialValue: task.status == .failed)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if viewModel.loadingTaskLogs.contains(task.logCacheKey) {
                HStack {
                    Spacer()
                    ProgressView("Loading log…")
                    Spacer()
                }
            } else if let logText = viewModel.taskLogs[task.logCacheKey] {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(logText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if task.log == nil {
                Text("No log available.")
                    .foregroundStyle(.secondary)
            }
        } label: {
            HStack {
                Text(task.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            if isExpanded {
                await viewModel.loadTaskLog(task: task)
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                Task { await viewModel.loadTaskLog(task: task) }
            }
        }
    }
}

// MARK: - Task Status Icon

private struct TaskStatusIcon: View {
    let status: TaskStatus

    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(color)
            .frame(width: 20)
    }

    private var iconName: String {
        switch status {
        case .success: "checkmark.circle.fill"
        case .failed:  "xmark.circle.fill"
        case .running: "arrow.trianglehead.2.clockwise.rotate.90"
        case .pending: "circle.dashed"
        case .skipped: "forward.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .success: .green
        case .failed:  .red
        case .running: .yellow
        case .pending: .gray
        case .skipped: .secondary
        }
    }
}
