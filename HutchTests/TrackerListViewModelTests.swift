import Foundation
import Testing
@testable import Hutch

struct TrackerListViewModelTests {

    @Test
    @MainActor
    func graphQLErrorDescriptionIsPreservedForTrackerCreationFailures() {
        let error = SRHTError.graphQLErrors([
            GraphQLError(message: "A tracker named bugs already exists", locations: nil)
        ])

        #expect(error.localizedDescription == "GraphQL error: A tracker named bugs already exists")
    }

    @Test
    func filteredTrackersReturnsAllWhenSearchTextIsEmpty() {
        let trackers = [
            makeTracker(id: 1, name: "bugs", description: "Bug tracker", owner: "~owner"),
            makeTracker(id: 2, name: "ideas", description: nil, owner: "~team")
        ]

        let filtered = filterTrackers(trackers, query: "")

        #expect(filtered.count == 2)
    }

    @Test
    func filteredTrackersMatchesDescription() {
        let trackers = [
            makeTracker(id: 1, name: "bugs", description: "Production incidents", owner: "~owner"),
            makeTracker(id: 2, name: "ideas", description: "Feature requests", owner: "~team")
        ]

        let filtered = filterTrackers(trackers, query: "incident")

        #expect(filtered.map(\.id) == [1])
    }

    @Test
    func filteredTrackersMatchesOwner() {
        let trackers = [
            makeTracker(id: 1, name: "bugs", description: nil, owner: "~owner"),
            makeTracker(id: 2, name: "ideas", description: nil, owner: "~team")
        ]

        let filtered = filterTrackers(trackers, query: "~team")

        #expect(filtered.map(\.id) == [2])
    }

    private func filterTrackers(_ trackers: [TrackerSummary], query: String) -> [TrackerSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return trackers }
        return trackers.filter {
            $0.name.lowercased().contains(q) ||
            ($0.description?.lowercased().contains(q) == true) ||
            $0.owner.canonicalName.lowercased().contains(q)
        }
    }

    private func makeTracker(id: Int, name: String, description: String?, owner: String) -> TrackerSummary {
        TrackerSummary(
            id: id,
            rid: "rid-\(id)",
            name: name,
            description: description,
            visibility: .public,
            updated: Date(),
            owner: Entity(canonicalName: owner)
        )
    }
}
