import Foundation
import Testing
@testable import Hutch

struct SystemStatusRepositoryTests {

    @Test
    func fallsBackToPersistedSnapshotWhenRefreshFails() async throws {
        let defaultsName = "SystemStatusRepositoryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let cachedSnapshot = SystemStatusSnapshot(
            services: [
                StatusServiceState(id: "git.sr.ht", name: "git.sr.ht", slug: "git.sr.ht", status: .degraded, description: nil)
            ],
            activeIncidents: [],
            lastUpdated: Date(timeIntervalSince1970: 120)
        )
        let cacheStore = SystemStatusCacheStore(defaults: defaults)
        let initialRepository = SystemStatusRepository(
            service: TestSystemStatusService(
                snapshotHTMLHandler: { Self.cachedSnapshotHTML },
                incidentsDataHandler: { Data(Self.emptyRSS.utf8) }
            ),
            cacheStore: cacheStore,
            now: { Date(timeIntervalSince1970: 120) }
        )

        _ = try await initialRepository.snapshotResult(forceRefresh: true)

        let fallbackRepository = SystemStatusRepository(
            service: TestSystemStatusService(
                snapshotHTMLHandler: { throw SRHTError.httpError(503) },
                incidentsDataHandler: { Data(Self.emptyRSS.utf8) }
            ),
            ttl: 0,
            cacheStore: cacheStore,
            now: { Date(timeIntervalSince1970: 180) }
        )

        let result = try await fallbackRepository.snapshotResult(forceRefresh: true)

        #expect(result.value == cachedSnapshot)
        #expect(result.isStale)
        #expect(result.lastSuccessfulAt == Date(timeIntervalSince1970: 120))
        #expect(result.refreshErrorMessage != nil)
    }

    @Test
    func fallsBackToPersistedIncidentsWhenRefreshFails() async throws {
        let defaultsName = "SystemStatusRepositoryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let cachedIncidents = [
            StatusIncident(
                id: "incident-1",
                title: "builds.sr.ht outage",
                summary: "Builds are failing.",
                url: nil,
                publishedAt: Date(timeIntervalSince1970: 200),
                updatedAt: nil,
                isActive: true
            )
        ]
        let cacheStore = SystemStatusCacheStore(defaults: defaults)
        let initialRepository = SystemStatusRepository(
            service: TestSystemStatusService(
                snapshotHTMLHandler: { Self.cachedOperationalHTML },
                incidentsDataHandler: { Data(Self.cachedIncidentRSS.utf8) }
            ),
            cacheStore: cacheStore,
            now: { Date(timeIntervalSince1970: 220) }
        )

        _ = try await initialRepository.recentIncidentsResult(forceRefresh: true)

        let fallbackRepository = SystemStatusRepository(
            service: TestSystemStatusService(
                snapshotHTMLHandler: { Self.cachedOperationalHTML },
                incidentsDataHandler: { throw SRHTError.httpError(504) }
            ),
            ttl: 0,
            cacheStore: cacheStore,
            now: { Date(timeIntervalSince1970: 260) }
        )

        let result = try await fallbackRepository.recentIncidentsResult(forceRefresh: true)

        #expect(result.value == cachedIncidents)
        #expect(result.isStale)
        #expect(result.lastSuccessfulAt == Date(timeIntervalSince1970: 220))
        #expect(result.refreshErrorMessage != nil)
    }
}

private struct TestSystemStatusService: SystemStatusServing {
    let snapshotHTMLHandler: @Sendable () async throws -> String
    let incidentsDataHandler: @Sendable () async throws -> Data

    func fetchSnapshotHTML() async throws -> String {
        try await snapshotHTMLHandler()
    }

    func fetchIncidentFeedData() async throws -> Data {
        try await incidentsDataHandler()
    }
}

private extension SystemStatusRepositoryTests {
    static let cachedSnapshotHTML = #"""
    <div class="component" data-status="disrupted">
      <a href="/affected/git.sr.ht/">git.sr.ht</a>
      <span class="component-status">Disrupted</span>
    </div>
    """#

    static let cachedOperationalHTML = #"""
    <div class="component" data-status="ok">
      <a href="/affected/meta.sr.ht/">meta.sr.ht</a>
      <span class="component-status">Operational</span>
    </div>
    """#

    static let cachedIncidentRSS = #"""
    <rss version="2.0">
      <channel>
        <item>
          <title>builds.sr.ht outage</title>
          <link>https://status.sr.ht/issues/1/</link>
          <pubDate>Thu, 01 Jan 1970 00:03:20 +0000</pubDate>
          <guid>incident-1</guid>
          <description>&lt;p&gt;Builds are failing.&lt;/p&gt;</description>
        </item>
      </channel>
    </rss>
    """#

    static let emptyRSS = #"""
    <rss version="2.0">
      <channel></channel>
    </rss>
    """#
}
