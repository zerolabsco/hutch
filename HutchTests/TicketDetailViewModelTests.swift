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

    @Test
    @MainActor
    func ticketUpdateInputOmitsUnchangedFields() {
        let input = TicketDetailViewModel.ticketUpdateInput(
            subject: "Same subject",
            body: "Same body",
            currentSubject: "Same subject",
            currentBody: "Same body"
        )

        #expect(input.isEmpty)
    }

    @Test
    @MainActor
    func ticketUpdateInputCarriesOnlyTheChangedField() {
        let input = TicketDetailViewModel.ticketUpdateInput(
            subject: "New subject",
            body: "Same body",
            currentSubject: "Old subject",
            currentBody: "Same body"
        )

        #expect(input["subject"] as? String == "New subject")
        #expect(!input.keys.contains("body"))
    }

    @Test
    @MainActor
    func ticketUpdateInputTrimsWhitespaceBeforeComparing() {
        let input = TicketDetailViewModel.ticketUpdateInput(
            subject: "  Same subject  ",
            body: "\n Same body \n",
            currentSubject: "Same subject",
            currentBody: "Same body"
        )

        #expect(input.isEmpty)
    }

    @Test
    @MainActor
    func ticketUpdateInputUsesNilToClearBody() {
        let input = TicketDetailViewModel.ticketUpdateInput(
            subject: "Same subject",
            body: "   ",
            currentSubject: "Same subject",
            currentBody: "Existing body"
        )

        // The key must survive with a nil value so it encodes as a JSON null and
        // actually clears the body, rather than being dropped from the mutation.
        #expect(input.keys.contains("body"))
        #expect(input["body"] as? String == nil)
    }

    @Test
    @MainActor
    func ticketUpdateInputTreatsNilBodyAsEmpty() {
        let input = TicketDetailViewModel.ticketUpdateInput(
            subject: "Same subject",
            body: "",
            currentSubject: "Same subject",
            currentBody: nil
        )

        #expect(input.isEmpty)
    }
}
