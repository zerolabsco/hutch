import Foundation

/// Review state of a patchset on lists.sr.ht.
enum PatchsetStatus: String, Codable, Sendable, CaseIterable {
    case unknown = "UNKNOWN"
    case proposed = "PROPOSED"
    case needsRevision = "NEEDS_REVISION"
    case superseded = "SUPERSEDED"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case applied = "APPLIED"

    var displayName: String {
        switch self {
        case .unknown: "Unknown"
        case .proposed: "Proposed"
        case .needsRevision: "Needs Revision"
        case .superseded: "Superseded"
        case .approved: "Approved"
        case .rejected: "Rejected"
        case .applied: "Applied"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .proposed: "paperplane"
        case .needsRevision: "exclamationmark.arrow.circlepath"
        case .superseded: "arrow.triangle.branch"
        case .approved: "checkmark.seal"
        case .rejected: "xmark.circle"
        case .applied: "checkmark.circle.fill"
        }
    }

    /// Whether the patchset is still awaiting a decision.
    var isOpen: Bool {
        switch self {
        case .unknown, .proposed, .needsRevision: true
        case .superseded, .approved, .rejected, .applied: false
        }
    }

    /// Statuses a reviewer can set directly.
    ///
    /// `unknown` is a sentinel for patchsets sr.ht could not classify, and
    /// `superseded` is set by the server when a later version arrives, so neither
    /// is offered as a choice.
    static var assignable: [PatchsetStatus] {
        [.proposed, .needsRevision, .approved, .rejected, .applied]
    }
}

/// A patchset as it appears in a mailing list listing, derived from the thread's
/// root email rather than a dedicated patchsets query — `MailingList` exposes no
/// such field.
struct PatchsetSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let subject: String
    let version: Int
    let prefix: String?
    let status: PatchsetStatus

    /// The `[PATCH v2]`-style prefix sr.ht parsed from the subject, if any.
    var versionLabel: String? {
        guard version > 1 else { return nil }
        return "v\(version)"
    }
}

/// One email within a patchset: either the cover letter or a single patch.
struct PatchsetEmail: Identifiable, Hashable, Sendable {
    let id: Int
    let subject: String
    let date: Date?
    let sender: Entity
    /// Split into commit message and diff blocks for rendering.
    let contentBlocks: [InboxMessageContentBlock]
    /// Position within the series, from the `[PATCH 2/5]` prefix.
    let index: Int?
    let count: Int?

    var seriesLabel: String? {
        guard let index, let count, count > 1 else { return nil }
        return "\(index)/\(count)"
    }
}

/// A build or check reported against a patchset.
struct PatchsetToolResult: Identifiable, Hashable, Sendable {
    let id: Int
    let icon: PatchsetToolIcon
    let details: String
}

enum PatchsetToolIcon: String, Codable, Sendable {
    case pending = "PENDING"
    case waiting = "WAITING"
    case success = "SUCCESS"
    case failed = "FAILED"
    case cancelled = "CANCELLED"

    var systemImage: String {
        switch self {
        case .pending, .waiting: "clock"
        case .success: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "minus.circle"
        }
    }
}

/// A patchset with its cover letter, patches, and review context.
struct PatchsetDetail: Sendable {
    let id: Int
    let created: Date
    let updated: Date
    let subject: String
    let version: Int
    let prefix: String?
    let status: PatchsetStatus
    let submitter: Entity
    let coverLetter: PatchsetEmail?
    let patches: [PatchsetEmail]
    /// Set when a newer version of this series exists.
    let supersededBy: Int?
    /// Set when this series revises an earlier one.
    let supersedes: Int?
    let tools: [PatchsetToolResult]
    let mbox: URL?
}
