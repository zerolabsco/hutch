import SwiftUI

struct RepositoryRowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    let repository: RepositorySummary
    let buildStatus: RepositoryBuildStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(repository.name)
                    .font(.headline)

                Spacer()

                RepositoryForgeBadge(service: repository.service)

                if buildStatus != .none {
                    RepositoryBuildStatusIndicator(status: buildStatus)
                }
                VisibilityBadge(visibility: repository.visibility)
            }

            Text(repository.owner.canonicalName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let description = repository.description,
               !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if let defaultBranchName = repository.defaultBranchName {
                    Label(defaultBranchName, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(repository.updated.relativeDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let url = SRHTWebURL.repository(repository) {
                Button {
                    openURL(url)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
            }

            Button {
                if let url = SRHTWebURL.repository(repository)?.absoluteString {
                    appState.copyToPasteboard(url, label: "repository URL")
                }
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }

            Button {
                if let url = SRHTWebURL.httpsCloneURL(repository) {
                    appState.copyToPasteboard(url, label: "HTTPS clone URL")
                }
            } label: {
                Label("Copy HTTPS URL", systemImage: "doc.on.doc")
            }

            Button {
                appState.copyToPasteboard(SRHTWebURL.sshCloneURL(repository), label: "SSH clone URL")
            } label: {
                Label("Copy SSH URL", systemImage: "terminal")
            }

            Button {
                appState.copyToPasteboard(repository.rid, label: "repository RID")
            } label: {
                Label("Copy RID", systemImage: "number")
            }
        }
    }
}

private struct RepositoryBuildStatusIndicator: View {
    let status: RepositoryBuildStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                Circle()
                    .strokeBorder(.primary.opacity(0.08))
            }
            .accessibilityLabel(accessibilityLabel)
    }

    private var color: Color {
        switch status {
        case .success:
            .green
        case .failed:
            .red
        case .running:
            .orange
        case .none:
            .clear
        }
    }

    private var accessibilityLabel: String {
        switch status {
        case .success:
            "Latest build succeeded"
        case .failed:
            "Latest build failed"
        case .running:
            "Latest build is running"
        case .none:
            "No recent builds"
        }
    }
}

// MARK: - VisibilityBadge

struct VisibilityBadge: View {
    let visibility: Visibility

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch visibility {
        case .public:   "PUBLIC"
        case .unlisted: "UNLISTED"
        case .private:  "PRIVATE"
        }
    }

    private var color: Color {
        switch visibility {
        case .public:   .green
        case .unlisted: .orange
        case .private:  .red
        }
    }
}
