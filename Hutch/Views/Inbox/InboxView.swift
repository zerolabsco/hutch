import SwiftUI

// Legacy wrapper kept temporarily so stale references continue to compile while
// the app transitions from Inbox to Work.
struct InboxView: View {
    var body: some View {
        WorkView()
    }
}

struct InboxThreadRow: View {
    let thread: InboxThreadSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(thread.isUnread ? .blue : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(thread.displaySubject)
                    .font(.subheadline.weight(thread.isUnread ? .semibold : .medium))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if thread.containsPatch {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(thread.metadataLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(thread.lastActivityAt.relativeDescription)
                .font(.caption)
                .foregroundStyle(.tertiary.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
