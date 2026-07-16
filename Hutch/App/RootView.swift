import SwiftUI
import os

private let rootDeepLinkLogger = Logger(subsystem: "net.cleberg.Hutch", category: "DeepLink")

/// The root view of the app. Shows a TabView when authenticated, or a
/// full-screen sheet for token entry on first launch.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.isAMOLEDTheme) private var isAMOLED
    @State private var homePath = NavigationPath()
    @State private var morePath = NavigationPath()
    @State private var repoPath = NavigationPath()
    @State private var buildsPath = NavigationPath()
    @State private var ticketsPath = NavigationPath()
    @State private var isResolvingDeepLink = false
    @State private var hasValidatedLaunch = false

    var body: some View {
        @Bindable var appState = appState

        Group {
            switch appState.authPhase {
            case .launching:
                ProgressView(appState.authStatusMessage)
                    .task {
                        guard !hasValidatedLaunch else { return }
                        hasValidatedLaunch = true
                        await appState.validateOnLaunch()
                    }

            case .unauthenticated:
                // Full-screen token entry that cannot be dismissed.
                TokenEntryView()

            case .authenticated:
                tabContent
            }
        }
        .onChange(of: appState.pendingDeepLink) { _, newValue in
            consumePendingDeepLinkIfPossible(newValue)
        }
        .onChange(of: appState.authPhase) { _, newPhase in
            handleAuthPhaseChange(newPhase)
        }
        .onChange(of: appState.pendingTabNavigation) { _, newValue in
            consumePendingTabNavigationIfPossible(newValue)
        }
        .alert(
            "Couldn't Open Link",
            isPresented: Binding(
                get: { appState.deepLinkError != nil },
                set: { isPresented in
                    if !isPresented {
                        appState.deepLinkError = nil
                    }
                }
            )
        ) {
            Button("OK") {
                appState.deepLinkError = nil
            }
        } message: {
            Text(appState.deepLinkError ?? "")
        }
    }

    // MARK: - Tab View

    private var tabContent: some View {
        @Bindable var appState = appState

        return TabView(selection: $appState.selectedTab) {
            NavigationStack(path: $homePath) {
                HomeView()
                    .navigationDestination(for: HomeRoute.self) { route in
                        switch route {
                        case .work(let scope):
                            WorkView(initialScope: scope)
                        }
                    }
            }
            .tag(AppState.Tab.home)
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack(path: $repoPath) {
                RepositoryListView()
            }
            .tag(AppState.Tab.repositories)
            .tabItem {
                Label("Repositories", systemImage: "book.closed")
            }

            NavigationStack(path: $ticketsPath) {
                TrackerListView()
                    // Deep link destination for jumping straight to a ticket.
                    .navigationDestination(for: TicketDeepLinkTarget.self) { target in
                        TicketDetailView(ownerUsername: target.ownerUsername, trackerName: target.trackerName, trackerId: target.trackerId, trackerRid: target.trackerRid, ticketId: target.ticketId)
                    }
            }
            .tag(AppState.Tab.tickets)
            .tabItem {
                Label("Trackers", systemImage: "checklist")
            }

            NavigationStack(path: $buildsPath) {
                BuildListView()
                    // Int destination used by deep links (hutch://builds/<id>).
                    // JobSummary destination is registered inside BuildListView.
                    .navigationDestination(for: Int.self) { jobId in
                        BuildDetailView(jobId: jobId)
                    }
            }
            .tag(AppState.Tab.builds)
            .tabItem {
                Label("Builds", systemImage: "hammer")
            }

            NavigationStack(path: $morePath) {
                MoreNavigationRoot()
            }
            .tag(AppState.Tab.more)
            .tabItem {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        .id(appState.sessionIdentity)
        .defaultAppStorage(appState.accountDefaults)
        .modifier(SidebarAdaptableTabStyle())
        .modifier(AMOLEDToolbarStyle(isAMOLED: isAMOLED))
        .modifier(TabKeyboardShortcuts(selectedTab: Binding(
            get: { appState.selectedTab },
            set: { appState.selectedTab = $0 }
        )))
        .safeAreaInset(edge: .bottom) {
            if let message = appState.copyConfirmationMessage {
                CopyConfirmationBadge(message: message)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if isResolvingDeepLink {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Opening link…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Deep Link Handling

    private func handleAuthPhaseChange(_ newPhase: AppState.AuthPhase) {
        rootDeepLinkLogger.info("Auth phase changed: \(String(describing: newPhase), privacy: .public); pendingDeepLink=\(String(describing: appState.pendingDeepLink), privacy: .public)")
        switch newPhase {
        case .launching:
            break
        case .unauthenticated:
            homePath = NavigationPath()
            morePath = NavigationPath()
            repoPath = NavigationPath()
            buildsPath = NavigationPath()
            ticketsPath = NavigationPath()
            appState.selectedTab = .home
            isResolvingDeepLink = false
        case .authenticated:
            consumePendingDeepLinkIfPossible(appState.pendingDeepLink)
        }
    }

    private func consumePendingDeepLinkIfPossible(_ link: DeepLink?) {
        rootDeepLinkLogger.info("Attempting to consume pending deep link. authenticated=\(appState.isAuthenticated, privacy: .public), link=\(String(describing: link), privacy: .public)")
        guard appState.isAuthenticated, let link else {
            rootDeepLinkLogger.info("Deferred deep link consumption.")
            return
        }
        handleDeepLink(link)
        appState.pendingDeepLink = nil
    }

    private func consumePendingTabNavigationIfPossible(_ target: AppState.TabNavigationTarget?) {
        guard appState.isAuthenticated, let target else { return }
        handleTabNavigation(target)
        appState.pendingTabNavigation = nil
    }

    private func handleDeepLink(_ link: DeepLink) {
        rootDeepLinkLogger.info("Handling deep link: \(String(describing: link), privacy: .public)")
        guard appState.isAuthenticated else {
            rootDeepLinkLogger.info("Ignoring deep link while unauthenticated: \(String(describing: link), privacy: .public)")
            return
        }

        switch link {
        case .home:
            homePath = NavigationPath()
            appState.selectedTab = .home

        case .recentActivity:
            homePath = NavigationPath()
            appState.selectedTab = .home

        case .repository(let service, let owner, let repo):
            resolveRepositoryLink(service: service, owner: owner, repo: repo)

        case .tracker(let owner, let tracker):
            resolveTrackerLink(owner: owner, tracker: tracker)

        case .build(let jobId):
            buildsPath = NavigationPath()
            appState.selectedTab = .builds
            Task {
                await settleNavigationTransition()
                buildsPath.append(jobId)
            }

        case .ticket(let owner, let tracker, let ticketId):
            resolveTicketLink(owner: owner, tracker: tracker, ticketId: ticketId)

        case .mailingList(let owner, let list):
            resolveMailingListLink(owner: owner, list: list)

        case .userProfile(let owner):
            resolveUserProfileLink(owner: owner)

        case .work:
            navigateToWork(scope: .all)

        case .workQueue(let scope):
            navigateToWork(scope: scope)

        case .projectDashboard(let id, let title):
            morePath = NavigationPath()
            appState.selectedTab = .more
            Task {
                await settleNavigationTransition()
                morePath.append(MoreRoute.projects)
                morePath.append(MoreRoute.projectDashboard(id: id, title: title))
            }

        case .failedBuilds:
            buildsPath = NavigationPath()
            appState.pendingBuildListFilter = .failed
            appState.selectedTab = .builds

        case .search(let query):
            morePath = NavigationPath()
            appState.selectedTab = .more
            Task {
                await settleNavigationTransition()
                morePath.append(MoreRoute.lookup(query: query))
            }

        case .lookup:
            morePath = NavigationPath()
            appState.selectedTab = .more
            Task {
                await settleNavigationTransition()
                morePath.append(MoreRoute.lookup(query: nil))
            }

        case .buildsTab:
            buildsPath = NavigationPath()
            appState.selectedTab = .builds

        case .repositoriesTab:
            repoPath = NavigationPath()
            appState.selectedTab = .repositories

        case .trackersTab:
            ticketsPath = NavigationPath()
            appState.selectedTab = .tickets

        case .systemStatus:
            appState.navigateToSystemStatus()
        }
    }

    private func navigateToWork(scope: HutchWorkQueueScope) {
        homePath = NavigationPath()
        appState.selectedTab = .home
        Task {
            await settleNavigationTransition()
            homePath.append(HomeRoute.work(scope: scope))
        }
    }

    private func handleTabNavigation(_ target: AppState.TabNavigationTarget) {
        switch target {
        case .repository(let repository):
            repoPath = NavigationPath()
            appState.selectedTab = .repositories
            Task {
                await settleNavigationTransition()
                repoPath.append(repository)
            }

        case .tracker(let tracker):
            ticketsPath = NavigationPath()
            appState.selectedTab = .tickets
            Task {
                await settleNavigationTransition()
                ticketsPath.append(tracker)
            }

        case .mailingList(let mailingList):
            morePath = NavigationPath()
            appState.selectedTab = .more
            Task {
                await settleNavigationTransition()
                morePath.append(MoreRoute.lists)
                morePath.append(MoreRoute.mailingList(mailingList))
            }
        case .systemStatus:
            morePath = NavigationPath()
            appState.selectedTab = .more
            Task {
                await settleNavigationTransition()
                morePath.append(MoreRoute.systemStatus)
            }
        case .builds:
            buildsPath = NavigationPath()
            appState.selectedTab = .builds
        }
    }

    private func resolveRepositoryLink(service: SRHTService, owner: String, repo: String) {
        isResolvingDeepLink = true
        Task {
            defer { isResolvingDeepLink = false }
            do {
                let summary = try await appState.resolveRepository(owner: owner, name: repo, service: service)
                repoPath = NavigationPath()
                appState.selectedTab = .repositories
                await settleNavigationTransition()
                repoPath.append(summary)
            } catch {
                appState.presentRepositoryDeepLinkError()
            }
        }
    }

    private func resolveTrackerLink(owner: String, tracker: String) {
        isResolvingDeepLink = true
        Task {
            defer { isResolvingDeepLink = false }
            do {
                let trackerSummary = try await appState.resolveTracker(owner: owner, name: tracker)
                ticketsPath = NavigationPath()
                appState.selectedTab = .tickets
                await settleNavigationTransition()
                ticketsPath.append(trackerSummary)
            } catch {
                appState.presentTicketDeepLinkError()
            }
        }
    }

    private func resolveMailingListLink(owner: String, list: String) {
        isResolvingDeepLink = true
        Task {
            defer { isResolvingDeepLink = false }
            do {
                let mailingList = try await appState.resolveMailingList(owner: owner, name: list)
                morePath = NavigationPath()
                appState.selectedTab = .more
                await settleNavigationTransition()
                morePath.append(MoreRoute.lists)
                morePath.append(MoreRoute.mailingList(mailingList))
            } catch {
                appState.deepLinkError = "The mailing list could not be found or is inaccessible."
            }
        }
    }

    private func resolveUserProfileLink(owner: String) {
        rootDeepLinkLogger.info("Routing user profile deep link for owner=\(owner, privacy: .public)")
        morePath = NavigationPath()
        appState.selectedTab = .more
        Task {
            await settleNavigationTransition()
            rootDeepLinkLogger.info("Appending user profile route for owner=\(owner, privacy: .public)")
            morePath.append(MoreRoute.userProfile(owner))
        }
    }

    private func resolveTicketLink(owner: String, tracker: String, ticketId: Int) {
        isResolvingDeepLink = true
        Task {
            defer { isResolvingDeepLink = false }
            do {
                let trackerSummary = try await appState.resolveTracker(owner: owner, name: tracker)
                ticketsPath = NavigationPath()
                appState.selectedTab = .tickets
                await settleNavigationTransition()
                ticketsPath.append(trackerSummary)
                ticketsPath.append(TicketDeepLinkTarget(
                    ownerUsername: String(trackerSummary.owner.canonicalName.dropFirst()),
                    trackerName: trackerSummary.name,
                    trackerId: trackerSummary.id,
                    trackerRid: trackerSummary.rid,
                    ticketId: ticketId
                ))
            } catch {
                appState.presentTicketDeepLinkError()
            }
        }
    }

    @MainActor
    private func settleNavigationTransition() async {
        await Task.yield()
        await Task.yield()
    }
}

enum MoreDestination: Hashable {
    case lists
    case pastes
    case settings
}

enum MoreRoute: Hashable {
    case lookup(query: String?)
    case projects
    case lists
    case pastes
    case profile
    case systemStatus
    case settings
    case about
    case userProfile(String)
    case projectDashboard(id: String, title: String?)
    case mailingList(InboxMailingListReference)
    case thread(InboxThreadSummary)
    case manPageBrowser
    case manPage(URL)
}

private struct MoreNavigationRoot: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        MoreView()
            .navigationDestination(for: MoreRoute.self) { route in
                switch route {
                case .lookup(let query):
                    LookupView(initialQuery: query ?? "")
                case .projects:
                    ProjectsListView()
                case .lists:
                    MailingListListView()
                case .pastes:
                    PasteListView()
                case .profile:
                    ProfileView()
                case .systemStatus:
                    SystemStatusView()
                case .settings:
                    SettingsView()
                case .about:
                    AboutView()
                case .userProfile(let owner):
                    UserProfileDeepLinkView(owner: owner)
                case .projectDashboard(let id, let title):
                    ProjectDashboardDeepLinkView(projectID: id, title: title)
                case .mailingList(let mailingList):
                    MailingListDetailView(mailingList: mailingList)
                case .thread(let thread):
                    ThreadDetailView(
                        thread: thread,
                        onViewed: {
                            InboxReadStateStore.markViewed(max(Date(), thread.lastActivityAt), for: thread.threadGroupingKey, defaults: appState.accountDefaults)
                            NeedsAttentionSnapshotStore.adjustUnreadInboxThreads(by: -1, accountID: appState.activeAccountID)
                        },
                        onMarkRead: {
                            InboxReadStateStore.markViewed(max(Date(), thread.lastActivityAt), for: thread.threadGroupingKey, defaults: appState.accountDefaults)
                            NeedsAttentionSnapshotStore.adjustUnreadInboxThreads(by: -1, accountID: appState.activeAccountID)
                        },
                        onMarkUnread: {
                            InboxReadStateStore.markUnread(for: thread.threadGroupingKey, defaults: appState.accountDefaults)
                            NeedsAttentionSnapshotStore.adjustUnreadInboxThreads(by: 1, accountID: appState.activeAccountID)
                        }
                    )
                case .manPageBrowser:
                    ManPageBrowserView()
                case .manPage(let url):
                    ManPageDetailView(url: url)
                }
            }
    }
}

struct UserProfileDeepLinkView: View {
    private let logger = Logger(subsystem: "net.cleberg.Hutch", category: "DeepLink")
    @Environment(AppState.self) private var appState
    let owner: String
    @State private var user: User?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let user {
                UserProfileView(user: user)
            } else if let errorMessage {
                ContentUnavailableView("Couldn't Open Profile", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(errorMessage))
            } else {
                SRHTLoadingStateView(message: "Loading profile...")
            }
        }
        .navigationTitle(displayOwner)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: owner) {
            await loadProfile()
        }
    }

    private var displayOwner: String {
        owner.hasPrefix("~") ? owner : "~\(owner)"
    }

    @MainActor
    private func loadProfile() async {
        logger.info("Loading user profile for owner=\(owner, privacy: .public)")
        errorMessage = nil
        do {
            user = try await appState.resolveUser(username: owner)
            logger.info("Loaded user profile for owner=\(owner, privacy: .public), canonical=\(user?.canonicalName ?? "nil", privacy: .public)")
        } catch {
            logger.error("Failed loading user profile for owner=\(owner, privacy: .public): \(String(describing: error), privacy: .public)")
            errorMessage = "The user profile could not be found or is inaccessible."
        }
    }
}

struct ProjectDashboardDeepLinkView: View {
    @Environment(AppState.self) private var appState
    let projectID: String
    let title: String?
    @State private var project: Project?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let project {
                ProjectDetailView(project: project)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't Open Project",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text(errorMessage)
                )
            } else {
                SRHTLoadingStateView(message: "Loading project...")
            }
        }
        .navigationTitle(title ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: projectID) {
            await loadProject()
        }
    }

    @MainActor
    private func loadProject() async {
        errorMessage = nil
        do {
            project = try await ProjectService(client: appState.client).fetchProjectDetail(rid: projectID)
        } catch {
            errorMessage = "The project could not be found or is inaccessible."
        }
    }
}

// MARK: - Ticket Deep Link Navigation Target

/// Hashable wrapper to push a ticket detail view from a deep link.
struct TicketDeepLinkTarget: Hashable {
    let ownerUsername: String
    let trackerName: String
    let trackerId: Int
    let trackerRid: String
    let ticketId: Int
}

// MARK: - Keyboard Shortcuts for iPad + Hardware Keyboard

/// Adds Cmd+1 through Cmd+5 keyboard shortcuts for tab switching on iPad.
private struct TabKeyboardShortcuts: ViewModifier {
    @Binding var selectedTab: AppState.Tab

    private static let tabMap: [String: AppState.Tab] = [
        "1": .home,
        "2": .repositories,
        "3": .tickets,
        "4": .builds,
        "5": .more,
    ]

    func body(content: Content) -> some View {
        content
            .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                guard press.modifiers == .command else { return .ignored }
                let key = String(press.characters)
                if let tab = Self.tabMap[key] {
                    selectedTab = tab
                    return .handled
                }
                return .ignored
            }
    }
}

// MARK: - AMOLED Toolbar Styling

/// Applies true-black backgrounds to the tab bar and navigation bar when the AMOLED theme is active.
private struct AMOLEDToolbarStyle: ViewModifier {
    let isAMOLED: Bool

    func body(content: Content) -> some View {
        if isAMOLED {
            content
                .toolbarBackground(Color.black, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(Color.black, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            content
        }
    }
}

// MARK: - iPad Sidebar Adaptable

/// Applies `.tabViewStyle(.sidebarAdaptable)` on iOS 18+ so the tab bar
/// becomes a full sidebar on iPad, while falling back to the standard tab
/// bar on earlier releases.
private struct SidebarAdaptableTabStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}
