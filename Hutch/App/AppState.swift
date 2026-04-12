import Foundation
import SwiftUI
import WebKit

/// Central application state shared across the view hierarchy.
@Observable
@MainActor
final class AppState {

    enum Tab: Hashable {
        case home
        case repositories
        case tickets
        case builds
        case more
    }

    enum TabNavigationTarget: Hashable {
        case repository(RepositorySummary)
        case tracker(TrackerSummary)
        case mailingList(InboxMailingListReference)
        case systemStatus
        case builds
    }

    enum AuthPhase {
        /// App just launched, checking for an existing token.
        case launching
        /// No valid token — show the token entry screen.
        case unauthenticated
        /// Token validated, user is signed in.
        case authenticated
    }

    // MARK: - Authentication

    private(set) var authPhase: AuthPhase = .launching

    /// Convenience for views that need a simple bool.
    var isAuthenticated: Bool {
        authPhase == .authenticated && currentUser != nil
    }

    // MARK: - Multi-account

    /// All stored accounts. Loaded from Keychain; kept in sync on add/remove/switch.
    private(set) var accounts: [AccountEntry] = []

    /// The ID of the account currently in use. Persisted in UserDefaults.
    private(set) var activeAccountID: String = ""

    var selectedTab: Tab = .home

    // MARK: - Current user (populated after successful validation)

    private(set) var currentUser: User?

    // MARK: - Networking

    let client: SRHTClient
    let configuration: AppConfiguration
    let systemStatusRepository: SystemStatusRepository

    // MARK: - Deep link pending navigation

    /// Set by the deep link handler; consumed by RootView to drive navigation.
    var pendingDeepLink: DeepLink?
    var pendingTabNavigation: TabNavigationTarget?
    var deepLinkError: String?

    // MARK: - Init

    init() {
        self.configuration = AppConfiguration()
        let token = KeychainHelper.loadToken()
        self.client = SRHTClient(token: token)
        self.systemStatusRepository = SystemStatusRepository()
    }

    // MARK: - Launch validation

    /// Called once at app launch. If a token exists in Keychain, validates it
    /// silently. On failure, clears the token and falls through to unauthenticated.
    func validateOnLaunch() async {
        var storedAccounts = KeychainHelper.loadAccounts()

        if storedAccounts.isEmpty, let legacyToken = KeychainHelper.loadToken() {
            client.setToken(legacyToken)
            if let user = try? await fetchMe() {
                let entry = AccountEntry(id: UUID().uuidString, username: user.username, token: legacyToken)
                storedAccounts = [entry]
                try? KeychainHelper.saveAccounts(storedAccounts)
                try? KeychainHelper.deleteToken()
            } else {
                try? KeychainHelper.deleteToken()
                client.setToken(nil)
                authPhase = .unauthenticated
                return
            }
        }

        guard !storedAccounts.isEmpty else {
            authPhase = .unauthenticated
            return
        }

        let savedID = UserDefaults.standard.string(forKey: AppStorageKeys.activeAccountID) ?? ""
        let target = storedAccounts.first(where: { $0.id == savedID }) ?? storedAccounts[0]

        client.setToken(target.token)
        do {
            let user = try await fetchMe()
            accounts = storedAccounts
            activeAccountID = target.id
            currentUser = user
            ContributionWidgetContextStore.saveActor(user.canonicalName)
            authPhase = .authenticated
            await refreshNeedsAttentionSnapshot()
        } catch {
            client.setToken(nil)
            currentUser = nil
            ContributionWidgetContextStore.clear()
            authPhase = .unauthenticated
            NeedsAttentionSnapshotStore.clear()
        }
    }

    // MARK: - Token management

    /// Validate a new token by querying meta.sr.ht, then persist it.
    /// Throws on network/GraphQL errors so the caller can display the message.
    func connect(with token: String) async throws {
        client.setToken(token)
        do {
            let user = try await fetchMe()
            let entry = AccountEntry(id: UUID().uuidString, username: user.username, token: token)
            accounts.append(entry)
            activeAccountID = entry.id
            UserDefaults.standard.set(entry.id, forKey: AppStorageKeys.activeAccountID)
            try KeychainHelper.saveAccounts(accounts)
            currentUser = user
            ContributionWidgetContextStore.saveActor(user.canonicalName)
            authPhase = .authenticated
            await refreshNeedsAttentionSnapshot()
        } catch {
            client.setToken(nil)
            throw error
        }
    }

    /// Validate a new token, add it as an account, and switch to it immediately.
    func addAccount(token: String) async throws {
        let tempClient = SRHTClient(token: token)
        let user = try await fetchMe(using: tempClient)
        let entry = AccountEntry(id: UUID().uuidString, username: user.username, token: token)
        accounts.append(entry)
        try KeychainHelper.saveAccounts(accounts)
        try await switchAccount(to: entry.id)
    }

    /// Switch the active account and fully refresh the app.
    func switchAccount(to id: String) async throws {
        guard let entry = accounts.first(where: { $0.id == id }) else { return }

        client.responseCache.clear()
        currentUser = nil
        pendingDeepLink = nil
        pendingTabNavigation = nil
        deepLinkError = nil
        selectedTab = .home

        authPhase = .unauthenticated

        client.setToken(entry.token)
        activeAccountID = entry.id
        UserDefaults.standard.set(entry.id, forKey: AppStorageKeys.activeAccountID)

        let user = try await fetchMe()
        currentUser = user
        ContributionWidgetContextStore.saveActor(user.canonicalName)
        authPhase = .authenticated
        await refreshNeedsAttentionSnapshot()
    }

    /// Remove a stored account. Switches to another account if the removed account
    /// was active; signs out fully if it was the last account.
    func removeAccount(id: String) async {
        accounts.removeAll { $0.id == id }
        try? KeychainHelper.saveAccounts(accounts)

        guard id == activeAccountID else { return }

        if let next = accounts.first {
            try? await switchAccount(to: next.id)
        } else {
            await signOut()
        }
    }

    func signOut() async {
        clearSessionState()
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        await clearWebData()
        clearWebContentRenderCaches()
        NeedsAttentionSnapshotStore.clear()
        SystemStatusWidgetSnapshotStore.clear()
        authPhase = .unauthenticated
        selectedTab = .home
    }

    func resetAppData() async {
        clearSessionState()

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        await clearWebData()
        clearWebContentRenderCaches()
        NeedsAttentionSnapshotStore.clear()
        SystemStatusWidgetSnapshotStore.clear()

        authPhase = .unauthenticated
        selectedTab = .home
    }

    // MARK: - Deep link resolution

    /// Resolve a repository by owner and name for deep linking.
    func resolveRepository(owner: String, name: String, service: SRHTService = .git) async throws -> RepositorySummary {
        let result = try await client.execute(
            service: service,
            query: Self.repoLookupQuery,
            variables: ["owner": owner, "name": name],
            responseType: RepoLookupResponse.self
        )
        return result.user.repository
    }

    /// Resolve a tracker by owner and name for deep linking.
    func resolveTracker(owner: String, name: String) async throws -> TrackerSummary {
        let result = try await client.execute(
            service: .todo,
            query: Self.trackerLookupQuery,
            variables: ["owner": owner, "name": name],
            responseType: TrackerLookupResponse.self
        )
        return result.user.tracker
    }

    func resolveProjectSource(_ source: Project.SourceRepo) async throws -> RepositorySummary {
        try await resolveRepository(
            owner: source.ownerUsername,
            name: source.name,
            service: source.repoType.service
        )
    }

    func resolveProjectTracker(_ tracker: Project.Tracker) async throws -> TrackerSummary {
        try await resolveTracker(owner: tracker.ownerUsername, name: tracker.name)
    }

    func openProjectSource(_ source: Project.SourceRepo) async throws {
        let repository = try await resolveProjectSource(source)
        navigateToRepository(repository)
    }

    func openProjectTracker(_ tracker: Project.Tracker) async throws {
        let resolvedTracker = try await resolveProjectTracker(tracker)
        navigateToTracker(resolvedTracker)
    }

    func openMailingList(_ mailingList: InboxMailingListReference) {
        navigateToMailingList(mailingList)
    }

    func openSystemStatus() {
        navigateToSystemStatus()
    }

    func navigateToRepository(_ repository: RepositorySummary) {
        pendingTabNavigation = .repository(repository)
        selectedTab = .repositories
    }

    func navigateToTracker(_ tracker: TrackerSummary) {
        pendingTabNavigation = .tracker(tracker)
        selectedTab = .tickets
    }

    func navigateToBuild(jobId: Int) {
        pendingDeepLink = .build(jobId: jobId)
        selectedTab = .builds
    }

    func navigateToTicket(ownerUsername: String, trackerName: String, ticketId: Int) {
        pendingDeepLink = .ticket(owner: ownerUsername, tracker: trackerName, ticketId: ticketId)
        selectedTab = .tickets
    }

    func navigateToMailingList(_ mailingList: InboxMailingListReference) {
        pendingTabNavigation = .mailingList(mailingList)
        selectedTab = .more
    }

    func navigateToSystemStatus() {
        pendingTabNavigation = .systemStatus
        selectedTab = .more
    }

    func navigateToBuildsList() {
        pendingTabNavigation = .builds
        selectedTab = .builds
    }

    func presentRepositoryDeepLinkError() {
        deepLinkError = "The repository could not be found or is inaccessible."
    }

    func presentTicketDeepLinkError() {
        deepLinkError = "The ticket could not be found or is inaccessible."
    }

    // MARK: - Private

    private static let meQuery = """
    {
        me {
            id
            username
            canonicalName
            email
            avatar
        }
    }
    """

    private struct MeResponse: Decodable {
        let me: User
    }

    private func fetchMe() async throws -> User {
        try await fetchMe(using: client)
    }

    private func fetchMe(using srhtClient: SRHTClient) async throws -> User {
        let result = try await srhtClient.execute(
            service: .meta,
            query: Self.meQuery,
            responseType: MeResponse.self
        )
        return result.me
    }

    // MARK: - Deep link queries

    private static let repoLookupQuery = """
    query repoLookup($owner: String!, $name: String!) {
        user(username: $owner) {
            repository(name: $name) {
                id rid name description visibility updated
                owner { canonicalName }
                HEAD { name target }
            }
        }
    }
    """

    private struct RepoLookupResponse: Decodable, Sendable {
        let user: RepoLookupUser
    }

    private struct RepoLookupUser: Decodable, Sendable {
        let repository: RepositorySummary
    }

    private static let trackerLookupQuery = """
    query trackerLookup($owner: String!, $name: String!) {
        user(username: $owner) {
            tracker(name: $name) {
                id rid name description visibility updated
                owner { canonicalName }
            }
        }
    }
    """

    private struct TrackerLookupResponse: Decodable, Sendable {
        let user: TrackerLookupUser
    }

    private struct TrackerLookupUser: Decodable, Sendable {
        let tracker: TrackerSummary
    }

    private func clearSessionState() {
        try? KeychainHelper.deleteAll()
        client.setToken(nil)
        client.responseCache.clear()
        accounts = []
        activeAccountID = ""
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.activeAccountID)
        currentUser = nil
        ContributionWidgetContextStore.clear()
        pendingDeepLink = nil
        pendingTabNavigation = nil
        deepLinkError = nil
        selectedTab = .home
    }

    private func refreshNeedsAttentionSnapshot() async {
        guard let currentUser else {
            NeedsAttentionSnapshotStore.clear()
            return
        }

        let viewModel = HomeViewModel(
            currentUser: currentUser,
            client: client,
            systemStatusRepository: systemStatusRepository
        )
        await viewModel.loadDashboard()
    }

    private func clearWebData() async {
        await withCheckedContinuation { continuation in
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            let since = Date(timeIntervalSince1970: 0)
            WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: since) {
                continuation.resume()
            }
        }
    }
}
