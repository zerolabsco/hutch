import SwiftUI
import WidgetKit

struct NeedsAttentionEntry: TimelineEntry {
    let date: Date
    let snapshot: NeedsAttentionSnapshot?
}

struct NeedsAttentionTimelineProvider: TimelineProvider {
    func placeholder(in _: Context) -> NeedsAttentionEntry {
        NeedsAttentionEntry(
            date: .now,
            snapshot: NeedsAttentionSnapshot(
                unreadInboxThreads: 3,
                assignedOpenTickets: 2,
                failedBuilds: 1,
                updatedAt: .now
            )
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (NeedsAttentionEntry) -> Void) {
        completion(
            NeedsAttentionEntry(
                date: .now,
                snapshot: NeedsAttentionSnapshotStore.load()
            )
        )
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<NeedsAttentionEntry>) -> Void) {
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 20, to: .now) ?? .now.addingTimeInterval(1200)
        let entry = NeedsAttentionEntry(date: .now, snapshot: NeedsAttentionSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct NeedsAttentionWidget: Widget {
    static let kind = NeedsAttentionWidgetConfiguration.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NeedsAttentionTimelineProvider()) { entry in
            NeedsAttentionWidgetView(entry: entry)
        }
        .configurationDisplayName("Needs Attention")
        .description("Unread inbox threads, assigned tickets, and failed builds.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct NeedsAttentionWidgetView: View {
    let entry: NeedsAttentionEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.hasAnyData {
                if snapshot.allCountsAreZero {
                    clearState
                } else {
                    switch family {
                    case .systemMedium:
                        mediumView(snapshot: snapshot)
                    case .systemLarge:
                        largeView(snapshot: snapshot)
                    default:
                        smallView(snapshot: snapshot)
                    }
                }
            } else {
                fallbackState
            }
        }
        .widgetURL(URL(string: "hutch://home"))
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private func smallView(snapshot: NeedsAttentionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                compactMetric(
                    count: snapshot.unreadInboxThreads,
                    label: "Unread",
                    tint: unreadTint(for: snapshot.unreadInboxThreads)
                )
                compactMetric(count: snapshot.assignedOpenTickets, label: "Assigned")
                compactMetric(
                    count: snapshot.failedBuilds,
                    label: "Failed",
                    tint: failedTint(for: snapshot.failedBuilds)
                )
            }
            Spacer(minLength: 0)
        }
        .padding()
    }

    private func mediumView(snapshot: NeedsAttentionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                metricColumn(
                    count: snapshot.unreadInboxThreads,
                    label: "Unread",
                    systemImage: "tray",
                    tint: unreadTint(for: snapshot.unreadInboxThreads)
                )
                metricColumn(
                    count: snapshot.assignedOpenTickets,
                    label: "Assigned",
                    systemImage: "ticket"
                )
                metricColumn(
                    count: snapshot.failedBuilds,
                    label: "Failed",
                    systemImage: "hammer",
                    tint: failedTint(for: snapshot.failedBuilds)
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private func largeView(snapshot: NeedsAttentionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            metricRow(
                count: snapshot.unreadInboxThreads,
                label: "Unread threads",
                systemImage: "tray",
                tint: unreadTint(for: snapshot.unreadInboxThreads)
            )
            metricRow(
                count: snapshot.assignedOpenTickets,
                label: "Assigned tickets",
                systemImage: "ticket"
            )
            metricRow(
                count: snapshot.failedBuilds,
                label: "Failed builds",
                systemImage: "hammer",
                tint: failedTint(for: snapshot.failedBuilds)
            )
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var clearState: some View {
        Group {
            switch family {
            case .systemSmall:
                smallClearState
            case .systemMedium:
                mediumClearState
            case .systemLarge:
                largeClearState
            default:
                smallClearState
            }
        }
    }

    private var fallbackState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 0)
            Text("Open Hutch")
                .font(.title3.weight(.semibold))
            Text("Unable to load recent counts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func compactMetric(count: Int?, label: String, tint: Color = .primary) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(displayCount(count))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func metricColumn(count: Int?, label: String, systemImage: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, alignment: .leading)
                    .padding(.trailing, 4)
                Text(displayCount(count))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(tint)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(height: 16, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func metricRow(count: Int?, label: String, systemImage: String, tint: Color = .primary) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24, alignment: .leading)
            Text(displayCount(count))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var smallClearState: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(clearStateTint)
            Text("0 items")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var mediumClearState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(clearStateTint)
            Text("Nothing to review")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
    }

    private var largeClearState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(clearStateTint)
            Text("Nothing to review")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
    }

    private var clearStateTint: Color {
        Color(.systemGreen).opacity(0.75)
    }

    private func displayCount(_ count: Int?) -> String {
        guard let count else { return "—" }
        return "\(count)"
    }

    private func unreadTint(for count: Int?) -> Color {
        guard let count, count > 0 else { return .primary }
        return .blue
    }

    private func failedTint(for count: Int?) -> Color {
        guard let count else { return .primary }
        return count > 0 ? .red : .green
    }
}

@main
struct HutchWidgets: WidgetBundle {
    var body: some Widget {
        NeedsAttentionWidget()
    }
}
