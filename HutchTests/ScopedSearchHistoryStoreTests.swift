import Foundation
import Testing
@testable import Hutch

struct ScopedSearchHistoryStoreTests {

    @Test
    func recordsMostRecentUniqueSearchPerScopeFirst() {
        let suiteName = "ScopedSearchHistoryStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        ScopedSearchHistoryStore.record(
            query: "hutch",
            scopeID: "repositories",
            defaults: defaults,
            now: Date(timeIntervalSince1970: 100)
        )
        ScopedSearchHistoryStore.record(
            query: "running",
            scopeID: "builds",
            defaults: defaults,
            now: Date(timeIntervalSince1970: 200)
        )
        ScopedSearchHistoryStore.record(
            query: "Hutch",
            scopeID: "repositories",
            defaults: defaults,
            now: Date(timeIntervalSince1970: 300)
        )

        let repositoryHistory = ScopedSearchHistoryStore.load(scopeID: "repositories", defaults: defaults)
        let buildHistory = ScopedSearchHistoryStore.load(scopeID: "builds", defaults: defaults)

        #expect(repositoryHistory.map(\.query) == ["Hutch"])
        #expect(repositoryHistory.first?.createdAt == Date(timeIntervalSince1970: 300))
        #expect(buildHistory.map(\.query) == ["running"])
    }

    @Test
    func clearsOnlyRequestedScope() {
        let suiteName = "ScopedSearchHistoryStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        ScopedSearchHistoryStore.record(query: "repo", scopeID: "repositories", defaults: defaults)
        ScopedSearchHistoryStore.record(query: "ticket", scopeID: "tickets.rid", defaults: defaults)

        ScopedSearchHistoryStore.clear(scopeID: "repositories", defaults: defaults)

        #expect(ScopedSearchHistoryStore.load(scopeID: "repositories", defaults: defaults).isEmpty)
        #expect(ScopedSearchHistoryStore.load(scopeID: "tickets.rid", defaults: defaults).map(\.query) == ["ticket"])
    }
}
