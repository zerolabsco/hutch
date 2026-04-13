import SwiftUI

struct HomeView: View {
    @AppStorage(AppStorageKeys.swipeActionsEnabled) private var swipeActionsEnabled = true
    @AppStorage(AppStorageKeys.homeProjectsExpanded) private var projectsExpanded = true
    @AppStorage(AppStorageKeys.homeAssignedTicketsExpanded) private var assignedTicketsExpanded = true
    @AppStorage(AppStorageKeys.homeBuildsExpanded) private var buildsExpanded = true
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
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
            guard let currentUser = appState.currentUser else { return }

            let vm: HomeViewModel
            if let viewModel {
                vm = viewModel
            } else {
                let newViewModel = HomeViewModel(
                    currentUser: currentUser,
                    client: appState.client,
                    systemStatusRepository: appState.systemStatusRepository
                )
                viewModel = newViewModel
                vm = newViewModel
            }

            await vm.loadDashboard()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, let viewModel else { return }
            Task {
                await viewModel.loadDashboard()
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: HomeViewModel) -> some View {
        List {
            attentionSection(viewModel)
            systemStatusBannerSection(viewModel)
            inboxSection(viewModel)
            projectsSection(viewModel)
            assignedTicketsSection(viewModel)
            recentBuildsSection(viewModel)
        }
        .themedList()
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.isLoadingProjects && viewModel.isLoadingAssignedTickets && viewModel.isLoadingRecentBuilds &&
                viewModel.pinnedProjects.isEmpty && viewModel.assignedTickets.isEmpty && viewModel.recentBuilds.isEmpty &&
                viewModel.unreadInboxThreads.isEmpty {
                SRHTLoadingStateView(message: "Loading Home…")
            } else if !viewModel.isLoadingProjects && !viewModel.isLoadingAssignedTickets && !viewModel.isLoadingRecentBuilds &&
                        viewModel.pinnedProjects.isEmpty && viewModel.assignedTickets.isEmpty && viewModel.recentBuilds.isEmpty &&
                        viewModel.unreadInboxThreads.isEmpty &&
                        viewModel.assignedTicketsError == nil && viewModel.recentBuildsError == nil {
                ContentUnavailableView(
                    "All Clear",
                    systemImage: "checkmark.circle",
                    description: Text("There are no unread threads, assigned tickets, or urgent builds right now.")
                )
            }
        }
        .refreshable {
            await viewModel.loadDashboard()
        }
        .connectivityOverlay(hasContent: viewModel.hasDashboardContent) {
            await viewModel.loadDashboard()
        }
    }

    @ViewBuilder
    private func attentionSection(_ viewModel: HomeViewModel) -> some View {
        Section("Needs Attention") {
            HomeAttentionSummaryRow(
                title: viewModel.needsAttentionCount == 0 ? "All clear" : "\(viewModel.needsAttentionCount) things need attention",
                summary: viewModel.attentionSummaryText
            )

            HomeAttentionLinkRow(
                title: "Inbox",
                summary: viewModel.inboxSummaryText,
                countText: viewModel.unreadInboxThreadCount.map(String.init) ?? "?"
            ) {
                InboxView()
            }

            HomeAttentionLinkRow(
                title: "Assigned Tickets",
                summary: viewModel.ticketsSummaryText,
                countText: String(viewModel.assignedTickets.count)
            ) {
                HomeAssignedTicketsListView(viewModel: viewModel)
            }

            HomeAttentionLinkRow(
                title: "Builds",
                summary: viewModel.buildsSummaryText,
                countText: String(viewModel.failedBuildCount + viewModel.activeBuildCount),
                action: {
                    appState.navigateToBuildsList()
                }
            )
        }
    }

    @ViewBuilder
    private func systemStatusBannerSection(_ viewModel: HomeViewModel) -> some View {
        Section {
            NavigationLink {
                SystemStatusView()
            } label: {
                SystemStatusSummaryRow(
                    snapshot: viewModel.systemStatusSnapshot,
                    isLoading: viewModel.isLoadingSystemStatus,
                    errorMessage: viewModel.systemStatusErrorMessage,
                    isShowingStaleData: viewModel.isShowingStaleSystemStatus
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func inboxSection(_ viewModel: HomeViewModel) -> some View {
        Section {
            if let unreadCount = viewModel.unreadInboxThreadCount, unreadCount == 0 {
                HomeSectionMessageRow(
                    text: "No unread inbox threads.",
                    systemImage: "tray"
                )
            } else if viewModel.unreadInboxThreads.isEmpty {
                HomeSectionMessageRow(
                    text: viewModel.inboxSummaryText,
                    systemImage: "tray"
                )
            } else {
                ForEach(viewModel.unreadInboxThreads.prefix(previewLimit)) { thread in
                    NavigationLink {
                        ThreadDetailView(
                            thread: thread,
                            onViewed: { viewModel.markInboxThreadRead(thread) },
                            onMarkRead: { viewModel.markInboxThreadRead(thread) },
                            onMarkUnread: { viewModel.markInboxThreadUnread(thread) }
                        )
                    } label: {
                        HomeInboxThreadRow(thread: thread)
                    }
                }
            }
        } header: {
            HomeSectionHeader("Inbox") {
                InboxView()
            }
        }
    }

    @ViewBuilder
    private func projectsSection(_ viewModel: HomeViewModel) -> some View {
        if !viewModel.pinnedProjects.isEmpty {
            HomeSectionView("Pinned Projects", isExpanded: $projectsExpanded) {
                NavigationLink {
                    ProjectsListView()
                } label: {
                    Text("See All")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
            } content: {
                ForEach(viewModel.pinnedProjects.prefix(projectPreviewLimit)) { project in
                    NavigationLink {
                        ProjectDetailView(project: project)
                    } label: {
                        HomeProjectRow(project: project)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func assignedTicketsSection(_ viewModel: HomeViewModel) -> some View {
        HomeSectionView("Tickets", isExpanded: $assignedTicketsExpanded) {
            NavigationLink {
                HomeAssignedTicketsListView(viewModel: viewModel)
            } label: {
                Text("See All")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
        } content: {
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
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if swipeActionsEnabled {
                            ticketLeadingSwipeAction(ticket, viewModel: viewModel)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if swipeActionsEnabled {
                            Button {
                                Task {
                                    await viewModel.unassignFromMe(ticket)
                                }
                            } label: {
                                Label("Unassign Me", systemImage: "person.badge.minus")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentBuildsSection(_ viewModel: HomeViewModel) -> some View {
        HomeSectionView("Builds", isExpanded: $buildsExpanded) {
            Button("See All") {
                appState.navigateToBuildsList()
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.plain)
        } content: {
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
                ForEach(buildGroups(for: viewModel.recentBuilds)) { group in
                    if let repositoryDisplayName = group.repositoryDisplayName {
                        HomeBuildGroupHeader(
                            repositoryDisplayName: repositoryDisplayName,
                            buildCount: group.builds.count,
                            latestStatus: group.latestStatus
                        )
                    }

                    ForEach(group.builds) { build in
                        NavigationLink {
                            BuildDetailView(jobId: build.job.id)
                        } label: {
                            HomeBuildRow(
                                build: build,
                                showsRepositoryLink: group.repositoryDisplayName == nil
                            )
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if swipeActionsEnabled, build.job.status.isCancellable {
                                Button {
                                    Task {
                                        await viewModel.cancelBuild(build)
                                    }
                                }
                                label: {
                                    Label("Cancel", systemImage: "xmark.circle")
                                }
                                .tint(.red)
                            }
                        }
                    }
                }
            }
        }
    }

    private func buildGroups(for builds: [HomeBuildItem]) -> [HomeBuildGroup] {
        let previewBuilds = Array(builds.prefix(previewLimit))
        guard let firstBuild = previewBuilds.first else { return [] }

        var groups: [HomeBuildGroup] = []
        var currentIdentity = HomeBuildGroup.Identity(build: firstBuild)
        var currentBuilds: [HomeBuildItem] = []

        for build in previewBuilds {
            let identity = HomeBuildGroup.Identity(build: build)
            if identity == currentIdentity {
                currentBuilds.append(build)
            } else {
                groups.append(HomeBuildGroup(identity: currentIdentity, builds: currentBuilds))
                currentIdentity = identity
                currentBuilds = [build]
            }
        }

        if !currentBuilds.isEmpty {
            groups.append(HomeBuildGroup(identity: currentIdentity, builds: currentBuilds))
        }

        return groups
    }

    @ViewBuilder
    private func ticketLeadingSwipeAction(
        _ ticket: HomeAssignedTicket,
        viewModel: HomeViewModel
    ) -> some View {
        if ticket.ticket.status.isOpen {
            Button {
                Task {
                    await viewModel.resolveTicket(ticket)
                }
            } label: {
                Label("Resolve", systemImage: "checkmark.circle")
            }
            .tint(.green)
        } else {
            Button {
                Task {
                    await viewModel.reopenTicket(ticket)
                }
            } label: {
                Label("Reopen", systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
        }
    }

}

private struct HomeInboxToolbarIcon: View {
    let hasUnreadThreads: Bool

    var body: some View {
        Image(systemName: hasUnreadThreads ? "tray.fill" : "tray")
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

private struct HomeBuildRow: View {
    @Environment(AppState.self) private var appState
    let build: HomeBuildItem
    var showsRepositoryLink = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                JobStatusIcon(status: build.job.status)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(build.job.displayLabel)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text("Job #\(build.job.id)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Text(build.job.status.displayTitle)
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

            if showsRepositoryLink, let repositoryDisplayName = build.repositoryDisplayName {
                Button {
                    openRepository()
                } label: {
                    Label(repositoryDisplayName, systemImage: "book.closed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private func openRepository() {
        guard let repositoryName = build.repositoryName,
              let repositoryOwner = build.repositoryOwner else { return }
        Task {
            do {
                let repository = try await appState.resolveRepository(
                    owner: repositoryOwner.hasPrefix("~") ? String(repositoryOwner.dropFirst()) : repositoryOwner,
                    name: repositoryName
                )
                appState.navigateToRepository(repository)
            } catch {
                appState.presentRepositoryDeepLinkError()
            }
        }
    }
}

private struct HomeBuildGroup: Identifiable {
    enum Identity: Hashable {
        case repository(owner: String?, name: String)
        case standalone(Int)

        init(build: HomeBuildItem) {
            if let repositoryName = build.repositoryName {
                self = .repository(owner: build.repositoryOwner, name: repositoryName)
            } else {
                self = .standalone(build.id)
            }
        }
    }

    let identity: Identity
    let builds: [HomeBuildItem]

    var id: String {
        switch identity {
        case .repository(let owner, let name):
            return "\(owner ?? "_")/\(name)#\(builds.first?.id ?? 0)"
        case .standalone(let jobId):
            return "job-\(jobId)"
        }
    }

    var repositoryDisplayName: String? {
        builds.first?.repositoryDisplayName
    }

    var latestStatus: JobStatus {
        builds.first?.job.status ?? .pending
    }
}

private struct HomeBuildGroupHeader: View {
    let repositoryDisplayName: String
    let buildCount: Int
    let latestStatus: JobStatus

    var body: some View {
        HStack(spacing: 12) {
            Label(repositoryDisplayName, systemImage: "book.closed")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("\(buildCount) \(buildCount == 1 ? "build" : "builds")")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)

            JobStatusBadge(status: latestStatus)
        }
        .padding(.top, 4)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }
}

private struct HomeAssignedTicketRow: View {
    @Environment(AppState.self) private var appState
    let ticket: HomeAssignedTicket

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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

            Button {
                openTracker()
            } label: {
                Label("\(ticket.ownerCanonicalName)/\(ticket.trackerName)", systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func openTracker() {
        Task {
            do {
                let tracker = try await appState.resolveTracker(owner: ticket.ownerUsername, name: ticket.trackerName)
                appState.navigateToTracker(tracker)
            } catch {
                appState.presentTicketDeepLinkError()
            }
        }
    }
}

private struct HomeInboxThreadRow: View {
    @Environment(AppState.self) private var appState
    let thread: InboxThreadSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(thread.displaySubject)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)

                    Text(thread.metadataLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                Button {
                    appState.navigateToMailingList(
                        InboxMailingListReference(
                            id: thread.listID,
                            rid: thread.listRID,
                            name: thread.listName,
                            owner: thread.listOwner
                        )
                    )
                } label: {
                    Label(thread.listName, systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if let repo = thread.repo {
                    Button {
                        openRepository(named: repo)
                    } label: {
                        Label(repo, systemImage: "book.closed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func openRepository(named repositoryName: String) {
        Task {
            do {
                let ownerUsername = thread.listOwner.canonicalName.hasPrefix("~")
                    ? String(thread.listOwner.canonicalName.dropFirst())
                    : thread.listOwner.canonicalName
                let repository = try await appState.resolveRepository(owner: ownerUsername, name: repositoryName)
                appState.navigateToRepository(repository)
            } catch {
                appState.presentRepositoryDeepLinkError()
            }
        }
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

private struct HomeAttentionSummaryRow: View {
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

private struct HomeAttentionLinkRow<Destination: View>: View {
    let title: String
    let summary: String
    let countText: String
    let destination: Destination?
    let action: (() -> Void)?

    init(
        title: String,
        summary: String,
        countText: String,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.summary = summary
        self.countText = countText
        self.destination = destination()
        self.action = nil
    }

    init(
        title: String,
        summary: String,
        countText: String,
        action: @escaping () -> Void
    ) where Destination == EmptyView {
        self.title = title
        self.summary = summary
        self.countText = countText
        self.destination = nil
        self.action = action
    }

    var body: some View {
        Group {
            if let destination {
                NavigationLink {
                    destination
                } label: {
                    content
                }
            } else if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(countText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.secondarySystemFill), in: Capsule())

            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

private struct HomeAssignedTicketsListView: View {
    let viewModel: HomeViewModel
    @AppStorage(AppStorageKeys.swipeActionsEnabled) private var swipeActionsEnabled = true

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
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if swipeActionsEnabled {
                        if ticket.ticket.status.isOpen {
                            Button {
                                Task { await viewModel.resolveTicket(ticket) }
                            } label: {
                                Label("Resolve", systemImage: "checkmark.circle")
                            }
                            .tint(.green)
                        } else {
                            Button {
                                Task { await viewModel.reopenTicket(ticket) }
                            } label: {
                                Label("Reopen", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if swipeActionsEnabled {
                        Button {
                            Task { await viewModel.unassignFromMe(ticket) }
                        } label: {
                            Label("Unassign Me", systemImage: "person.badge.minus")
                        }
                        .tint(.orange)
                    }
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
