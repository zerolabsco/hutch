import SwiftUI
import WidgetKit

struct NeedsAttentionEntry: TimelineEntry {
    let date: Date
    let snapshot: NeedsAttentionSnapshot?
}

struct NeedsAttentionTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NeedsAttentionEntry {
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

    func getSnapshot(in context: Context, completion: @escaping (NeedsAttentionEntry) -> Void) {
        completion(
            NeedsAttentionEntry(
                date: .now,
                snapshot: NeedsAttentionSnapshotStore.load()
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NeedsAttentionEntry>) -> Void) {
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
        .supportedFamilies([.systemSmall, .systemMedium])
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Hutch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Needs Attention")
                .font(.headline)
                .lineLimit(1)
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
        VStack(alignment: .leading, spacing: 18) {
            header
                .padding(.top, 6)
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

    private var clearState: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Spacer(minLength: 0)
            Text("All clear")
                .font(.title3.weight(.semibold))
            Text("No unread threads, assigned tickets, or failed builds.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }

    private var fallbackState: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
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
