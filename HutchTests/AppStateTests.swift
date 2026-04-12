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
}
