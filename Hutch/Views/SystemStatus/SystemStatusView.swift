import SwiftUI

struct SystemStatusView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: SystemStatusViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading system status…")
            }
        }
        .navigationTitle("System Status")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let vm: SystemStatusViewModel
            if let viewModel {
                vm = viewModel
            } else {
                let newViewModel = SystemStatusViewModel(repository: appState.systemStatusRepository)
                viewModel = newViewModel
                vm = newViewModel
            }

            await vm.load()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: SystemStatusViewModel) -> some View {
        List {
            if viewModel.isShowingStaleData, let staleDataMessage = viewModel.staleDataMessage {
                Section {
                    Label(staleDataMessage, systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .themedRow()
                }
            }

            if let snapshot = viewModel.snapshot {
                summarySection(snapshot)
                servicesSection(snapshot)
                activeIncidentsSection(snapshot.activeIncidents)
            }

            recentIncidentsSection(viewModel.recentIncidents)
        }
        .themedList()
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.load(forceRefresh: true)
        }
        .overlay {
            if viewModel.isLoading && !viewModel.hasContent {
                SRHTLoadingStateView(message: "Loading system status…")
            } else if !viewModel.isLoading && !viewModel.hasContent, let errorMessage = viewModel.errorMessage {
                SRHTErrorStateView(
                    title: "Couldn’t Load System Status",
                    message: errorMessage,
                    retryAction: { await viewModel.load(forceRefresh: true) }
                )
            } else if !viewModel.isLoading && !viewModel.hasContent {
                ContentUnavailableView(
                    "No Status Data",
                    systemImage: "server.rack",
                    description: Text("System status information is not available right now.")
                )
            }
        }
        .connectivityOverlay(hasContent: viewModel.hasContent) {
            await viewModel.load(forceRefresh: true)
        }
        .srhtErrorBanner(error: Binding(
            get: { viewModel.errorMessage },
            set: { viewModel.errorMessage = $0 }
        ))
    }

    @ViewBuilder
    private func summarySection(_ snapshot: SystemStatusSnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: snapshot.hasDisruption ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(snapshot.hasDisruption ? .orange : .green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.overallStatusText)
                            .font(.headline)
                        Text("Updated \(snapshot.lastUpdated.relativeDescription)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Link(destination: SRHTWebURL.status) {
                    Label("Open status.sr.ht", systemImage: "safari")
                }
                .font(.subheadline.weight(.medium))
            }
            .padding(.vertical, 4)
            .themedRow()
        }
    }

    @ViewBuilder
    private func servicesSection(_ snapshot: SystemStatusSnapshot) -> some View {
        Section("Services") {
            ForEach(snapshot.services) { service in
                HStack(spacing: 12) {
                    StatusLevelBadge(level: service.status)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.name)
                            .font(.subheadline.weight(.medium))
                        Text(service.status.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            .themedRow()
        }
    }

    @ViewBuilder
    private func activeIncidentsSection(_ incidents: [StatusIncident]) -> some View {
        if !incidents.isEmpty {
            Section("Active Incidents") {
                ForEach(incidents) { incident in
                    incidentRow(incident)
                }
                .themedRow()
            }
        }
    }

    @ViewBuilder
    private func recentIncidentsSection(_ incidents: [StatusIncident]) -> some View {
        Section("Recent Incidents") {
            if incidents.isEmpty {
                ContentUnavailableView(
                    "No Recent Incidents",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("The status feed didn’t return any recent incidents.")
                )
                .themedRow()
            } else {
                ForEach(incidents) { incident in
                    incidentRow(incident)
                }
                .themedRow()
            }
        }
    }

    @ViewBuilder
    private func incidentRow(_ incident: StatusIncident) -> some View {
        if let url = incident.url {
            Link(destination: url) {
                StatusIncidentRow(incident: incident)
            }
        } else {
            StatusIncidentRow(incident: incident)
        }
    }
}

private struct StatusIncidentRow: View {
    let incident: StatusIncident

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(incident.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if incident.url != nil {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(timestampText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let summary = incident.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }

    private var timestampText: String {
        if let updatedAt = incident.updatedAt {
            return "Published \(incident.publishedAt.relativeDescription) • Updated \(updatedAt.relativeDescription)"
        }
        return "Published \(incident.publishedAt.relativeDescription)"
    }
}

private struct StatusLevelBadge: View {
    let level: StatusLevel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(level.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14), in: Capsule())
    }

    private var color: Color {
        switch level {
        case .operational:
            .green
        case .degraded:
            .orange
        case .majorOutage:
            .red
        case .maintenance:
            .blue
        case .unknown:
            .gray
        }
    }
}
