import Foundation
import Testing
@testable import Hutch

struct TicketSavedFilterStoreTests {

    @Test
    func storesCurrentFilterStatePerTracker() {
        let suiteName = "TicketSavedFilterStoreTests-\(#function)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        TicketSavedFilterStore.saveCurrentState(
            TicketListFilterState(status: .all, labelIDs: [4, 1]),
            for: "tracker-a",
            defaults: defaults
        )
        TicketSavedFilterStore.saveCurrentState(
            TicketListFilterState(status: .resolved, labelIDs: [9]),
            for: "tracker-b",
            defaults: defaults
        )

        #expect(
            TicketSavedFilterStore.loadCurrentState(for: "tracker-a", defaults: defaults) ==
            TicketListFilterState(status: .all, labelIDs: [1, 4])
        )
        #expect(
            TicketSavedFilterStore.loadCurrentState(for: "tracker-b", defaults: defaults) ==
            TicketListFilterState(status: .resolved, labelIDs: [9])
        )
    }

    @Test
    func savesNamedFiltersPerTrackerAndReplacesDuplicateNames() {
        let suiteName = "TicketSavedFilterStoreTests-\(#function)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        _ = TicketSavedFilterStore.saveFilter(
            named: "Bugs",
            state: TicketListFilterState(status: .open, labelIDs: [1]),
            for: "tracker-a",
            defaults: defaults,
            now: Date(timeIntervalSince1970: 100)
        )
        _ = TicketSavedFilterStore.saveFilter(
            named: "bugs",
            state: TicketListFilterState(status: .resolved, labelIDs: [2]),
            for: "tracker-a",
            defaults: defaults,
            now: Date(timeIntervalSince1970: 200)
        )
        _ = TicketSavedFilterStore.saveFilter(
            named: "Needs Info",
            state: TicketListFilterState(status: .all, labelIDs: [3]),
            for: "tracker-b",
            defaults: defaults,
            now: Date(timeIntervalSince1970: 300)
        )

        let trackerAFilters = TicketSavedFilterStore.loadSavedFilters(for: "tracker-a", defaults: defaults)
        let trackerBFilters = TicketSavedFilterStore.loadSavedFilters(for: "tracker-b", defaults: defaults)

        #expect(trackerAFilters.count == 1)
        #expect(trackerAFilters.first?.name == "bugs")
        #expect(trackerAFilters.first?.state == TicketListFilterState(status: .resolved, labelIDs: [2]))
        #expect(trackerBFilters.map(\.name) == ["Needs Info"])
    }

    @Test
    func deletesSavedFilter() {
        let suiteName = "TicketSavedFilterStoreTests-\(#function)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let savedFilter = TicketSavedFilterStore.saveFilter(
            named: "Bugs",
            state: TicketListFilterState(status: .open, labelIDs: [1]),
            for: "tracker-a",
            defaults: defaults
        )

        TicketSavedFilterStore.deleteFilter(id: savedFilter!.id, for: "tracker-a", defaults: defaults)

        #expect(TicketSavedFilterStore.loadSavedFilters(for: "tracker-a", defaults: defaults).isEmpty)
    }
}
