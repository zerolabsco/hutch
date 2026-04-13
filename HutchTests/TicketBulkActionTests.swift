import Testing
@testable import Hutch

struct TicketBulkActionTests {

    @Test
    func bulkActionResultFormatsSuccessMessage() {
        let result = TicketBulkActionResult(
            action: .close,
            totalCount: 3,
            updatedCount: 3,
            unchangedCount: 0,
            failures: []
        )

        #expect(result.title == "Close Complete")
        #expect(result.message == "Closed 3 tickets.")
    }

    @Test
    func bulkActionResultFormatsPartialFailureMessage() {
        let result = TicketBulkActionResult(
            action: .assign,
            totalCount: 4,
            updatedCount: 2,
            unchangedCount: 1,
            failures: [
                TicketBulkActionFailure(ticketID: 42, message: "Network error")
            ]
        )

        #expect(result.title == "Assign Partially Applied")
        #expect(result.message == "Assigned 2 tickets. 1 already assigned. Failed: #42.")
    }
}
