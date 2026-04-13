import SwiftUI

struct CommitDetailView: View {
    let commitSummary: CommitSummary
    let repository: RepositorySummary

    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @State private var viewModel: CommitDetailViewModel?

    var body: some View {
        Group {
            if let viewModel {
                commitContent(viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(commitSummary.shortId)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    if let commitURL = SRHTWebURL.commit(repository: repository, commitId: commitSummary.id) {
                        Button {
                            openURL(commitURL)
                        } label: {
                            Label("Open in Browser", systemImage: "safari")
                        }

                        Button {
                            appState.copyToPasteboard(commitURL.absoluteString, label: "commit URL")
                        } label: {
                            Label("Copy URL", systemImage: "doc.on.doc")
                        }
                    }

                    Button {
                        appState.copyToPasteboard(commitSummary.id, label: "commit SHA")
                    } label: {
                        Label("Copy Full SHA", systemImage: "doc.on.doc")
                    }

                    Button {
                        appState.copyToPasteboard(commitSummary.shortId, label: "short commit SHA")
                    } label: {
                        Label("Copy Short SHA", systemImage: "number")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Commit actions")

                SRHTShareButton(url: SRHTWebURL.commit(repository: repository, commitId: commitSummary.id), target: .commit) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .task {
            if viewModel == nil {
                let vm = CommitDetailViewModel(
                    repositoryRid: repository.rid,
                    service: repository.service,
                    commitId: commitSummary.id,
                    client: appState.client
                )
                viewModel = vm
                await vm.loadCommit()
            }
        }
    }

    @ViewBuilder
    private func commitContent(_ viewModel: CommitDetailViewModel) -> some View {
        if viewModel.isLoading {
            ProgressView()
        } else if let error = viewModel.error {
            ContentUnavailableView {
                Label("Error", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") {
                    Task { await viewModel.loadCommit() }
                }
            }
        } else if let commit = viewModel.commit {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Header
                    commitHeader(commit)

                    sectionDivider

                    // Message
                    commitMessage(commit)

                    // Trailers
                    if !commit.trailers.isEmpty {
                        sectionDivider
                        trailersSection(commit.trailers)
                    }

                    // Parents
                    if !commit.parents.isEmpty {
                        sectionDivider
                        parentsSection(commit.parents)
                    }

                    // Diff
                    if let diff = commit.diff, !diff.isEmpty {
                        sectionDivider
                        diffSection(diff)
                    }

                    // Tree
                    if let tree = commit.tree, !tree.entries.results.isEmpty {
                        sectionDivider
                        treeSection(tree.entries.results)
                    }
                }
            }
            .navigationDestination(for: ParentCommit.self) { parent in
                CommitDetailView(
                    commitSummary: CommitSummary(
                        id: parent.id,
                        shortId: parent.shortId,
                        author: CommitAuthor(name: parent.author.name, email: nil, time: .now),
                        message: ""
                    ),
                    repository: repository
                )
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func commitHeader(_ commit: CommitDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Full hash — tappable to copy
            Button {
                appState.copyToPasteboard(commit.id, label: "commit SHA")
            } label: {
                HStack(spacing: 4) {
                    Text(commit.id)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }

            // Author
            HStack {
                Label(commit.author.name, systemImage: "person")
                Spacer()
                Text(commit.author.time.relativeDescription)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            // Committer (if different from author)
            if commit.committer.name != commit.author.name
                || commit.committer.email != commit.author.email {
                HStack {
                    Label(commit.committer.name, systemImage: "person.badge.shield.checkmark")
                    Spacer()
                    Text(commit.committer.time.relativeDescription)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Message

    @ViewBuilder
    private func commitMessage(_ commit: CommitDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(commit.title)
                .font(.headline)

            if let body = commit.body {
                Text(body)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Trailers

    @ViewBuilder
    private func trailersSection(_ trailers: [CommitTrailer]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trailers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(trailers) { trailer in
                HStack(alignment: .top, spacing: 4) {
                    Text("\(trailer.name):")
                        .font(.subheadline.monospaced().weight(.medium))
                    Text(trailer.value)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Parents

    @ViewBuilder
    private func parentsSection(_ parents: [ParentCommit]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Parents")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(parents) { parent in
                NavigationLink(value: parent) {
                    HStack {
                        Text(parent.shortId)
                            .font(.subheadline.monospaced())
                        Text(parent.author.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Diff

    @ViewBuilder
    private func diffSection(_ diff: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diff")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal)
                .padding(.top)

            DiffView(diff: invertDiff(diff))
                .padding(.bottom)
        }
    }

    /// The sr.ht API returns diffs comparing current→parent (inverted).
    /// This swaps +/- prefixes so the diff reads as parent→current.
    private func invertDiff(_ diff: String) -> String {
        diff.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let s = String(line)
                if s.hasPrefix("@@") || s.hasPrefix("diff ") || s.hasPrefix("index ") {
                    return s
                }
                if s.hasPrefix("---") {
                    return "+++" + s.dropFirst(3)
                }
                if s.hasPrefix("+++") {
                    return "---" + s.dropFirst(3)
                }
                if s.hasPrefix("+") {
                    return "-" + s.dropFirst(1)
                }
                if s.hasPrefix("-") {
                    return "+" + s.dropFirst(1)
                }
                return s
            }
            .joined(separator: "\n")
    }

    // MARK: - Tree

    @ViewBuilder
    private func treeSection(_ entries: [CommitTreeEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tree")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Image(systemName: treeEntryIcon(for: entry))
                        .foregroundStyle(treeEntryColor(for: entry))
                        .frame(width: 20)
                    Text(entry.name)
                        .font(.subheadline.monospaced())
                    Spacer()
                    if let obj = entry.object, let shortId = obj.shortId {
                        Text(shortId)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var sectionDivider: some View {
        Divider().padding(.horizontal)
    }

    private func treeEntryIcon(for entry: CommitTreeEntry) -> String {
        guard let type = entry.object?.type else {
            return "doc"
        }
        switch type {
        case "tree":   return "folder"
        case "blob":   return "doc.text"
        case "tag":    return "tag"
        case "commit": return "arrow.triangle.branch"
        default:       return "doc"
        }
    }

    private func treeEntryColor(for entry: CommitTreeEntry) -> Color {
        guard let type = entry.object?.type else {
            return .secondary
        }
        switch type {
        case "tree":   return .blue
        case "blob":   return .secondary
        case "tag":    return .orange
        case "commit": return .purple
        default:       return .secondary
        }
    }
}
