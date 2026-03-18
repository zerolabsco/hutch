import Foundation

/// Lightweight commit model for list views. Matches the subset of fields
/// returned by the repository log query.
struct CommitSummary: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let shortId: String
    let author: CommitAuthor
    let message: String

    /// First line of the commit message.
    var title: String {
        message.prefix(while: { $0 != "\n" }).trimmingCharacters(in: .whitespaces)
    }
}

/// A compact author representation used in commit list responses.
struct CommitAuthor: Codable, Sendable, Hashable {
    let name: String
    let email: String?
    let time: Date
}
