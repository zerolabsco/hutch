import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppStorageKeys.homeFailedBuildLookbackDays, store: .standard)
    private var failedBuildLookbackDays = HomeViewModel.defaultFailedBuildLookbackDays
    @State private var viewModel: HomeViewModel?
    @State private var recentItems: [RecentActivityEntry] = []
    @State private var isOpeningRecentItem = false
    @State private var selectedPinnedProject: Project?
    @State private var selectedPinnedUser: User?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                SRHTLoadingStateView(message: "Loading Home…")
            }
        }
        .navigationTitle("Home")
        .navigationDestination(isPresented: Binding(
            get: { selectedPinnedProject != nil },
            set: { isPresented in
                if !isPresented {
                    selectedPinnedProject = nil
                }
            }
        )) {
            if let selectedPinnedProject {
                ProjectDetailView(project: selectedPinnedProject)
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedPinnedUser != nil },
            set: { isPresented in
                if !isPresented {
                    selectedPinnedUser = nil
                }
            }
        )) {
            if let selectedPinnedUser {
                UserProfileView(user: selectedPinnedUser)
            }
        }
        .task {
            guard let currentUser = appState.currentUser else { return }
            await ensureViewModel(currentUser: currentUser).loadDashboard()
            loadRecentActivity()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, let viewModel, viewModel.needsRefresh() else { return }
            Task {
                await viewModel.loadDashboard()
                loadRecentActivity()
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: HomeViewModel) -> some View {
        List {
            systemStatusSection(viewModel)
            workSection(viewModel)
            recentSection
            buildsSection(viewModel)
            pinnedSection(viewModel)
        }
        .themedList()
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .refreshable {
            await viewModel.loadDashboard()
        }
        .connectivityOverlay(hasContent: hasHomeContent(viewModel)) {
            await viewModel.loadDashboard()
        }
        .onAppear {
            loadRecentActivity()
        }
    }

    @ViewBuilder
    private func systemStatusSection(_ viewModel: HomeViewModel) -> some View {
        if viewModel.systemStatusSnapshot?.hasDisruption == true {
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
                .themedRow()
            }
        }
    }

    private func workSection(_ viewModel: HomeViewModel) -> some View {
        Section("Work") {
            NavigationLink(value: HomeRoute.work) {
                HomeSummaryRow(
                    title: workTitle(viewModel),
                    summary: workSummary(viewModel),
                    systemImage: "tray.full",
                    tint: workCount(viewModel) > 0 ? .blue : .secondary,
                    emphasis: .action
                )
            }
            .themedRow()
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !recentItems.isEmpty {
            Section("Recent") {
                ForEach(recentItems.prefix(3)) { item in
                    Button {
                        openRecentItem(item)
                    } label: {
                        HomeRecentRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .disabled(isOpeningRecentItem)
                    .listRowSeparator(.hidden)
                }
                .themedRow()
            }
        }
    }

    private func buildsSection(_ viewModel: HomeViewModel) -> some View {
        Section("Builds") {
            Button {
                appState.navigateToBuildsList()
            } label: {
                HomeSummaryRow(
                    title: buildsTitle(viewModel),
                    summary: buildsSummary(viewModel),
                    systemImage: "hammer",
                    tint: failedBuildCount(viewModel) > 0 ? .orange : .secondary,
                    emphasis: .monitoring
                )
            }
            .buttonStyle(.plain)
            .themedRow()
        }
    }

    private func pinnedSection(_ viewModel: HomeViewModel) -> some View {
        let items = pinnedItems(viewModel)

        return Section("Pinned") {
            if items.isEmpty {
                NavigationLink {
                    ProjectsListView()
                } label: {
                    HomeCompactMessageRow(text: "Pin projects for quick access", systemImage: "pin")
                }
                .themedRow()
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ],
                    spacing: 10
                ) {
                    ForEach(items) { item in
                        Button {
                            openPinnedItem(item)
                        } label: {
                            HomePinnedCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
                .themedRow()
            }
        }
    }

    private func workCount(_ viewModel: HomeViewModel) -> Int {
        unreadCount(viewModel) + viewModel.assignedTickets.count
    }

    private func unreadCount(_ viewModel: HomeViewModel) -> Int {
        viewModel.unreadInboxThreadCount ?? viewModel.unreadInboxThreads.count
    }

    private func workTitle(_ viewModel: HomeViewModel) -> String {
        let count = workCount(viewModel)
        if count == 0 {
            return "Queue clear"
        }
        return "\(count) item\(count == 1 ? "" : "s") need attention"
    }

    private func workSummary(_ viewModel: HomeViewModel) -> String {
        let unread = unreadCount(viewModel)
        let assigned = viewModel.assignedTickets.count
        return "\(unread) unread • \(assigned) assigned"
    }

    private func buildsTitle(_ viewModel: HomeViewModel) -> String {
        let failed = failedBuildCount(viewModel)
        let running = viewModel.activeBuildCount

        if failed == 0 && running == 0 {
            return "Build monitoring clear"
        }
        if failed > 0 {
            return "\(failed) failed build\(failed == 1 ? "" : "s")"
        }
        return "\(running) running build\(running == 1 ? "" : "s")"
    }

    private func buildsSummary(_ viewModel: HomeViewModel) -> String {
        let failed = failedBuildCount(viewModel)
        let running = viewModel.activeBuildCount
        if failed == 0 && running == 0 {
            return "No failures • \(buildTimeframeLabel())"
        }
        if failed > 0 && running > 0 {
            return "\(failed) failed • \(running) running • \(buildTimeframeLabel())"
        }
        if failed > 0 {
            return "\(failed) failed • \(buildTimeframeLabel())"
        }
        return "\(running) running now"
    }

    private func pinnedItems(_ viewModel: HomeViewModel) -> [HomePinnedItem] {
        let currentUserKey = appState.currentUser?.canonicalName ?? ""
        let pins = HomePinStore.loadPins(for: currentUserKey, defaults: appState.accountDefaults)
        let projectsByID = Dictionary(uniqueKeysWithValues: viewModel.projects.map { ($0.id, $0) })

        return pins.compactMap { pin in
            switch pin.kind {
            case .project:
                guard let project = projectsByID[pin.value] else { return nil }
                return HomePinnedItem(pin: pin, project: project)
            case .repository, .tracker, .mailingList, .user:
                return HomePinnedItem(pin: pin, project: nil)
            }
        }
    }

    private func buildTimeframeLabel() -> String {
        HomeViewModel.failedBuildLookbackLabel(days: failedBuildLookbackDays)
    }

    private func failedBuildCount(_ viewModel: HomeViewModel) -> Int {
        viewModel.recentFailedBuilds(lookbackDays: failedBuildLookbackDays).count
    }

    private func hasHomeContent(_ viewModel: HomeViewModel) -> Bool {
        viewModel.systemStatusSnapshot?.hasDisruption == true ||
        workCount(viewModel) > 0 ||
        !recentItems.isEmpty ||
        !pinnedItems(viewModel).isEmpty
    }

    private func loadRecentActivity() {
        recentItems = RecentActivityStore.load(defaults: appState.accountDefaults)
    }

    private func openRecentItem(_ item: RecentActivityEntry) {
        guard !isOpeningRecentItem else { return }

        switch item.kind {
        case .build:
            guard let jobId = item.buildJobId else { return }
            appState.navigateToBuild(jobId: jobId)
        case .ticket:
            guard
                let ownerUsername = item.ticketOwnerUsername,
                let trackerName = item.ticketTrackerName,
                let ticketId = item.ticketId
            else {
                return
            }
            appState.navigateToTicket(ownerUsername: ownerUsername, trackerName: trackerName, ticketId: ticketId)
        case .repository:
            guard
                let owner = item.repositoryOwner,
                let name = item.repositoryName
            else {
                return
            }

            isOpeningRecentItem = true
            Task {
                defer { isOpeningRecentItem = false }
                do {
                    let repository = try await appState.resolveRepository(
                        owner: owner,
                        name: name,
                        service: item.repositoryService ?? .git
                    )
                    appState.navigateToRepository(repository)
                } catch {
                    appState.presentRepositoryDeepLinkError()
                }
            }
        }
    }

    private func openPinnedItem(_ item: HomePinnedItem) {
        switch item.pin.kind {
        case .project:
            guard let project = item.project else { return }
            selectedPinnedProject = project
        case .repository:
            guard
                let owner = item.pin.ownerUsername,
                let service = item.pin.service
            else {
                return
            }
            isOpeningRecentItem = true
            Task {
                defer { isOpeningRecentItem = false }
                do {
                    let repository = try await appState.resolveRepository(owner: owner, name: item.pin.value, service: service)
                    appState.navigateToRepository(repository)
                } catch {
                    appState.presentRepositoryDeepLinkError()
                }
            }
        case .tracker:
            guard let owner = item.pin.ownerUsername else { return }
            isOpeningRecentItem = true
            Task {
                defer { isOpeningRecentItem = false }
                do {
                    let tracker = try await appState.resolveTracker(owner: owner, name: item.pin.value)
                    appState.navigateToTracker(tracker)
                } catch {
                    appState.presentTicketDeepLinkError()
                }
            }
        case .mailingList:
            guard let ownerUsername = item.pin.ownerUsername else { return }
            appState.openMailingList(
                InboxMailingListReference(
                    id: 0,
                    rid: item.pin.value,
                    name: item.pin.title,
                    owner: Entity(canonicalName: "~\(ownerUsername)")
                )
            )
        case .user:
            guard let ownerUsername = item.pin.ownerUsername else { return }
            isOpeningRecentItem = true
            Task {
                defer { isOpeningRecentItem = false }
                if let user = try? await resolvePinnedUser(username: ownerUsername) {
                    selectedPinnedUser = user
                }
            }
        }
    }

    private func resolvePinnedUser(username: String) async throws -> User {
        struct Response: Decodable, Sendable {
            let user: User
        }

        let query = """
        query userLookup($username: String!) {
            user: userByName(username: $username) {
                id
                created
                updated
                canonicalName
                username
                email
                url
                location
                bio
                avatar
                pronouns
                userType
            }
        }
        """

        let result = try await appState.client.execute(
            service: .meta,
            query: query,
            variables: ["username": username],
            responseType: Response.self
        )
        return result.user
    }

    @MainActor
    private func ensureViewModel(currentUser: User) -> HomeViewModel {
        if let viewModel {
            return viewModel
        }

        let newViewModel = HomeViewModel(
            currentUser: currentUser,
            client: appState.client,
            systemStatusRepository: appState.systemStatusRepository,
            defaults: appState.accountDefaults,
            accountID: appState.activeAccountID
        )
        viewModel = newViewModel
        return newViewModel
    }
}

enum HomeRoute: Hashable {
    case work
}

private enum HomeSummaryEmphasis {
    case action
    case monitoring
}

private struct HomePinnedItem: Identifiable {
    let pin: HomePinRecord
    let project: Project?

    var id: String { pin.id }
    var title: String { project?.displayName ?? pin.title }
    var detail: String { pin.subtitle }
}

private struct HomeSummaryRow: View {
    let title: String
    let summary: String
    let systemImage: String
    let tint: Color
    let emphasis: HomeSummaryEmphasis

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, verticalPadding)
    }

    private var iconColor: Color {
        switch emphasis {
        case .action:
            return tint
        case .monitoring:
            return tint.opacity(0.9)
        }
    }

    private var verticalPadding: CGFloat {
        switch emphasis {
        case .action:
            return 3
        case .monitoring:
            return 2
        }
    }
}

private struct HomeRecentRow: View {
    let item: RecentActivityEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(item.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 1)
    }

    private var iconName: String {
        switch item.kind {
        case .repository:
            return "book.closed"
        case .ticket:
            return "number"
        case .build:
            return "hammer"
        }
    }
}

private struct HomePinnedCard: View {
    let item: HomePinnedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.detail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct HomeCompactMessageRow: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)
    }
}
