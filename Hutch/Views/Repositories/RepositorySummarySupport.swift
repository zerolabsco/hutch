import SwiftUI

enum RepositoryBuildStatus: Sendable {
    case success
    case failed
    case running
    case none
}

struct RepositoryCloneURLs {
    let readOnly: String
    let readWrite: String
}

func repositoryCloneURLs(for repository: RepositorySummary) -> RepositoryCloneURLs {
    let owner = repository.owner.canonicalName
    let name = repository.name

    switch repository.service {
    case .git:
        return RepositoryCloneURLs(
            readOnly: "https://git.sr.ht/\(owner)/\(name)",
            readWrite: "git@git.sr.ht:\(owner)/\(name)"
        )
    case .hg:
        return RepositoryCloneURLs(
            readOnly: "https://hg.sr.ht/\(owner)/\(name)",
            readWrite: "ssh://hg@hg.sr.ht/\(owner)/\(name)"
        )
    default:
        return RepositoryCloneURLs(
            readOnly: "https://\(repository.service.rawValue).sr.ht/\(owner)/\(name)",
            readWrite: ""
        )
    }
}

func repositoryVisibilityLabel(_ visibility: Visibility) -> String {
    switch visibility {
    case .publicVisibility:
        return "Public"
    case .unlisted:
        return "Unlisted"
    case .privateVisibility:
        return "Private"
    }
}

func repositoryForgeLabel(_ service: SRHTService) -> String {
    switch service {
    case .git:
        return "GIT"
    case .hg:
        return "HG"
    default:
        return service.rawValue.uppercased()
    }
}

func repositoryPrimaryBranchLabel(for repository: RepositorySummary, hgTipBranch: String? = nil) -> String? {
    switch repository.service {
    case .git:
        return repository.defaultBranchName
    case .hg:
        return hgTipBranch ?? repository.defaultBranchName ?? "tip"
    default:
        return repository.defaultBranchName
    }
}

struct SummaryMetadataRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SummaryDetailRow: View {
    let label: String
    let value: String
    var monospace: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospace ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
        }
    }
}

struct RepositoryForgeBadge: View {
    let service: SRHTService

    var body: some View {
        Text(repositoryForgeLabel(service))
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch service {
        case .git:
            .indigo
        case .hg:
            .cyan
        default:
            .secondary
        }
    }
}
