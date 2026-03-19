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

    var selectedTab: Tab = .home

    // MARK: - Current user (populated after successful validation)

    private(set) var currentUser: User?

    // MARK: - Networking

    let client: SRHTClient

    // MARK: - Deep link pending navigation

    /// Set by the deep link handler; consumed by RootView to drive navigation.
    var pendingDeepLink: DeepLink?
    var pendingTabNavigation: TabNavigationTarget?

    // MARK: - Init

    init() {
        let token = KeychainHelper.loadToken()
        self.client = SRHTClient(token: token)
    }

    // MARK: - Launch validation

    /// Called once at app launch. If a token exists in Keychain, validates it
    /// silently. On failure, clears the token and falls through to unauthenticated.
    func validateOnLaunch() async {
        guard client.hasToken else {
            authPhase = .unauthenticated
            return
        }

        do {
            let user = try await fetchMe()
            currentUser = user
            authPhase = .authenticated
        } catch {
            try? KeychainHelper.deleteToken()
            client.setToken(nil)
            currentUser = nil
            authPhase = .unauthenticated
        }
    }

    // MARK: - Token management

    /// Validate a new token by querying meta.sr.ht, then persist it.
    /// Throws on network/GraphQL errors so the caller can display the message.
    func connect(with token: String) async throws {
        // Temporarily set the token so the client can use it for the request.
        client.setToken(token)

        do {
            let user = try await fetchMe()
            try KeychainHelper.saveToken(token)
            currentUser = user
            authPhase = .authenticated
        } catch {
            // Roll back — don't leave an invalid token in the client.
            client.setToken(nil)
            throw error
        }
    }

    func signOut() async {
        clearSessionState()
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        await clearWebData()
        clearWebContentRenderCaches()
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
        pendingTabNavigation = .repository(repository)
        selectedTab = .repositories
    }

    func openProjectTracker(_ tracker: Project.Tracker) async throws {
        let resolvedTracker = try await resolveProjectTracker(tracker)
        pendingTabNavigation = .tracker(resolvedTracker)
        selectedTab = .tickets
    }

    func openMailingList(_ mailingList: InboxMailingListReference) {
        pendingTabNavigation = .mailingList(mailingList)
        selectedTab = .more
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
        let result = try await client.execute(
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
        currentUser = nil
        pendingDeepLink = nil
        pendingTabNavigation = nil
        selectedTab = .home
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
