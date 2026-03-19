import Foundation
import Testing
@testable import Hutch

struct TicketDetailViewModelTests {

    @Test
    @MainActor
    func reopenStatusInputOmitsResolution() {
        let input = TicketDetailViewModel.statusUpdateInput(
            status: .reported,
            resolution: .unresolved
        )

        #expect(input["status"] as? String == TicketStatus.reported.rawValue)
        #expect(input["resolution"] == nil)
    }

    @Test
    @MainActor
    func resolveStatusInputIncludesResolution() {
        let input = TicketDetailViewModel.statusUpdateInput(
            status: .resolved,
            resolution: .fixed
        )

        #expect(input["status"] as? String == TicketStatus.resolved.rawValue)
        #expect(input["resolution"] as? String == TicketResolution.fixed.rawValue)
    }
}
