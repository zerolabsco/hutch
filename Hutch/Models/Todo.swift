import Foundation

// MARK: - Enums

/// Status of a ticket.
enum TicketStatus: String, Codable, Sendable, CaseIterable {
    case reported = "REPORTED"
    case confirmed = "CONFIRMED"
    case inProgress = "IN_PROGRESS"
    case pending = "PENDING"
    case resolved = "RESOLVED"

    /// Whether this status represents an open (unresolved) ticket.
    var isOpen: Bool {
        switch self {
        case .reported, .confirmed, .inProgress, .pending: true
        case .resolved: false
        }
    }

    var displayName: String {
        switch self {
        case .reported:   "Reported"
        case .confirmed:  "Confirmed"
        case .inProgress: "In Progress"
        case .pending:    "Pending"
        case .resolved:   "Resolved"
        }
    }
}

/// Resolution of a ticket.
enum TicketResolution: String, Codable, Sendable {
    case unresolved = "UNRESOLVED"
    case fixed = "FIXED"
    case implemented = "IMPLEMENTED"
    case wontFix = "WONT_FIX"
    case byDesign = "BY_DESIGN"
    case invalid = "INVALID"
    case duplicate = "DUPLICATE"
    case notOurBug = "NOT_OUR_BUG"
    case closed = "CLOSED"
    case notApplicable = "NOT_APPLICABLE"

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = TicketResolution(rawValue: value) ?? .unresolved
    }

    var displayName: String {
        switch self {
        case .unresolved:     "Unresolved"
        case .fixed:          "Fixed"
        case .implemented:    "Implemented"
        case .wontFix:        "Won't Fix"
        case .byDesign:       "By Design"
        case .invalid:        "Invalid"
        case .duplicate:      "Duplicate"
        case .notOurBug:      "Not Our Bug"
        case .closed:         "Closed"
        case .notApplicable:  "Not Applicable"
        }
    }
}

/// Authenticity of a ticket or comment.
enum Authenticity: String, Codable, Sendable {
    case authentic = "AUTHENTIC"
    case tampered = "TAMPERED"
    case unauthenticated = "UNAUTHENTICATED"
}

// MARK: - Label

/// A label that can be applied to tickets.
/// Named `TicketLabel` to avoid collision with `SwiftUI.Label`.
struct TicketLabel: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let backgroundColor: String
    let foregroundColor: String
}

// MARK: - Tracker

/// A bug tracker from todo.sr.ht.
struct Tracker: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let created: Date
    let updated: Date
    let name: String
    let description: String?
    let visibility: Visibility
    let owner: Entity

    static func == (lhs: Tracker, rhs: Tracker) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Tracker Summary (for list view)

/// Lightweight tracker model matching the fields returned by the trackers list query.
struct TrackerSummary: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    /// GraphQL resource identifier used by `tracker(id:)` queries.
    let rid: String
    let name: String
    let description: String?
    let visibility: Visibility
    let updated: Date
    let owner: Entity
}

// MARK: - Ticket Summary (for list view)

/// Lightweight ticket model for the list query.
struct TicketSummary: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let title: String
    let status: TicketStatus
    let resolution: TicketResolution?
    let created: Date
    let submitter: Entity
    let labels: [TicketLabel]
    let assignees: [Entity]

    static func == (lhs: TicketSummary, rhs: TicketSummary) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Ticket Detail

/// Full ticket model for the detail view.
struct TicketDetail: Codable, Sendable {
    let id: Int
    let created: Date
    let updated: Date
    let title: String
    let description: String?
    let status: TicketStatus
    let resolution: TicketResolution?
    let authenticity: Authenticity
    let submitter: Entity
    let assignees: [Entity]
    let labels: [TicketLabel]
}

// MARK: - Event

/// A timeline event on a ticket. Each event contains one or more changes.
struct TicketEvent: Codable, Sendable, Identifiable {
    let id: Int
    let created: Date
    var changes: [EventChange]
}

/// A single change within an event, decoded from the polymorphic EventDetail
/// interface using inline fragments.
struct EventChange: Codable, Sendable, Identifiable {
    let id: UUID

    let eventType: String

    // Comment fields
    let author: Entity?
    var text: String?
    let authenticity: Authenticity?

    // StatusChange fields
    let oldStatus: TicketStatus?
    let newStatus: TicketStatus?

    // LabelUpdate fields
    let labeler: Entity?
    let label: EventLabel?

    // Assignment fields
    let assigner: Entity?
    let assignee: Entity?

    // Mention fields
    // TicketMention: mentioned is a Ticket with { id }
    // UserMention: mentioned is an Entity with { canonicalName }
    let mentioned: MentionTarget?

    // Created fields (author is shared with Comment)

    private enum CodingKeys: String, CodingKey {
        case eventType
        case author, text, authenticity
        case oldStatus, newStatus
        case labeler, label
        case assigner, assignee
        case mentioned
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.eventType = try container.decode(String.self, forKey: .eventType)
        self.author = try container.decodeIfPresent(Entity.self, forKey: .author)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        self.authenticity = try container.decodeIfPresent(Authenticity.self, forKey: .authenticity)
        self.oldStatus = try container.decodeIfPresent(TicketStatus.self, forKey: .oldStatus)
        self.newStatus = try container.decodeIfPresent(TicketStatus.self, forKey: .newStatus)
        self.labeler = try container.decodeIfPresent(Entity.self, forKey: .labeler)
        self.label = try container.decodeIfPresent(EventLabel.self, forKey: .label)
        self.assigner = try container.decodeIfPresent(Entity.self, forKey: .assigner)
        self.assignee = try container.decodeIfPresent(Entity.self, forKey: .assignee)
        self.mentioned = try container.decodeIfPresent(MentionTarget.self, forKey: .mentioned)
    }
}

/// Decoded from the `mentioned` field which may be a Ticket (with `id`) or
/// an Entity (with `canonicalName`) depending on the event type.
struct MentionTarget: Codable, Sendable {
    let id: Int?
    let canonicalName: String?
}

/// Label info as returned within a LabelUpdate event change.
struct EventLabel: Codable, Sendable {
    let name: String
}
