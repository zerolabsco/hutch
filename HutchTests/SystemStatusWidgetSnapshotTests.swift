import Foundation
import Testing
@testable import Hutch

@MainActor
struct SystemStatusWidgetSnapshotTests {

    @Test
    func saveAndLoadRoundTrips() {
        let defaultsName = "SystemStatusWidgetSnapshotTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let snapshot = SystemStatusWidgetSnapshot(
            services: [
                .init(id: "git", name: "git.sr.ht", status: "Operational", requiresAttention: false),
                .init(id: "builds", name: "builds.sr.ht", status: "Degraded", requiresAttention: true),
            ],
            hasDisruption: true,
            overallStatusText: "Experiencing disruptions",
            bannerSummary: "builds.sr.ht disrupted",
            updatedAt: Date(timeIntervalSince1970: 1000)
        )

        SystemStatusWidgetSnapshotStore.save(snapshot, defaults: defaults)
        let loaded = SystemStatusWidgetSnapshotStore.load(defaults: defaults)

        #expect(loaded != nil)
        #expect(loaded?.services.count == 2)
        #expect(loaded?.hasDisruption == true)
        #expect(loaded?.bannerSummary == "builds.sr.ht disrupted")
        #expect(loaded?.services[0].name == "git.sr.ht")
        #expect(loaded?.services[1].requiresAttention == true)
    }

    @Test
    func loadReturnsNilWhenEmpty() {
        let defaultsName = "SystemStatusWidgetSnapshotTests-empty-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let loaded = SystemStatusWidgetSnapshotStore.load(defaults: defaults)
        #expect(loaded == nil)
    }

    @Test
    func clearRemovesSnapshot() {
        let defaultsName = "SystemStatusWidgetSnapshotTests-clear-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let snapshot = SystemStatusWidgetSnapshot(
            services: [.init(id: "meta", name: "meta.sr.ht", status: "Operational", requiresAttention: false)],
            hasDisruption: false,
            overallStatusText: "All monitored services operational",
            bannerSummary: "",
            updatedAt: .now
        )

        SystemStatusWidgetSnapshotStore.save(snapshot, defaults: defaults)
        #expect(SystemStatusWidgetSnapshotStore.load(defaults: defaults) != nil)

        SystemStatusWidgetSnapshotStore.clear(defaults: defaults)
        #expect(SystemStatusWidgetSnapshotStore.load(defaults: defaults) == nil)
    }

    @Test
    func snapshotsAreIsolatedPerAccount() {
        let defaultsName = "SystemStatusWidgetSnapshotTests-isolation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let firstSnapshot = SystemStatusWidgetSnapshot(
            services: [.init(id: "git", name: "git.sr.ht", status: "Operational", requiresAttention: false)],
            hasDisruption: false,
            overallStatusText: "All monitored services operational",
            bannerSummary: "",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let secondSnapshot = SystemStatusWidgetSnapshot(
            services: [.init(id: "builds", name: "builds.sr.ht", status: "Degraded", requiresAttention: true)],
            hasDisruption: true,
            overallStatusText: "Experiencing disruptions",
            bannerSummary: "builds.sr.ht disrupted",
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        SystemStatusWidgetSnapshotStore.save(firstSnapshot, accountID: "account-a", defaults: defaults)
        SystemStatusWidgetSnapshotStore.save(secondSnapshot, accountID: "account-b", defaults: defaults)

        #expect(SystemStatusWidgetSnapshotStore.load(accountID: "account-a", defaults: defaults)?.services.first?.name == "git.sr.ht")
        #expect(SystemStatusWidgetSnapshotStore.load(accountID: "account-b", defaults: defaults)?.services.first?.name == "builds.sr.ht")

        ActiveAccountContextStore.save("account-b", defaults: defaults)
        #expect(SystemStatusWidgetSnapshotStore.load(defaults: defaults)?.bannerSummary == "builds.sr.ht disrupted")
    }

    @Test
    func unavailableSnapshotHasEmptyServices() {
        let snapshot = SystemStatusWidgetSnapshot.unavailable
        #expect(snapshot.services.isEmpty)
        #expect(snapshot.hasDisruption == false)
    }
}
