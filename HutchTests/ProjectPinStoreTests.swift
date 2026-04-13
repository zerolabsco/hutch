import Foundation
import Testing
@testable import Hutch

struct ProjectPinStoreTests {
    @Test
    func storesPinnedProjectsPerUser() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        ProjectPinStore.togglePin(projectID: "project-1", for: "~alice", defaults: defaults)
        ProjectPinStore.togglePin(projectID: "project-2", for: "~bob", defaults: defaults)

        #expect(ProjectPinStore.loadPinnedProjectIDs(for: "~alice", defaults: defaults) == ["project-1"])
        #expect(ProjectPinStore.loadPinnedProjectIDs(for: "~bob", defaults: defaults) == ["project-2"])
    }

    @Test
    func toggleRemovesExistingPin() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        ProjectPinStore.togglePin(projectID: "project-1", for: "~alice", defaults: defaults)
        ProjectPinStore.togglePin(projectID: "project-1", for: "~alice", defaults: defaults)

        #expect(ProjectPinStore.loadPinnedProjectIDs(for: "~alice", defaults: defaults).isEmpty)
    }

    @Test
    func loadPinnedProjectsNormalizesWhitespaceAndDuplicates() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let encoded = try! JSONEncoder().encode([
            "~alice": [" project-1 ", "", "project-1", "project-2"]
        ])
        defaults.set(encoded, forKey: AppStorageKeys.pinnedHomeProjects)

        #expect(ProjectPinStore.loadPinnedProjectIDs(for: "~alice", defaults: defaults) == ["project-1", "project-2"])
    }
}
