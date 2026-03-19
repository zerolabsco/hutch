import SwiftUI

struct FileTreeView: View {
    let repository: RepositorySummary
    let client: SRHTClient

    @State private var viewModel: FileTreeViewModel?

    var body: some View {
        Group {
            if let viewModel {
                FileTreeContentView(repository: repository, viewModel: viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading files…")
            }
        }
        .task {
            if viewModel == nil {
                let vm = FileTreeViewModel(
                    repositoryRid: repository.rid,
                    service: repository.service,
                    client: client
                )
                viewModel = vm
                async let loadTree: () = vm.loadRootTree()
                async let loadRefs: () = vm.loadReferences()
                _ = await (loadTree, loadRefs)
            }
        }
    }
}

// MARK: - Content View

private struct FileTreeContentView: View {
    let repository: RepositorySummary
    let viewModel: FileTreeViewModel

    @State private var showRefPicker = false

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()
            contentArea
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRefPicker = true
                } label: {
                    Label(
                        revspecLabel,
                        systemImage: "arrow.triangle.branch"
                    )
                    .font(.subheadline)
                }
            }
        }
        .sheet(isPresented: $showRefPicker) {
            RefPickerSheet(viewModel: viewModel, isPresented: $showRefPicker)
        }
        .srhtErrorBanner(error: Binding(
            get: { viewModel.error },
            set: { viewModel.error = $0 }
        ))
        .refreshable {
            await viewModel.loadRootTree()
        }
    }

    private var shareURL: URL? {
        guard let viewingEntry = viewModel.viewingEntry else { return nil }
        return SRHTWebURL.file(
            repository: repository,
            revspec: viewModel.revspec,
            path: currentFilePath(for: viewingEntry)
        )
    }

    private var revspecLabel: String {
        let revspec = viewModel.revspec
        if revspec == "HEAD" {
            return "HEAD"
        }
        if revspec.hasPrefix("refs/heads/") {
            return String(revspec.dropFirst("refs/heads/".count))
        } else if revspec.hasPrefix("refs/tags/") {
            return String(revspec.dropFirst("refs/tags/".count))
        }
        return revspec
    }

    // MARK: - Breadcrumb Bar

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(Array(viewModel.navStack.enumerated()), id: \.offset) { index, navEntry in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Button {
                            Task {
                                await viewModel.navigateToBreadcrumb(at: index)
                            }
                        } label: {
                            Text(navEntry.name)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(
                                    index == viewModel.navStack.count - 1 && viewModel.viewingEntry == nil
                                        ? .primary : .secondary
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if let viewing = viewModel.viewingEntry {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Text(viewing.name)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.primary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func currentFilePath(for entry: TreeEntry) -> String {
        let directoryComponents = viewModel.navStack
            .dropFirst()
            .map(\.name)
        return (directoryComponents + [entry.name]).joined(separator: "/")
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isLoading, viewModel.entries.isEmpty, viewModel.viewingEntry == nil {
            SRHTLoadingStateView(message: "Loading files…")
        } else if let entry = viewModel.viewingEntry, let object = viewModel.viewingObject {
            // Viewing a file
            fileContentView(entry: entry, object: object)
        } else if let error = viewModel.error, viewModel.entries.isEmpty {
            SRHTErrorStateView(
                title: "Couldn't Load Files",
                message: error,
                retryAction: { await viewModel.loadRootTree() }
            )
        } else if !viewModel.entries.isEmpty {
            // Viewing a directory listing
            treeListView
        } else if viewModel.navStack.isEmpty {
            ContentUnavailableView(
                "No Files",
                systemImage: "folder",
                description: Text("This repository could not be loaded.")
            )
        } else {
            ContentUnavailableView(
                "Empty Directory",
                systemImage: "folder",
                description: Text("This directory has no files.")
            )
        }
    }

    // MARK: - File Content View

    @ViewBuilder
    private func fileContentView(entry: TreeEntry, object: GitObject) -> some View {
        switch object {
        case .textBlob(let blob):
            textBlobView(entry: entry, blob: blob)
        case .binaryBlob(let blob):
            binaryBlobView(entry: entry, blob: blob)
        default:
            ContentUnavailableView(
                "Unknown Object",
                systemImage: "questionmark.folder",
                description: Text("Cannot display this object type.")
            )
        }
    }

    // MARK: - Tree List

    private var treeListView: some View {
        let sorted = viewModel.entries.sorted { a, b in
            let aIsTree = a.object?.isTree == true
            let bIsTree = b.object?.isTree == true
            if aIsTree != bIsTree { return aIsTree }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        return List(sorted) { entry in
            TreeEntryRow(entry: entry)
                .contentShape(Rectangle())
                .onTapGesture {
                    Task {
                        await viewModel.navigateInto(entry: entry)
                    }
                }
        }
        .listStyle(.plain)
    }

    // MARK: - Text Blob

    @ViewBuilder
    private func textBlobView(entry: TreeEntry, blob: GitTextBlob) -> some View {
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
                    Text(blob.text ?? "")
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: geometry.size.width,
                               minHeight: geometry.size.height,
                               alignment: .topLeading)
                        .padding()
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    // MARK: - Binary Blob

    @ViewBuilder
    private func binaryBlobView(entry: TreeEntry, blob: GitBinaryBlob) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "doc.zipper")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(entry.name)
                .font(.headline)

            if let size = blob.size {
                Text(formatBytes(size))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Binary file — cannot be displayed inline.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            SRHTShareButton(url: shareURL, target: .file) {
                Label("Share File", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)

            if let content = blob.content, let url = URL(string: content) {
                Link(destination: url) {
                    Label("Open in Safari", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                viewModel.dismissFileView()
            } label: {
                Text("Back to directory")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Tree Entry Row

private struct TreeEntryRow: View {
    let entry: TreeEntry

    var body: some View {
        Label {
            Text(entry.name)
                .font(.body.monospaced())
                .lineLimit(1)
        } icon: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        switch entry.object {
        case .tree: "folder.fill"
        case .unknown: "questionmark.circle"
        default: "doc"
        }
    }

    private var iconColor: Color {
        switch entry.object {
        case .tree: .blue
        case .unknown: .orange
        default: .secondary
        }
    }
}

// MARK: - Ref Picker Sheet

private struct RefPickerSheet: View {
    let viewModel: FileTreeViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task {
                            await viewModel.changeRevspec("HEAD")
                            isPresented = false
                        }
                    } label: {
                        refRow(
                            title: "HEAD",
                            systemImage: "arrow.triangle.branch",
                            color: .blue,
                            isSelected: viewModel.revspec == "HEAD"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if !viewModel.branches.isEmpty {
                    Section("Branches") {
                        ForEach(viewModel.branches, id: \.name) { ref in
                            Button {
                                Task {
                                    await viewModel.changeRevspec(ref.name)
                                    isPresented = false
                                }
                            } label: {
                                refRow(
                                    title: ref.name.replacingOccurrences(of: "refs/heads/", with: ""),
                                    systemImage: "arrow.triangle.branch",
                                    color: .blue,
                                    isSelected: viewModel.revspec == ref.name
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !viewModel.tags.isEmpty {
                    Section("Tags") {
                        ForEach(viewModel.tags, id: \.name) { ref in
                            Button {
                                Task {
                                    await viewModel.changeRevspec(ref.name)
                                    isPresented = false
                                }
                            } label: {
                                refRow(
                                    title: ref.name.replacingOccurrences(of: "refs/tags/", with: ""),
                                    systemImage: "tag",
                                    color: .orange,
                                    isSelected: viewModel.revspec == ref.name
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
            .overlay {
                if viewModel.isLoadingRefs {
                    SRHTLoadingStateView(message: "Loading references…")
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
