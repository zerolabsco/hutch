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
}
