import SwiftUI

/// The root view of the app. Shows a TabView when authenticated, or a
/// full-screen sheet for token entry on first launch.
struct RootView: View {
    @Environment(AppState.self) private var appState
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
        .modifier(TabKeyboardShortcuts(selectedTab: Binding(
            get: { appState.selectedTab },
            set: { appState.selectedTab = $0 }
        )))
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
        guard appState.isAuthenticated, let link else { return }
        handleDeepLink(link)
        appState.pendingDeepLink = nil
    }

    private func consumePendingTabNavigationIfPossible(_ target: AppState.TabNavigationTarget?) {
        guard appState.isAuthenticated, let target else { return }
        handleTabNavigation(target)
        appState.pendingTabNavigation = nil
    }

    private func handleDeepLink(_ link: DeepLink) {
        guard appState.isAuthenticated else { return }

        switch link {
        case .home:
            homePath = NavigationPath()
            appState.selectedTab = .home

        case .repository(let owner, let repo):
            resolveRepositoryLink(owner: owner, repo: repo)

        case .build(let jobId):
            buildsPath = NavigationPath()
            appState.selectedTab = .builds
            Task {
                await settleNavigationTransition()
                buildsPath.append(jobId)
            }

        case .ticket(let owner, let tracker, let ticketId):
            resolveTicketLink(owner: owner, tracker: tracker, ticketId: ticketId)

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

        case .lookup:
            morePath = NavigationPath()
            appState.selectedTab = .more
            Task {
                await settleNavigationTransition()
                morePath.append(MoreRoute.lookup)
            }
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

    private func resolveRepositoryLink(owner: String, repo: String) {
        isResolvingDeepLink = true
        Task {
            defer { isResolvingDeepLink = false }
            do {
                let summary = try await appState.resolveRepository(owner: owner, name: repo)
                repoPath = NavigationPath()
                appState.selectedTab = .repositories
                await settleNavigationTransition()
                repoPath.append(summary)
            } catch {
                appState.presentRepositoryDeepLinkError()
            }
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
    case lookup
    case projects
    case lists
    case pastes
    case profile
    case systemStatus
    case settings
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
                case .lookup:
                    LookupView()
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
                case .mailingList(let mailingList):
                    MailingListDetailView(mailingList: mailingList)
                case .thread(let thread):
                    ThreadDetailView(
                        thread: thread,
                        onViewed: {
                            InboxReadStateStore.markViewed(max(Date(), thread.lastActivityAt), for: thread.id, defaults: appState.accountDefaults)
                            NeedsAttentionSnapshotStore.adjustUnreadInboxThreads(by: -1, accountID: appState.activeAccountID)
                        },
                        onMarkRead: {
                            InboxReadStateStore.markViewed(max(Date(), thread.lastActivityAt), for: thread.id, defaults: appState.accountDefaults)
                            NeedsAttentionSnapshotStore.adjustUnreadInboxThreads(by: -1, accountID: appState.activeAccountID)
                        },
                        onMarkUnread: {
                            InboxReadStateStore.markUnread(for: thread.id, defaults: appState.accountDefaults)
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
