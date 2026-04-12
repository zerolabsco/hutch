import Testing
@testable import Hutch

struct AppStateTests {

    @Test
    @MainActor
    func presentRepositoryDeepLinkErrorSetsUserFacingMessage() {
        let appState = AppState()

        appState.presentRepositoryDeepLinkError()

        #expect(appState.deepLinkError == "The repository could not be found or is inaccessible.")
    }

    @Test
    @MainActor
    func presentTicketDeepLinkErrorSetsUserFacingMessage() {
        let appState = AppState()

        appState.presentTicketDeepLinkError()

        #expect(appState.deepLinkError == "The ticket could not be found or is inaccessible.")
    }

    @Test
    @MainActor
    func openSystemStatusSelectsMoreTabAndQueuesNavigation() {
        let appState = AppState()

        appState.openSystemStatus()

        #expect(appState.selectedTab == .more)
        #expect(appState.pendingTabNavigation == .systemStatus)
    }

    @Test
    @MainActor
    func navigationHelpersQueueExpectedTargets() {
        let appState = AppState()
        let repository = RepositorySummary(
            id: 1,
            rid: "repo",
            service: .git,
            name: "hutch",
            description: nil,
            visibility: .public,
            updated: .distantPast,
            owner: Entity(canonicalName: "~owner"),
            head: nil
        )
        let tracker = TrackerSummary(
            id: 2,
            rid: "tracker",
            name: "todo",
            description: nil,
            visibility: .public,
            updated: .distantPast,
            owner: Entity(canonicalName: "~owner")
        )

        appState.navigateToRepository(repository)
        #expect(appState.selectedTab == .repositories)
        #expect(appState.pendingTabNavigation == .repository(repository))

        appState.navigateToTracker(tracker)
        #expect(appState.selectedTab == .tickets)
        #expect(appState.pendingTabNavigation == .tracker(tracker))

        appState.navigateToBuild(jobId: 42)
        #expect(appState.selectedTab == .builds)
        #expect(appState.pendingDeepLink == .build(jobId: 42))

        appState.navigateToTicket(ownerUsername: "owner", trackerName: "todo", ticketId: 9)
        #expect(appState.selectedTab == .tickets)
        #expect(appState.pendingDeepLink == .ticket(owner: "owner", tracker: "todo", ticketId: 9))
    }
}
