import SwiftUI

struct ContributionProfileCard: View {
    let actor: String
    let weeks: [ContributionWeek]
    let stats: ContributionStatsResponse?
    let isLoading: Bool
    let error: String?
    var isIndexedButEmpty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Contribution Activity")
                        .font(.headline)
                    Text(actor)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if isLoading && weeks.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading activity…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let error, weeks.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if isIndexedButEmpty || weeks.isEmpty || stats?.totalEvents == 0 {
                Text("Contribution activity may still be indexing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ContributionScrollableHeatmap(
                    weeks: weeks,
                    squareSize: 10,
                    spacing: 3,
                    showsWeekdayLabels: false,
                    showsMonthLabels: false
                )

                ContributionLegendView()

                if let stats {
                    HStack(spacing: 14) {
                        ContributionMetricChip(value: "\(stats.totalEvents)", title: "Events")
                        ContributionMetricChip(value: "\(stats.activeDays)", title: "Days")
                        ContributionMetricChip(value: "\(stats.longestStreak)", title: "Streak")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ContributionScrollableHeatmap: View {
    let weeks: [ContributionWeek]
    let squareSize: CGFloat
    let spacing: CGFloat
    let showsWeekdayLabels: Bool
    let showsMonthLabels: Bool

    @State private var didApplyInitialScroll = false

    private let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    if showsMonthLabels {
                        HStack(spacing: spacing) {
                            if showsWeekdayLabels {
                                Color.clear
                                    .frame(width: 10)
                            }

                            ForEach(Array(weeks.enumerated()), id: \.element.startDate) { index, week in
                                Text(monthLabel(for: week, index: index))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: squareSize, alignment: .leading)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        if showsWeekdayLabels {
                            VStack(alignment: .trailing, spacing: spacing) {
                                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 10, height: squareSize, alignment: .center)
                                }
                            }
                        }

                        HStack(alignment: .top, spacing: spacing) {
                            ForEach(weeks, id: \.startDate) { week in
                                VStack(spacing: spacing) {
                                    ForEach(week.days) { day in
                                        ContributionDayCell(day: day, size: squareSize)
                                    }
                                }
                                .id(week.startDate)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear {
                guard !didApplyInitialScroll, let lastWeek = weeks.last?.startDate else { return }
                didApplyInitialScroll = true

                DispatchQueue.main.async {
                    proxy.scrollTo(lastWeek, anchor: .trailing)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func monthLabel(for week: ContributionWeek, index: Int) -> String {
        let month = week.startDate.formatted(.dateTime.month(.abbreviated))
        if index == 0 {
            return month
        }

        let previousMonth = weeks[index - 1].startDate.formatted(.dateTime.month(.abbreviated))
        return previousMonth == month ? "" : month
    }
}

private struct ContributionDayCell: View {
    let day: ContributionDay
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(day.intensity.color)
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.primary.opacity(day.intensity == .empty ? 0.08 : 0), lineWidth: 0.5)
            }
            .accessibilityLabel(day.accessibilityLabel)
    }
}


private struct ContributionMetricChip: View {
    let value: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ContributionLegendView: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Less")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(ContributionIntensity.allCases, id: \.rawValue) { intensity in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(intensity.color)
                    .frame(width: 12, height: 12)
            }

            Text("More")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension ContributionIntensity {
    var color: Color {
        switch self {
        case .empty:
            Color(uiColor: .secondarySystemFill)
        case .level1:
            Color(red: 0.82, green: 0.92, blue: 0.83)
        case .level2:
            Color(red: 0.58, green: 0.83, blue: 0.61)
        case .level3:
            Color(red: 0.25, green: 0.69, blue: 0.36)
        case .level4:
            Color(red: 0.12, green: 0.47, blue: 0.21)
        }
    }
}

private extension ContributionDay {
    var accessibilityLabel: String {
        let contributionLabel = count == 1 ? "1 contribution" : "\(count) contributions"
        return "\(date.formatted(date: .long, time: .omitted)): \(contributionLabel), score \(score.formatted(.number.precision(.fractionLength(0...2))))"
    }
}
