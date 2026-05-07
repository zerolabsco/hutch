import SwiftUI

struct StaleCacheStatusRow: View {
    let metadata: CacheEntryMetadata
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: metadata.isExpired() ? "clock.badge.exclamationmark" : "clock")
                .foregroundStyle(.secondary)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .themedRow()
    }

    private var statusText: String {
        if isRefreshing {
            return "Showing cached data. Refreshing…"
        }
        if metadata.isExpired() {
            return "Showing cached data. Last updated \(metadata.fetchedAt.relativeDescription)."
        }
        return "Last updated \(metadata.fetchedAt.relativeDescription)"
    }
}
