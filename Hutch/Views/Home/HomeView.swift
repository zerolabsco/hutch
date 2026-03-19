import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: HomeViewModel?
    private let previewLimit = 4
    private let projectPreviewLimit = 3

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading Home…")
            }
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    InboxView()
                } label: {
                    HomeInboxToolbarIcon(hasUnreadThreads: viewModel?.hasUnreadInboxThreads == true)
                }
            }
        }
        .task {
            if viewModel == nil, let currentUser = appState.currentUser {
                let vm = HomeViewModel(currentUser: currentUser, client: appState.client)
                viewModel = vm
                await vm.loadDashboard()
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: HomeViewModel) -> some View {
        List {
            projectsSection(viewModel)
            assignedTicketsSection(viewModel)
            recentBuildsSection(viewModel)
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.isLoadingProjects && viewModel.isLoadingAssignedTickets && viewModel.isLoadingRecentBuilds &&
                viewModel.projects.isEmpty && viewModel.assignedTickets.isEmpty && viewModel.recentBuilds.isEmpty {
                SRHTLoadingStateView(message: "Loading Home…")
            } else if !viewModel.isLoadingProjects && !viewModel.isLoadingAssignedTickets && !viewModel.isLoadingRecentBuilds &&
                        viewModel.projects.isEmpty && viewModel.assignedTickets.isEmpty && viewModel.recentBuilds.isEmpty &&
                        viewModel.assignedTicketsError == nil && viewModel.recentBuildsError == nil {
                ContentUnavailableView(
                    "All Clear",
                    systemImage: "checkmark.circle",
                    description: Text("There are no assigned tickets or recent builds right now.")
                )
            }
        }
        .refreshable {
            await viewModel.loadDashboard()
        }
    }

    @ViewBuilder
    private func projectsSection(_ viewModel: HomeViewModel) -> some View {
        if !viewModel.projects.isEmpty {
            Section {
                ForEach(viewModel.projects.prefix(projectPreviewLimit)) { project in
                    NavigationLink {
                        ProjectDetailView(project: project)
                    } label: {
                        HomeProjectRow(project: project)
                    }
                }
            } header: {
                HomeSectionHeader("Projects") {
                    HomeProjectsListView(viewModel: viewModel)
                }
            }
        }
    }

    @ViewBuilder
    private func assignedTicketsSection(_ viewModel: HomeViewModel) -> some View {
        Section {
            if viewModel.isLoadingAssignedTickets && viewModel.assignedTickets.isEmpty {
                HomeSectionLoadingRow(label: "Loading assigned tickets")
            } else if let error = viewModel.assignedTicketsError, viewModel.assignedTickets.isEmpty {
                HomeSectionMessageRow(
                    text: "Couldn’t load assigned tickets.",
                    systemImage: "exclamationmark.triangle",
                    emphasized: true,
                    accessibilityHint: error
                )
            } else if viewModel.assignedTickets.isEmpty {
                HomeSectionMessageRow(
                    text: "No open tickets assigned to you.",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
            } else {
                ForEach(viewModel.assignedTickets.prefix(previewLimit)) { ticket in
                    NavigationLink {
                        TicketDetailView(
                            ownerUsername: ticket.ownerUsername,
                            trackerName: ticket.trackerName,
                            trackerId: ticket.trackerId,
                            trackerRid: ticket.trackerRid,
                            ticketId: ticket.ticket.id
                        )
                    } label: {
                        HomeAssignedTicketRow(ticket: ticket)
                    }
                }
            }
        } header: {
            HomeSectionHeader("Assigned Tickets") {
                HomeAssignedTicketsListView(viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private func recentBuildsSection(_ viewModel: HomeViewModel) -> some View {
        Section {
            if viewModel.isLoadingRecentBuilds && viewModel.recentBuilds.isEmpty {
                HomeSectionLoadingRow(label: "Loading recent builds")
            } else if let error = viewModel.recentBuildsError, viewModel.recentBuilds.isEmpty {
                HomeSectionMessageRow(
                    text: "Couldn’t load recent builds.",
                    systemImage: "exclamationmark.triangle",
                    emphasized: true,
                    accessibilityHint: error
                )
            } else if viewModel.recentBuilds.isEmpty {
                HomeSectionMessageRow(
                    text: "No recent builds.",
                    systemImage: "clock"
                )
            } else {
                ForEach(viewModel.recentBuilds.prefix(previewLimit)) { build in
                    NavigationLink {
                        BuildDetailView(jobId: build.job.id)
                    } label: {
                        HomeBuildRow(build: build)
                    }
                }
            }
        } header: {
            HomeSectionActionHeader("Recent Builds") {
                appState.selectedTab = .builds
            }
        }
    }

}

private struct HomeInboxToolbarIcon: View {
    let hasUnreadThreads: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: hasUnreadThreads ? "tray.fill" : "tray")

            if hasUnreadThreads {
                Circle()
                    .fill(.blue)
                    .frame(width: 9, height: 9)
                    .offset(x: 4, y: -2)
            }
        }
        .accessibilityLabel(hasUnreadThreads ? "Inbox, unread messages" : "Inbox")
    }
}

private struct HomeProjectRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            if let description = project.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let summary = project.resourceSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HomeProjectsListView: View {
    let viewModel: HomeViewModel

    var body: some View {
        List {
            ForEach(viewModel.projects) { project in
                NavigationLink {
                    ProjectDetailView(project: project)
                } label: {
                    HomeProjectRow(project: project)
                }
            }
        }
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.loadDashboard()
        }
        .overlay {
            if viewModel.isLoadingProjects && viewModel.projects.isEmpty {
                SRHTLoadingStateView(message: "Loading projects…")
            }
        }
    }
}

private struct HomeBuildRow: View {
    let build: HomeBuildItem

    var body: some View {
        HStack(spacing: 12) {
            JobStatusIcon(status: build.job.status)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(primaryTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("Job #\(build.job.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(build.job.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(build.job.created.relativeDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Spacer()
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var primaryTitle: String {
        if let repositoryDisplayName = build.repositoryDisplayName {
            return repositoryDisplayName
        }
        return build.job.displayLabel
    }
}

private struct HomeAssignedTicketRow: View {
    let ticket: HomeAssignedTicket

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TicketStatusIcon(status: ticket.ticket.status)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(ticket.ticket.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                Text("\(ticket.ownerCanonicalName)/\(ticket.trackerName) • #\(ticket.ticket.id) • \(ticket.ticket.created.relativeDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Text(ticket.ticket.status.displayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 2)
    }
}

private struct HomeSectionLoadingRow: View {
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeSectionHeader<Destination: View>: View {
    let title: String
    let destination: Destination

    init(_ title: String, @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.destination = destination()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            NavigationLink {
                destination
            } label: {
                Text("See All")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
        }
        .textCase(nil)
    }
}

private struct HomeSectionActionHeader: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button("See All", action: action)
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
        }
        .textCase(nil)
    }
}

private struct HomeAssignedTicketsListView: View {
    let viewModel: HomeViewModel

    var body: some View {
        List {
            ForEach(viewModel.assignedTickets) { ticket in
                NavigationLink {
                    TicketDetailView(
                        ownerUsername: ticket.ownerUsername,
                        trackerName: ticket.trackerName,
                        trackerId: ticket.trackerId,
                        trackerRid: ticket.trackerRid,
                        ticketId: ticket.ticket.id
                    )
                } label: {
                    HomeAssignedTicketRow(ticket: ticket)
                }
            }

            if !viewModel.isLoadingAssignedTickets && viewModel.assignedTickets.isEmpty {
                HomeSectionMessageRow(
                    text: "No open tickets assigned to you.",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
            }
        }
        .navigationTitle("Assigned Tickets")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.loadDashboard()
        }
        .overlay {
            if viewModel.isLoadingAssignedTickets && viewModel.assignedTickets.isEmpty {
                SRHTLoadingStateView(message: "Loading assigned tickets…")
            }
        }
    }
}

private struct HomeSectionMessageRow: View {
    let text: String
    let systemImage: String
    var emphasized = false
    var accessibilityHint: String? = nil

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(emphasized ? .secondary : .tertiary)
            .accessibilityHint(accessibilityHint ?? "")
    }
}
