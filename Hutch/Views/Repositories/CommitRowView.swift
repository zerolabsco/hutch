import SwiftUI

struct CommitRowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    let commit: CommitSummary
    let repository: RepositorySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(commit.title)
                .font(.subheadline)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(commit.shortId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Text(commit.author.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(commit.author.time.relativeDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let url = SRHTWebURL.commit(repository: repository, commitId: commit.id) {
                Button {
                    openURL(url)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
            }

            Button {
                appState.copyToPasteboard(commit.id, label: "commit SHA")
            } label: {
                Label("Copy Full SHA", systemImage: "doc.on.doc")
            }

            Button {
                appState.copyToPasteboard(commit.shortId, label: "short commit SHA")
            } label: {
                Label("Copy Short SHA", systemImage: "doc.on.doc.fill")
            }
        }
    }
}
