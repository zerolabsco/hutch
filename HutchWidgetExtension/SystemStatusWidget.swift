import SwiftUI
import WidgetKit

struct SystemStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: SystemStatusWidgetSnapshot?
}

struct SystemStatusTimelineProvider: TimelineProvider {
    func placeholder(in _: Context) -> SystemStatusEntry {
        SystemStatusEntry(
            date: .now,
            snapshot: SystemStatusWidgetSnapshot(
                services: [
                    .init(id: "git", name: "git.sr.ht", status: "Operational", requiresAttention: false),
                    .init(id: "builds", name: "builds.sr.ht", status: "Operational", requiresAttention: false),
                    .init(id: "lists", name: "lists.sr.ht", status: "Operational", requiresAttention: false),
                    .init(id: "todo", name: "todo.sr.ht", status: "Operational", requiresAttention: false),
                    .init(id: "meta", name: "meta.sr.ht", status: "Operational", requiresAttention: false),
                    .init(id: "hg", name: "hg.sr.ht", status: "Operational", requiresAttention: false),
                ],
                hasDisruption: false,
                overallStatusText: "All monitored services operational",
                bannerSummary: "",
                updatedAt: .now
            )
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (SystemStatusEntry) -> Void) {
        completion(
            SystemStatusEntry(
                date: .now,
                snapshot: SystemStatusWidgetSnapshotStore.load()
            )
        )
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<SystemStatusEntry>) -> Void) {
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        let entry = SystemStatusEntry(date: .now, snapshot: SystemStatusWidgetSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct SystemStatusWidget: Widget {
    static let kind = SystemStatusWidgetConfiguration.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SystemStatusTimelineProvider()) { entry in
            SystemStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("SourceHut Status")
        .description("Current status of SourceHut services at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct SystemStatusWidgetView: View {
    let entry: SystemStatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !snapshot.services.isEmpty {
                switch family {
                case .systemMedium:
                    mediumView(snapshot: snapshot)
                default:
                    smallView(snapshot: snapshot)
                }
            } else {
                fallbackView
            }
        }
        .widgetURL(URL(string: "hutch://status"))
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private func smallView(snapshot: SystemStatusWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: snapshot.hasDisruption ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(snapshot.hasDisruption ? .orange : .green)
                Spacer()
            }

            Text(snapshot.hasDisruption ? snapshot.bannerSummary : "All Clear")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Spacer(minLength: 0)

            if snapshot.hasDisruption {
                let disrupted = snapshot.services.filter(\.requiresAttention)
                Text(disrupted.map(\.name).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("\(snapshot.services.count) services monitored")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func mediumView(snapshot: SystemStatusWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: snapshot.hasDisruption ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(snapshot.hasDisruption ? .orange : .green)

                Text(snapshot.hasDisruption ? snapshot.bannerSummary : "All Services Operational")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer()
            }

            Divider()

            let columns = Array(snapshot.services.prefix(8))
            let half = (columns.count + 1) / 2
            let leftColumn = Array(columns.prefix(half))
            let rightColumn = Array(columns.suffix(from: half))

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(leftColumn) { service in
                        serviceRow(service)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rightColumn) { service in
                        serviceRow(service)
                    }
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func serviceRow(_ service: SystemStatusWidgetSnapshot.ServiceEntry) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(service.requiresAttention ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(service.name)
                .font(.caption2)
                .foregroundStyle(service.requiresAttention ? .primary : .secondary)
                .lineLimit(1)
        }
    }

    private var fallbackView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Text("Open Hutch")
                .font(.title3.weight(.semibold))
            Text("Sign in to load system status.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
