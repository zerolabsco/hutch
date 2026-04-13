import SwiftUI

struct SystemStatusSummaryRow: View {
    let title: String
    let snapshot: SystemStatusSnapshot?
    let isLoading: Bool
    let errorMessage: String?
    let isShowingStaleData: Bool

    init(
        title: String = "System Status",
        snapshot: SystemStatusSnapshot?,
        isLoading: Bool = false,
        errorMessage: String? = nil,
        isShowingStaleData: Bool = false
    ) {
        self.title = title
        self.snapshot = snapshot
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.isShowingStaleData = isShowingStaleData
    }

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(primaryMessage)
                    .font(.caption)
                    .foregroundStyle(primaryMessageColor)
                    .lineLimit(2)

                if let metadataMessage {
                    Text(metadataMessage)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if isLoading && snapshot == nil {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
    }

    private var primaryMessage: String {
        if let snapshot {
            let summary = snapshot.hasDisruption ? snapshot.bannerSummary : snapshot.overallStatusText
            return "\(summary) • Updated \(snapshot.lastUpdated.relativeDescription)"
        }
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        if isLoading {
            return "Loading system status…"
        }
        return "System status is unavailable right now."
    }

    private var metadataMessage: String? {
        if snapshot != nil, isShowingStaleData {
            return "Showing saved data"
        }
        if errorMessage != nil {
            return "Open System Status to retry."
        }
        return nil
    }

    private var iconName: String {
        if let snapshot {
            return snapshot.hasDisruption ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        }
        if errorMessage != nil {
            return "exclamationmark.triangle"
        }
        return "server.rack"
    }

    private var iconColor: Color {
        if let snapshot {
            return snapshot.hasDisruption ? .orange : .green
        }
        if errorMessage != nil {
            return .secondary
        }
        return .secondary
    }

    private var primaryMessageColor: Color {
        if snapshot != nil {
            return .secondary
        }
        if errorMessage != nil {
            return .secondary
        }
        return .secondary
    }
}
