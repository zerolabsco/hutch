import Foundation

enum TicketBulkActionKind: String, Sendable {
    case close
    case assign

    var displayName: String {
        switch self {
        case .close:
            "Close"
        case .assign:
            "Assign"
        }
    }

    var pastTenseDisplayName: String {
        switch self {
        case .close:
            "Closed"
        case .assign:
            "Assigned"
        }
    }
}

struct TicketBulkActionResult: Identifiable, Sendable {
    let id = UUID()
    let action: TicketBulkActionKind
    let totalCount: Int
    let updatedCount: Int
    let unchangedCount: Int
    let failures: [TicketBulkActionFailure]

    var failedCount: Int {
        failures.count
    }

    var title: String {
        if updatedCount == 0, failedCount > 0 {
            return "\(action.displayName) Failed"
        }
        if failedCount > 0 {
            return "\(action.displayName) Partially Applied"
        }
        return "\(action.displayName) Complete"
    }

    var message: String {
        var components: [String] = []

        if updatedCount > 0 {
            components.append("\(action.pastTenseDisplayName) \(updatedCount) \(ticketWord(for: updatedCount)).")
        }

        if unchangedCount > 0 {
            let unchangedDescription: String
            switch action {
            case .close:
                unchangedDescription = "\(unchangedCount) already closed."
            case .assign:
                unchangedDescription = "\(unchangedCount) already assigned."
            }
            components.append(unchangedDescription)
        }

        if failedCount > 0 {
            let ids = failures
                .map { "#\($0.ticketID)" }
                .joined(separator: ", ")
            components.append("Failed: \(ids).")
        }

        if components.isEmpty {
            components.append("No tickets were selected.")
        }

        return components.joined(separator: " ")
    }

    private func ticketWord(for count: Int) -> String {
        count == 1 ? "ticket" : "tickets"
    }
}

struct TicketBulkActionFailure: Sendable {
    let ticketID: Int
    let message: String
}
