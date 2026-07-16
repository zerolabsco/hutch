import SwiftUI

struct ActivityView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: ActivityViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading Activity…")
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let model = viewModel ?? ActivityViewModel(client: appState.client)
            viewModel = model
            await model.loadIfNeeded()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: ActivityViewModel) -> some View {
        List {
            ForEach(viewModel.events) { event in
                NavigationLink {
                    TicketDetailView(
                        ownerUsername: event.ownerUsername,
                        trackerName: event.trackerName,
                        trackerId: event.trackerID,
                        trackerRid: event.trackerRID,
                        ticketId: event.ticketID
                    )
                } label: {
                    ActivityRow(event: event)
                }
                .themedRow()
            }

            if viewModel.hasMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .themedRow()
                .task { await viewModel.loadMore() }
            }
        }
        .themedList()
        .listStyle(.plain)
        .refreshable { await viewModel.load() }
        .overlay {
            if viewModel.isLoading, viewModel.events.isEmpty {
                SRHTLoadingStateView(message: "Loading Activity…")
            } else if let error = viewModel.error, viewModel.events.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Activity",
                    message: error,
                    retryAction: { await viewModel.load() }
                )
            } else if viewModel.events.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "bell",
                    description: Text("Ticket activity you are subscribed to or involved in appears here.")
                )
            }
        }
    }
}

private struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.ticketSubject)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            Text("\(event.summary) • \(event.created.relativeDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(event.trackerOwner.canonicalName)/\(event.trackerName) #\(event.ticketID)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.ticketSubject), \(event.summary), \(event.created.relativeDescription)")
    }
}
