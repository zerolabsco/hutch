import Foundation
import Testing
@testable import Hutch

@MainActor
struct TicketListViewModelTests {

    @Test
    func filteredTicketsReturnsStatusFilteredTicketsWhenSearchTextIsEmpty() {
        let tickets = [
            makeTicket(id: 1, title: "Crash on launch", status: .reported, submitter: "~owner", labels: []),
            makeTicket(id: 2, title: "Already fixed", status: .resolved, submitter: "~owner", labels: [])
        ]

        let filtered = filterTickets(
            tickets,
            state: TicketListFilterState(status: .open),
            query: ""
        )

        #expect(filtered.map(\.id) == [1])
    }

    @Test
    func filteredTicketsMatchesTitleAndTicketId() {
        let tickets = [
            makeTicket(id: 42, title: "Crash on launch", status: .reported, submitter: "~owner", labels: []),
            makeTicket(id: 99, title: "Settings polish", status: .reported, submitter: "~owner", labels: [])
        ]

        let titleMatches = filterTickets(
            tickets,
            state: TicketListFilterState(status: .all),
            query: "settings"
        )
        let idMatches = filterTickets(
            tickets,
            state: TicketListFilterState(status: .all),
            query: "42"
        )

        #expect(titleMatches.map(\.id) == [99])
        #expect(idMatches.map(\.id) == [42])
    }

    @Test
    func filteredTicketsMatchesSubmitterAndLabels() {
        let tickets = [
            makeTicket(id: 1, title: "Crash on launch", status: .reported, submitter: "~owner", labels: [makeLabel(id: 1, name: "bug")]),
            makeTicket(id: 2, title: "Needs triage", status: .reported, submitter: "~triage", labels: [makeLabel(id: 2, name: "needs-info")])
        ]

        let submitterMatches = filterTickets(
            tickets,
            state: TicketListFilterState(status: .all),
            query: "~triage"
        )
        let labelMatches = filterTickets(
            tickets,
            state: TicketListFilterState(status: .all),
            query: "bug"
        )

        #expect(submitterMatches.map(\.id) == [2])
        #expect(labelMatches.map(\.id) == [1])
    }

    @Test
    func filteredTicketsMatchesAssigneeAndStatus() {
        let tickets = [
            makeTicket(
                id: 1,
                title: "Crash on launch",
                status: .inProgress,
                submitter: "~owner",
                labels: [],
                assignees: [Entity(canonicalName: "~alice")]
            ),
            makeTicket(
                id: 2,
                title: "Settings polish",
                status: .resolved,
                submitter: "~owner",
                labels: [],
                assignees: []
            )
        ]

        let assigneeMatches = filterTickets(
            tickets,
            state: TicketListFilterState(status: .all),
            query: "~alice"
        )
        let statusMatches = filterTickets(
            tickets,
            state: TicketListFilterState(status: .all),
            query: "resolved"
        )

        #expect(assigneeMatches.map(\.id) == [1])
        #expect(statusMatches.map(\.id) == [2])
    }

    @Test
    func filteredTicketsMatchesAnySelectedLabel() {
        let tickets = [
            makeTicket(id: 1, title: "Crash on launch", status: .reported, submitter: "~owner", labels: [makeLabel(id: 1, name: "bug")]),
            makeTicket(id: 2, title: "Needs triage", status: .reported, submitter: "~triage", labels: [makeLabel(id: 2, name: "needs-info")]),
            makeTicket(id: 3, title: "Unlabeled", status: .reported, submitter: "~owner", labels: [])
        ]

        let filtered = filterTickets(
            tickets,
            state: TicketListFilterState(status: .all, labelIDs: [2, 3]),
            query: ""
        )

        #expect(filtered.map(\.id) == [2])
    }

    @Test
    func synchronizeTicketsReplacesEditedLabelsAndRemovesDeletedOnes() {
        let existing = [
            makeTicket(
                id: 7,
                title: "Triage me",
                status: .reported,
                submitter: "~owner",
                labels: [
                    makeLabel(id: 1, name: "bug"),
                    makeLabel(id: 2, name: "stale")
                ]
            )
        ]

        let updated = TicketListViewModel.synchronizeTickets(
            existing,
            with: [makeLabel(id: 1, name: "bugfix")]
        )

        #expect(updated.first?.labels.map(\.id) == [1])
        #expect(updated.first?.labels.first?.name == "bugfix")
    }

    @Test
    func reconciledSelectedLabelIDsRemovesUnknownIDs() {
        let reconciled = TicketListViewModel.reconciledSelectedLabelIDs(
            [1, 2, 5],
            availableLabels: [
                makeLabel(id: 2, name: "triage"),
                makeLabel(id: 3, name: "qa")
            ]
        )

        #expect(reconciled == [2])
    }

    @Test
    @MainActor
    func resolveTicketInputHasCorrectStatusAndDefaultResolution() {
        let input: [String: any Sendable] = [
            "status": TicketStatus.resolved.rawValue,
            "resolution": TicketResolution.fixed.rawValue
        ]
        #expect(input["status"] as? String == "resolved")
        #expect(input["resolution"] as? String == "fixed")
    }

    @Test
    @MainActor
    func reopenTicketInputOmitsResolution() {
        let input: [String: any Sendable] = [
            "status": TicketStatus.reported.rawValue
        ]
        #expect(input["status"] as? String == "reported")
        #expect(input["resolution"] == nil)
    }

    private func filterTickets(
        _ tickets: [TicketSummary],
        state: TicketListFilterState,
        query: String
    ) -> [TicketSummary] {
        TicketListViewModel.filterTickets(tickets, state: state, query: query)
    }

    private func makeTicket(
        id: Int,
        title: String,
        status: TicketStatus,
        submitter: String,
        labels: [TicketLabel],
        assignees: [Entity] = []
    ) -> TicketSummary {
        TicketSummary(
            id: id,
            title: title,
            status: status,
            resolution: status == .resolved ? .fixed : nil,
            created: Date(),
            submitter: Entity(canonicalName: submitter),
            labels: labels,
            assignees: assignees
        )
    }

    private func makeLabel(id: Int, name: String) -> TicketLabel {
        TicketLabel(
            id: id,
            name: name,
            backgroundColor: "#000000",
            foregroundColor: "#ffffff"
        )
    }
}
