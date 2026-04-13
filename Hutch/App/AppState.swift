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
    private(set) var authStatusMessage = "Connecting…"

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

    private(set) var client: SRHTClient
    let configuration: AppConfiguration
    private(set) var systemStatusRepository: SystemStatusRepository
    private var activeSession: AccountSession?
    private(set) var sessionIdentity = UUID()

    var accountDefaults: UserDefaults {
        activeSession?.defaults ?? .standard
    }

    // MARK: - Deep link pending navigation

    /// Set by the deep link handler; consumed by RootView to drive navigation.
    var pendingDeepLink: DeepLink?
    var pendingTabNavigation: TabNavigationTarget?
    var deepLinkError: String?

    // MARK: - Init

    init() {
        self.configuration = AppConfiguration()
        self.client = SRHTClient()
        self.systemStatusRepository = SystemStatusRepository()
    }

    // MARK: - Launch validation

    /// Called once at app launch. If a token exists in Keychain, validates it
    /// silently. On failure, clears the token and falls through to unauthenticated.
    func validateOnLaunch() async {
        authStatusMessage = "Connecting…"
        var storedAccounts = KeychainHelper.loadAccounts()

        if storedAccounts.isEmpty, let legacyToken = KeychainHelper.loadToken() {
            let legacyClient = SRHTClient(token: legacyToken)
            if let user = try? await fetchMe(using: legacyClient) {
                let entry = AccountEntry(id: UUID().uuidString, username: user.username, token: legacyToken)
                storedAccounts = [entry]
                try? KeychainHelper.saveAccounts(storedAccounts)
                try? KeychainHelper.deleteToken()
            } else {
                try? KeychainHelper.deleteToken()
                authPhase = .unauthenticated
                return
            }
        }

        guard !storedAccounts.isEmpty else {
            authPhase = .unauthenticated
            return
        }

        let savedID = UserDefaults.standard.string(forKey: AppStorageKeys.activeAccountID) ?? ""
        let orderedAccounts = prioritizedAccounts(storedAccounts, preferredID: savedID)
        var invalidIDs = Set<String>()

        for account in orderedAccounts {
            do {
                let session = try await makeSession(for: account)
                let filteredAccounts = storedAccounts.filter { !invalidIDs.contains($0.id) }
                accounts = filteredAccounts
                try? KeychainHelper.saveAccounts(filteredAccounts)
                activate(session)
                authPhase = .authenticated
                await refreshNeedsAttentionSnapshot()
                return
            } catch {
                invalidIDs.insert(account.id)
                clearAccountArtifacts(for: account.id)
            }
        }

        accounts = storedAccounts.filter { !invalidIDs.contains($0.id) }
        try? KeychainHelper.saveAccounts(accounts)
        clearActiveSessionState()
        authPhase = .unauthenticated
    }

    // MARK: - Token management

    /// Validate a new token by querying meta.sr.ht, then persist it.
    /// Throws on network/GraphQL errors so the caller can display the message.
    func connect(with token: String) async throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        try await addValidatedAccount(token: normalizedToken, activateNewAccount: true)
    }

    /// Validate a new token, add it as an account, and switch to it immediately.
    func addAccount(token: String) async throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        try await addValidatedAccount(token: normalizedToken, activateNewAccount: true)
    }

    /// Switch the active account and fully refresh the app.
    func switchAccount(to id: String) async throws {
        guard let entry = accounts.first(where: { $0.id == id }) else { return }
        let previousSession = activeSession

        authStatusMessage = "Switching Accounts…"
        authPhase = .launching
        sessionIdentity = UUID()

        do {
            let session = try await makeSession(for: entry)
            activate(session)
            resetNavigationState()
        } catch {
            if let previousSession {
                activate(previousSession)
                authPhase = .authenticated
            } else {
                clearActiveSessionState()
                authPhase = .unauthenticated
            }
            throw error
        }

        authPhase = .authenticated
        await refreshNeedsAttentionSnapshot()
    }

    /// Remove a stored account. Switches to another account if the removed account
    /// was active; signs out fully if it was the last account.
    func removeAccount(id: String) async {
        let removedWasActive = id == activeAccountID
        accounts.removeAll { $0.id == id }
        try? KeychainHelper.saveAccounts(accounts)
        clearAccountArtifacts(for: id)

        guard removedWasActive else { return }

        if let next = accounts.first {
            do {
                try await switchAccount(to: next.id)
            } catch {
                await removeAccount(id: next.id)
            }
        } else {
            await signOut()
        }
    }

    func signOut() async {
        clearActiveSessionState()
        try? KeychainHelper.deleteAll()
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        await clearWebData()
        clearWebContentRenderCaches()
        clearAllAccountArtifacts()
        authPhase = .unauthenticated
        selectedTab = .home
    }

    func resetAppData() async {
        clearActiveSessionState()

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }
        for account in accounts {
            AccountDefaultsStore.clear(accountID: account.id)
        }
        try? KeychainHelper.deleteAll()
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        await clearWebData()
        clearWebContentRenderCaches()
        clearAllAccountArtifacts()

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

    private func addValidatedAccount(token: String, activateNewAccount: Bool) async throws {
        let tempClient = SRHTClient(token: token)
        let user = try await fetchMe(using: tempClient)

        if let existing = accounts.first(where: {
            $0.username.caseInsensitiveCompare(user.username) == .orderedSame || $0.token == token
        }) {
            _ = existing
            throw AppStateError.duplicateAccount(username: user.username)
        }

        let entry = AccountEntry(id: UUID().uuidString, username: user.username, token: token)
        accounts.append(entry)
        try KeychainHelper.saveAccounts(accounts)

        guard activateNewAccount else { return }
        let session = try await makeSession(for: entry, knownUser: user)
        authStatusMessage = "Switching Accounts…"
        authPhase = .launching
        sessionIdentity = UUID()
        activate(session)
        resetNavigationState()
        authPhase = .authenticated
        await refreshNeedsAttentionSnapshot()
    }

    private func makeSession(for account: AccountEntry, knownUser: User? = nil) async throws -> AccountSession {
        let sessionClient = SRHTClient(token: account.token)
        let user: User
        if let knownUser {
            user = knownUser
        } else {
            user = try await fetchMe(using: sessionClient)
        }
        let defaults = AccountDefaultsStore.userDefaults(for: account.id)
        let repository = SystemStatusRepository(cacheStore: SystemStatusCacheStore(defaults: defaults))
        return AccountSession(
            account: account,
            user: user,
            client: sessionClient,
            defaults: defaults,
            systemStatusRepository: repository
        )
    }

    private func activate(_ session: AccountSession) {
        activeSession = session
        client = session.client
        systemStatusRepository = session.systemStatusRepository
        currentUser = session.user
        activeAccountID = session.account.id
        UserDefaults.standard.set(session.account.id, forKey: AppStorageKeys.activeAccountID)
        ActiveAccountContextStore.save(session.account.id)
        ContributionWidgetContextStore.saveActor(session.user.canonicalName, accountID: session.account.id)
        authStatusMessage = "Connecting…"
    }

    private func clearActiveSessionState() {
        client = SRHTClient()
        systemStatusRepository = SystemStatusRepository()
        activeSession = nil
        activeAccountID = ""
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.activeAccountID)
        ActiveAccountContextStore.clear()
        currentUser = nil
        sessionIdentity = UUID()
        resetNavigationState()
    }

    private func resetNavigationState() {
        pendingDeepLink = nil
        pendingTabNavigation = nil
        deepLinkError = nil
        selectedTab = .home
    }

    private func clearAccountArtifacts(for accountID: String) {
        AccountDefaultsStore.clear(accountID: accountID)
        ContributionWidgetContextStore.clear(accountID: accountID)
        NeedsAttentionSnapshotStore.clear(accountID: accountID)
        SystemStatusWidgetSnapshotStore.clear(accountID: accountID)
    }

    private func clearAllAccountArtifacts() {
        for account in accounts {
            clearAccountArtifacts(for: account.id)
        }
        ContributionWidgetContextStore.clear(accountID: nil)
        NeedsAttentionSnapshotStore.clear(accountID: nil)
        SystemStatusWidgetSnapshotStore.clear(accountID: nil)
        ActiveAccountContextStore.clear()
        accounts = []
    }

    private func prioritizedAccounts(_ accounts: [AccountEntry], preferredID: String) -> [AccountEntry] {
        guard let preferred = accounts.first(where: { $0.id == preferredID }) else { return accounts }
        return [preferred] + accounts.filter { $0.id != preferredID }
    }

    private func refreshNeedsAttentionSnapshot() async {
        guard let currentUser else {
            NeedsAttentionSnapshotStore.clear(accountID: activeAccountID)
            return
        }

        let viewModel = HomeViewModel(
            currentUser: currentUser,
            client: client,
            systemStatusRepository: systemStatusRepository,
            defaults: accountDefaults,
            accountID: activeAccountID
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

enum AppStateError: LocalizedError {
    case duplicateAccount(username: String)

    var errorDescription: String? {
        switch self {
        case .duplicateAccount(let username):
            "The account ~\(username) is already saved."
        }
    }
}
