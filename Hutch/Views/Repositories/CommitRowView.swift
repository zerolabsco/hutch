import SwiftUI

struct CommitRowView: View {
    let commit: CommitSummary

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
    }
}
