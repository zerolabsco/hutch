import SwiftUI

struct RepositoryRowView: View {
    let repository: RepositorySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(repository.name)
                    .font(.headline)

                Spacer()

                if repository.service == .hg {
                    Text("HG")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.15), in: Capsule())
                        .foregroundStyle(.cyan)
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
                if let head = repository.head {
                    Label(head.name, systemImage: "arrow.triangle.branch")
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
