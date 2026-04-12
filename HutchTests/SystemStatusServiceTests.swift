import Foundation
import Testing
@testable import Hutch

struct SystemStatusServiceTests {

    @Test
    func parsesCurrentStatusHTMLIntoServicesAndActiveIncidents() throws {
        let snapshot = try SystemStatusService.parseSnapshotHTML(Self.sampleHTML, fetchedAt: Date(timeIntervalSince1970: 100))

        #expect(snapshot.services.count == 3)
        #expect(snapshot.services[0].name == "git.sr.ht")
        #expect(snapshot.services[0].status == .degraded)
        #expect(snapshot.services[1].status == .operational)
        #expect(snapshot.hasDisruption)
        #expect(snapshot.activeIncidents.count == 1)
        #expect(snapshot.activeIncidents[0].title == "SourceHut disrupted due to DDoS attack")
        #expect(snapshot.activeIncidents[0].summary == "SourceHut was disrupted by a DDoS attack.")
        #expect(snapshot.activeIncidents[0].url?.absoluteString == "https://status.sr.ht/issues/2026-04-06-ddos-attack/")
    }

    @Test
    func parsesStatusHTMLWithClassOrderChangesAndTimeElements() throws {
        let snapshot = try SystemStatusService.parseSnapshotHTML(Self.variantHTML, fetchedAt: .now)

        #expect(snapshot.services.count == 2)
        #expect(snapshot.services[0].status == .operational)
        #expect(snapshot.services[1].status == .majorOutage)
        #expect(snapshot.activeIncidents.count == 1)
        #expect(snapshot.activeIncidents[0].title == "builds.sr.ht outage")
        #expect(snapshot.activeIncidents[0].publishedAt == ISO8601DateFormatter().date(from: "2026-04-07T12:00:00Z"))
    }

    @Test
    func parsesIncidentFeedRSS() async throws {
        let incidents = try await SystemStatusService.parseIncidentFeedXML(Data(Self.sampleRSS.utf8))

        #expect(incidents.count == 2)
        #expect(incidents[0].title == "SourceHut disrupted due to DDoS attack")
        #expect(incidents[0].isActive == true)
        #expect(incidents[0].summary == "SourceHut was disrupted by a DDoS attack.")
        #expect(incidents[1].title == "Planned maintenance on all services")
        #expect(incidents[1].isActive == false)
        #expect(incidents[1].updatedAt != nil)
    }

    @Test
    func parsesIncidentFeedWithISO8601Dates() async throws {
        let incidents = try await SystemStatusService.parseIncidentFeedXML(Data(Self.variantRSS.utf8))

        #expect(incidents.count == 1)
        #expect(incidents[0].title == "Status feed moved")
        #expect(incidents[0].publishedAt == ISO8601DateFormatter().date(from: "2026-04-07T15:30:00Z"))
    }

    @Test
    func bannerSummaryPrefersSpecificServiceThenCount() {
        let operational = SystemStatusSnapshot(
            services: [
                StatusServiceState(id: "git.sr.ht", name: "git.sr.ht", slug: "git.sr.ht", status: .operational, description: nil)
            ],
            activeIncidents: [],
            lastUpdated: .now
        )

        let oneDisrupted = SystemStatusSnapshot(
            services: [
                StatusServiceState(id: "git.sr.ht", name: "git.sr.ht", slug: "git.sr.ht", status: .degraded, description: nil),
                StatusServiceState(id: "hg.sr.ht", name: "hg.sr.ht", slug: "hg.sr.ht", status: .operational, description: nil)
            ],
            activeIncidents: [],
            lastUpdated: .now
        )

        let multipleDisrupted = SystemStatusSnapshot(
            services: [
                StatusServiceState(id: "git.sr.ht", name: "git.sr.ht", slug: "git.sr.ht", status: .degraded, description: nil),
                StatusServiceState(id: "builds.sr.ht", name: "builds.sr.ht", slug: "builds.sr.ht", status: .majorOutage, description: nil)
            ],
            activeIncidents: [],
            lastUpdated: .now
        )

        #expect(operational.hasDisruption == false)
        #expect(oneDisrupted.bannerSummary == "git.sr.ht disrupted")
        #expect(multipleDisrupted.bannerSummary == "2 services disrupted")
    }

    private static let sampleHTML = #"""
    <!DOCTYPE html>
    <html>
    <body class="status-homepage status-disrupted">
    <div class="announcement-box" style="border-bottom: 0">
      <div class="padding">
        <p>
          <a href="/issues/2026-04-06-ddos-attack/"><strong class="bold">SourceHut disrupted due to DDoS attack →</strong></a>
        </p>
        <p><small><a href="/affected/git.sr.ht/" class="tag no-underline">git.sr.ht</a></small></p>
        <p><strong>SourceHut was disrupted by a DDoS attack</strong>.</p>
      </div>
      <hr class="clean announcement-box">
    </div>
    <div class="components">
      <div class="component" data-status="disrupted">
        <a href="/affected/git.sr.ht/" class="no-underline">git.sr.ht</a>
        <span class="component-status">Disrupted</span>
      </div>
      <div class="component" data-status="ok">
        <a href="/affected/hg.sr.ht/" class="no-underline">hg.sr.ht</a>
        <span class="component-status">Operational</span>
      </div>
      <div class="component" data-status="notice">
        <a href="/affected/man.sr.ht/" class="no-underline">man.sr.ht</a>
        <span class="component-status">Maintenance</span>
      </div>
    </div>
    <a href="https://status.sr.ht/issues/2026-04-06-ddos-attack/" class="issue no-underline">
      <small class="date float-right " title="Apr 5 10:00:00 2026 UTC">April 5, 2026 at 10:00 AM UTC</small>
      <h3>SourceHut disrupted due to DDoS attack</h3>
      <strong class="error">▲ This issue is not resolved yet</strong>
    </a>
    </body>
    </html>
    """#

    private static let variantHTML = #"""
    <html>
    <body>
      <div class="component extra" data-status="ok">
        <a class="no-underline" href="/affected/meta.sr.ht/">meta.sr.ht</a>
        <small class="component-status secondary">All systems operational</small>
      </div>
      <div data-status="down" class="extra component">
        <a href="/affected/builds.sr.ht/" class="link">builds.sr.ht</a>
        <div class="component-status badge">Outage</div>
      </div>
      <div class="announcement-box">
        <div class="padding">
          <p><a href="/issues/2026-04-07-builds-outage/"><strong>builds.sr.ht outage</strong></a></p>
          <p><strong>Build jobs are currently failing.</strong></p>
        </div>
      </div>
      <a class="issue no-underline urgent" href="/issues/2026-04-07-builds-outage/">
        <time class="date" datetime="2026-04-07T12:00:00Z">Apr 7</time>
        <h4>builds.sr.ht outage</h4>
        <span>Investigating elevated failures</span>
      </a>
    </body>
    </html>
    """#

    private static let sampleRSS = #"""
    <?xml version="1.0" encoding="utf-8" standalone="yes"?>
    <rss version="2.0">
      <channel>
        <title>sr.ht status</title>
        <item>
          <title>SourceHut disrupted due to DDoS attack</title>
          <link>https://status.sr.ht/issues/2026-04-06-ddos-attack/</link>
          <pubDate>Sun, 05 Apr 2026 10:00:00 +0000</pubDate>
          <guid>https://status.sr.ht/issues/2026-04-06-ddos-attack/</guid>
          <category></category>
          <description>&lt;p&gt;&lt;strong&gt;SourceHut was disrupted by a DDoS attack&lt;/strong&gt;.&lt;/p&gt;</description>
        </item>
        <item>
          <title>[Resolved] Planned maintenance on all services</title>
          <link>https://status.sr.ht/issues/2025-10-22-planned-maintenance/</link>
          <pubDate>Wed, 22 Oct 2025 11:00:00 +0000</pubDate>
          <guid>https://status.sr.ht/issues/2025-10-22-planned-maintenance/</guid>
          <category>2025-10-22 12:25:00</category>
          <description>&lt;p&gt;&lt;strong&gt;The maintenance is complete&lt;/strong&gt;.&lt;/p&gt;</description>
        </item>
      </channel>
    </rss>
    """#

    private static let variantRSS = #"""
    <?xml version="1.0" encoding="utf-8" standalone="yes"?>
    <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel>
        <title>sr.ht status</title>
        <item>
          <title>Status feed moved</title>
          <link>https://status.sr.ht/issues/2026-04-07-feed-moved/</link>
          <dc:date>2026-04-07T15:30:00Z</dc:date>
          <guid>https://status.sr.ht/issues/2026-04-07-feed-moved/</guid>
          <description>&lt;p&gt;Use the new feed endpoint.&lt;/p&gt;</description>
        </item>
      </channel>
    </rss>
    """#
}
