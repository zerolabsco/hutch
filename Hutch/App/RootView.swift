import SwiftUI

/// The root view of the app. Shows a TabView when authenticated, or a
/// full-screen sheet for token entry on first launch.
struct RootView: View {
    @Environment(AppState.self) private var appState

    enum Tab: Hashable {
        case home
        case repositories
        case builds
        case tickets
        case settings
    }

    @State private var selectedTab: Tab = .home
    @State private var homePath = NavigationPath()
    @State private var repoPath = NavigationPath()
    @State private var buildsPath = NavigationPath()
    @State private var ticketsPath = NavigationPath()
    @State private var isResolvingDeepLink = false

    var body: some View {
        Group {
            switch appState.authPhase {
            case .launching:
                ProgressView("Connecting…")
                    .task {
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
    }

    // MARK: - Tab View

    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homePath) {
                HomeView()
            }
            .tag(Tab.home)
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack(path: $repoPath) {
                RepositoryListView()
            }
            .tag(Tab.repositories)
            .tabItem {
                Label("Repositories", systemImage: "book.closed")
            }

            NavigationStack(path: $buildsPath) {
                BuildListView()
                    // Int destination used by deep links (hutch://builds/<id>).
                    // JobSummary destination is registered inside BuildListView.
                    .navigationDestination(for: Int.self) { jobId in
                        BuildDetailView(jobId: jobId)
                    }
            }
            .tag(Tab.builds)
            .tabItem {
                Label("Builds", systemImage: "hammer")
            }

            NavigationStack(path: $ticketsPath) {
                TrackerListView()
                    // Deep link destination for jumping straight to a ticket.
                    .navigationDestination(for: TicketDeepLinkTarget.self) { target in
                        TicketDetailView(ownerUsername: target.ownerUsername, trackerName: target.trackerName, trackerId: target.trackerId, trackerRid: target.trackerRid, ticketId: target.ticketId)
                    }
            }
            .tag(Tab.tickets)
            .tabItem {
                Label("Tickets", systemImage: "ticket")
            }

            SettingsView()
                .tag(Tab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gear")
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
        switch newPhase {
        case .launching:
            break
        case .unauthenticated:
            homePath = NavigationPath()
            repoPath = NavigationPath()
            buildsPath = NavigationPath()
            ticketsPath = NavigationPath()
            selectedTab = .home
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

    private func handleDeepLink(_ link: DeepLink) {
        guard appState.isAuthenticated else { return }

        switch link {
        case .repository(let owner, let repo):
            resolveRepositoryLink(owner: owner, repo: repo)

        case .build(let jobId):
            // Reset the builds navigation and push the detail
            buildsPath = NavigationPath()
            selectedTab = .builds
            // Defer the push slightly so the tab switch takes effect
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                buildsPath.append(jobId)
            }

        case .ticket(let owner, let tracker, let ticketId):
            resolveTicketLink(owner: owner, tracker: tracker, ticketId: ticketId)
        }
    }

    private func resolveRepositoryLink(owner: String, repo: String) {
        isResolvingDeepLink = true
        Task {
            defer { isResolvingDeepLink = false }
            do {
                let summary = try await appState.resolveRepository(owner: owner, name: repo)
                repoPath = NavigationPath()
                selectedTab = .repositories
                try? await Task.sleep(for: .milliseconds(100))
                repoPath.append(summary)
            } catch {
                // Silently fail — the repo may not exist or be inaccessible
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
                selectedTab = .tickets
                try? await Task.sleep(for: .milliseconds(100))
                ticketsPath.append(trackerSummary)
                try? await Task.sleep(for: .milliseconds(100))
                ticketsPath.append(TicketDeepLinkTarget(
                    ownerUsername: String(trackerSummary.owner.canonicalName.dropFirst()),
                    trackerName: trackerSummary.name,
                    trackerId: trackerSummary.id,
                    trackerRid: trackerSummary.rid,
                    ticketId: ticketId
                ))
            } catch {
                // Silently fail
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
