import SwiftUI

struct HgRepositoryDetailView: View {
    let repository: RepositorySummary
    let onDeleted: (() -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel: HgRepositoryDetailViewModel?
    @State private var selectedTab: HgRepositoryDetailViewModel.Tab = .summary
    @State private var showSettings = false
    @State private var isShowingRepositoryDetails = false
    @State private var showBrowseRefPicker = false

    private var shareURL: URL? {
        guard let viewModel, let selectedFilePath = viewModel.selectedFilePath else { return nil }
        return SRHTWebURL.file(
            repository: repository,
            revspec: viewModel.browseRevspec,
            path: selectedFilePath
        )
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading repository…")
            }
        }
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if selectedTab == .browse, let viewModel {
                    Button {
                        showBrowseRefPicker = true
                    } label: {
                        Label(
                            browseRevspecLabel(viewModel.browseRevspec),
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.subheadline)
                    }
                }

                SRHTShareButton(url: SRHTWebURL.repository(repository), target: .repository) {
                    Image(systemName: "square.and.arrow.up")
                }

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            HgRepositorySettingsView(
                repository: repository,
                client: appState.client,
                onDeleted: {
                    dismiss()
                    onDeleted?()
                }
            )
        }
        .sheet(isPresented: $showBrowseRefPicker) {
            if let viewModel {
                HgBrowseRefPickerSheet(viewModel: viewModel, isPresented: $showBrowseRefPicker)
            }
        }
        .task {
            if viewModel == nil {
                let vm = HgRepositoryDetailViewModel(repository: repository, client: appState.client)
                viewModel = vm
                async let summary: () = vm.loadSummary()
                async let browse: () = vm.loadBrowseRoot()
                async let log: () = vm.loadLog()
                _ = await (summary, browse, log)
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: HgRepositoryDetailViewModel) -> some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(HgRepositoryDetailViewModel.Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case .summary:
                summaryTab(viewModel)
            case .browse:
                browseTab(viewModel)
            case .log:
                logTab(viewModel)
            case .tags:
                revisionsList(viewModel.tags, emptyTitle: "No Tags", emptyDescription: "This repository does not have any tags.")
            case .branches:
                revisionsList(viewModel.branches, emptyTitle: "No Branches", emptyDescription: "This repository does not have any named branches.")
            case .bookmarks:
                revisionsList(viewModel.bookmarks, emptyTitle: "No Bookmarks", emptyDescription: "This repository does not have any bookmarks.")
            }
        }
        .srhtErrorBanner(error: Binding(
            get: { viewModel.error },
            set: { viewModel.error = $0 }
        ))
    }

    @ViewBuilder
    private func summaryTab(_ viewModel: HgRepositoryDetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                metadataSection(viewModel)
                repositoryDetailsSection(viewModel)
                latestChangeSection(viewModel)
                readmeSection(viewModel)
            }
            .padding()
        }
        .overlay {
            if viewModel.isLoadingSummary, !viewModel.summaryLoaded, viewModel.tip == nil, viewModel.readmeContent == nil {
                SRHTLoadingStateView(message: "Loading repository…")
            } else if let error = viewModel.error, !viewModel.summaryLoaded, viewModel.tip == nil, viewModel.readmeContent == nil {
                SRHTErrorStateView(
                    title: "Couldn't Load Repository",
                    message: error,
                    retryAction: { await viewModel.loadSummary() }
                )
            }
        }
        .refreshable {
            await viewModel.loadSummary()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(repository.owner.canonicalName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(repository.name)
                .font(.largeTitle.weight(.semibold))
            if let description = repository.description, !description.isEmpty {
                Text(description)
                    .font(.body)
            }
        }
    }

    @ViewBuilder
    private func metadataSection(_ viewModel: HgRepositoryDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SummaryMetadataRow(
                icon: "arrow.triangle.branch",
                title: viewModel.tip?.branch ?? repository.head?.name ?? repositoryVisibilityLabel(repository.visibility)
            )

            if let readmePath = viewModel.readmePath {
                SummaryMetadataRow(
                    icon: "doc.text",
                    title: readmePath
                )
            }
        }
    }

    private func repositoryDetailsSection(_ viewModel: HgRepositoryDetailViewModel) -> some View {
        DisclosureGroup(isExpanded: $isShowingRepositoryDetails) {
            VStack(alignment: .leading, spacing: 12) {
                SummaryDetailRow(label: "Visibility", value: repositoryVisibilityLabel(repository.visibility))
                SummaryDetailRow(label: "Publishing", value: viewModel.nonPublishing ? "Non-publishing" : "Publishing")
                SummaryDetailRow(label: "Read-only", value: repositoryCloneURLs(for: repository).readOnly, monospace: true)
                SummaryDetailRow(label: "Read/write", value: repositoryCloneURLs(for: repository).readWrite, monospace: true)
                SummaryDetailRow(label: "RID", value: repository.rid, monospace: true)
            }
            .padding(.top, 8)
        } label: {
            Text("Repository Details")
                .font(.subheadline.weight(.medium))
        }
    }

    @ViewBuilder
    private func latestChangeSection(_ viewModel: HgRepositoryDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isLoadingSummary && viewModel.tip == nil {
                SRHTLoadingStateView(message: "Loading latest change…")
                    .frame(maxWidth: .infinity)
            } else if let tip = viewModel.tip {
                SummaryMetadataRow(
                    icon: "arrow.trianglehead.clockwise",
                    title: tip.title,
                    subtitle: "\(tip.displayShortId) — \(tip.author)"
                )
            } else if let error = viewModel.error, !viewModel.summaryLoaded {
                SRHTErrorStateView(
                    title: "Couldn't Load Latest Change",
                    message: error,
                    retryAction: { await viewModel.loadSummary() }
                )
            } else {
                ContentUnavailableView(
                    "No Recent Revisions",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("This repository does not have any revision history yet.")
                )
            }
        }
    }

    @ViewBuilder
    private func readmeSection(_ viewModel: HgRepositoryDetailViewModel) -> some View {
        if viewModel.isLoadingSummary && !viewModel.summaryLoaded {
            SRHTLoadingStateView(message: "Loading README…")
        } else if let readmeView = readmeContentView(viewModel) {
            readmeView
        } else if let error = viewModel.error, !viewModel.summaryLoaded {
            SRHTErrorStateView(
                title: "Couldn't Load README",
                message: error,
                retryAction: { await viewModel.loadSummary() }
            )
        } else {
            ContentUnavailableView(
                "No README",
                systemImage: "doc.text",
                description: Text("This repository does not have a README file.")
            )
        }
    }

    @ViewBuilder
    private func browseTab(_ viewModel: HgRepositoryDetailViewModel) -> some View {
        VStack(spacing: 0) {
            browseBreadcrumbs(viewModel)
            Divider()

            if viewModel.isLoadingBrowse, viewModel.files.isEmpty, viewModel.selectedFilePath == nil {
                SRHTLoadingStateView(message: "Loading files…")
            } else if let selectedFilePath = viewModel.selectedFilePath, let fileContent = viewModel.fileContent {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        SRHTShareButton(url: shareURL, target: .file) {
                            Label("Share File", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)

                    GeometryReader { geometry in
                        ScrollView([.vertical, .horizontal]) {
                            Text(fileContent)
                                .font(.system(.body, design: .monospaced))
                                .frame(
                                    minWidth: geometry.size.width,
                                    minHeight: geometry.size.height,
                                    alignment: .topLeading
                                )
                                .padding()
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button("Back to directory") {
                        viewModel.dismissFileView()
                    }
                    .buttonStyle(.bordered)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
                }
                .navigationTitle(selectedFilePath.split(separator: "/").last.map(String.init) ?? repository.name)
            } else if let error = viewModel.error, viewModel.files.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Files",
                    message: error,
                    retryAction: { await viewModel.loadBrowseRoot() }
                )
            } else if viewModel.files.isEmpty {
                ContentUnavailableView(
                    "No Files",
                    systemImage: "folder",
                    description: Text("This revision does not contain any browsable files.")
                )
            } else {
                List(viewModel.files) { file in
                    HgFileRow(file: file)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await viewModel.openFile(file) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .refreshable {
            await viewModel.loadBrowseRoot()
        }
    }

    private func browseBreadcrumbs(_ viewModel: HgRepositoryDetailViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    Task { await viewModel.navigateToPath(index: 0) }
                } label: {
                    Text("root")
                        .font(.subheadline.monospaced())
                }
                .buttonStyle(.plain)

                ForEach(Array(viewModel.pathStack.enumerated()), id: \.offset) { index, component in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Button {
                        Task { await viewModel.navigateToPath(index: index + 1) }
                    } label: {
                        Text(component)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if let selectedFilePath = viewModel.selectedFilePath {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(selectedFilePath.split(separator: "/").last.map(String.init) ?? selectedFilePath)
                        .font(.subheadline.monospaced())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    @ViewBuilder
    private func logTab(_ viewModel: HgRepositoryDetailViewModel) -> some View {
        List {
            ForEach(viewModel.log) { revision in
                revisionRow(revision)
                    .task {
                        await viewModel.loadMoreLogIfNeeded(currentItem: revision)
                    }
            }

            if viewModel.isLoadingMoreLog {
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
            if viewModel.isLoadingLog, viewModel.log.isEmpty {
                SRHTLoadingStateView(message: "Loading revisions…")
            } else if let error = viewModel.error, viewModel.log.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Revisions",
                    message: error,
                    retryAction: { await viewModel.loadLog() }
                )
            } else if viewModel.log.isEmpty {
                ContentUnavailableView(
                    "No Revisions",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("This repository has no revision history.")
                )
            }
        }
        .refreshable {
            await viewModel.loadLog()
        }
    }

    @ViewBuilder
    private func revisionsList(_ revisions: [HgNamedRevision], emptyTitle: String, emptyDescription: String) -> some View {
        if revisions.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: "tray",
                description: Text(emptyDescription)
            )
        } else {
            List(revisions) { revision in
                namedRevisionRow(revision)
            }
            .listStyle(.plain)
        }
    }

    private func revisionRow(_ revision: HgRevision) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(revision.primaryName)
                    .font(.headline)
                Spacer()
                Text(revision.displayShortId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(revision.title)
                .font(.subheadline)

            if let body = revision.body {
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text(revision.author)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func namedRevisionRow(_ revision: HgNamedRevision) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(revision.name)
                .font(.headline)
            Spacer()
            Text(revision.displayShortId)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func readmeContentView(_ viewModel: HgRepositoryDetailViewModel) -> AnyView? {
        guard let content = viewModel.readmeContent else {
            return nil
        }

        return AnyView(
            RenderedMarkupContentView(
                content: sharedReadmeContent(from: content),
                readmePath: viewModel.readmePath,
                colorScheme: colorScheme,
                ownerCanonicalName: repository.owner.canonicalName,
                repositoryName: repository.name,
                repositoryHost: "hg.sr.ht"
            )
        )
    }

    private func browseRevspecLabel(_ revspec: String) -> String {
        if revspec == "tip" {
            return "tip"
        }
        return revspec
    }

    private func sharedReadmeContent(from content: HgRepositoryDetailViewModel.ReadmeContent) -> RenderedMarkupContent {
        switch content {
        case .html(let html):
            .html(html)
        case .markdown(let text):
            .markdown(text)
        case .org(let text):
            .org(text)
        case .plainText(let text):
            .plainText(text)
        }
    }

    private func displayFileName(_ name: String) -> String {
        name.hasSuffix("/") ? String(name.dropLast()) : name
    }

}

private struct HgBrowseRefPickerSheet: View {
    let viewModel: HgRepositoryDetailViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task {
                            await viewModel.changeBrowseRevspec("tip")
                            isPresented = false
                        }
                    } label: {
                        refRow(
                            title: "tip",
                            systemImage: "arrow.triangle.branch",
                            color: .blue,
                            isSelected: viewModel.browseRevspec == "tip"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if !viewModel.branches.isEmpty {
                    Section("Branches") {
                        ForEach(viewModel.branches) { revision in
                            Button {
                                Task {
                                    await viewModel.changeBrowseRevspec(revision.name)
                                    isPresented = false
                                }
                            } label: {
                                refRow(
                                    title: revision.name,
                                    systemImage: "arrow.triangle.branch",
                                    color: .blue,
                                    isSelected: viewModel.browseRevspec == revision.name
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !viewModel.tags.isEmpty {
                    Section("Tags") {
                        ForEach(viewModel.tags) { revision in
                            Button {
                                Task {
                                    await viewModel.changeBrowseRevspec(revision.name)
                                    isPresented = false
                                }
                            } label: {
                                refRow(
                                    title: revision.name,
                                    systemImage: "tag",
                                    color: .orange,
                                    isSelected: viewModel.browseRevspec == revision.name
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !viewModel.bookmarks.isEmpty {
                    Section("Bookmarks") {
                        ForEach(viewModel.bookmarks) { revision in
                            Button {
                                Task {
                                    await viewModel.changeBrowseRevspec(revision.name)
                                    isPresented = false
                                }
                            } label: {
                                refRow(
                                    title: revision.name,
                                    systemImage: "bookmark",
                                    color: .purple,
                                    isSelected: viewModel.browseRevspec == revision.name
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Ref")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }

    private func refRow(title: String, systemImage: String, color: Color, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(color)

            Text(title)
                .font(.body.monospaced())
                .foregroundStyle(.primary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct HgFileRow: View {
    let file: HgFile

    var body: some View {
        Label {
            Text(displayName)
                .font(.body.monospaced())
                .lineLimit(1)
        } icon: {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(file.isDirectory ? .blue : .secondary)
        }
    }

    private var displayName: String {
        file.name.hasSuffix("/") ? String(file.name.dropLast()) : file.name
    }
}
