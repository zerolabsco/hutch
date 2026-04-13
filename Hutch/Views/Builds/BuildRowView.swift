import SwiftUI

struct BuildRowView: View, Equatable {
    let job: JobSummary

    var body: some View {
        HStack(spacing: 12) {
            JobStatusIcon(status: job.status)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.displayLabel)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let image = job.image {
                        Text(image)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(job.created.relativeDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if !job.tasks.isEmpty {
                    TaskProgressView(tasks: job.tasks)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct JobStatusBadge: View {
    let status: JobStatus

    var body: some View {
        HStack(spacing: 4) {
            JobStatusIcon(status: status)
                .frame(width: 12, height: 12)
            Text(status.displayTitle)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemFill), in: Capsule())
    }
}

extension JobStatus {
    var displayTitle: String {
        switch self {
        case .pending:
            "Pending"
        case .queued:
            "Queued"
        case .running:
            "Running"
        case .success:
            "Succeeded"
        case .failed:
            "Failed"
        case .cancelled:
            "Cancelled"
        case .timeout:
            "Timed Out"
        }
    }
}

// MARK: - Job Status Icon

struct JobStatusIcon: View {
    let status: JobStatus

    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(color)
            .symbolEffect(.pulse, isActive: status == .running)
    }

    private var iconName: String {
        switch status {
        case .success:              "checkmark.circle.fill"
        case .failed, .timeout:     "xmark.circle.fill"
        case .running:              "arrow.trianglehead.2.clockwise.rotate.90"
        case .queued:               "clock.fill"
        case .pending:              "circle.dashed"
        case .cancelled:            "minus.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .success:              .green
        case .failed, .timeout:     .red
        case .running:              .yellow
        case .queued:               .orange
        case .pending, .cancelled:  .gray
        }
    }
}

// MARK: - Task Progress

struct TaskProgressView: View {
    let tasks: [JobTaskSummary]

    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: progress, total: 1.0)
                .tint(progressColor)
                .frame(maxWidth: 80)

            Text("\(completedCount)/\(tasks.count) tasks")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var completedCount: Int {
        tasks.filter { $0.status == .success }.count
    }

    private var progress: Double {
        tasks.isEmpty ? 0 : Double(completedCount) / Double(tasks.count)
    }

    private var progressColor: Color {
        if tasks.contains(where: { $0.status == .failed }) {
            return .red
        }
        if completedCount == tasks.count {
            return .green
        }
        return .blue
    }
}
