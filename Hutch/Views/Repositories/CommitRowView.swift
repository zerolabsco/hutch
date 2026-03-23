import SwiftUI
import UIKit

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
        .contextMenu {
            Button {
                UIPasteboard.general.string = commit.id
            } label: {
                Label("Copy Full SHA", systemImage: "doc.on.doc")
            }

            Button {
                UIPasteboard.general.string = commit.shortId
            } label: {
                Label("Copy Short SHA", systemImage: "doc.on.doc.fill")
            }
        }
    }
}
