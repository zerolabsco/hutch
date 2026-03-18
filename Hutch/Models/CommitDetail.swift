import Foundation

/// Full commit detail returned by the revparse_single query.
struct CommitDetail: Codable, Sendable, Identifiable {
    let id: String
    let shortId: String
    let author: CommitAuthor
    let committer: CommitAuthor
    let message: String
    let diff: String?
    let trailers: [CommitTrailer]
    let parents: [ParentCommit]
    let tree: CommitTree?

    /// First line of the commit message.
    var title: String {
        message.prefix(while: { $0 != "\n" }).trimmingCharacters(in: .whitespaces)
    }

    /// The commit message body (everything after the first line), if any.
    var body: String? {
        guard let newlineIndex = message.firstIndex(of: "\n") else { return nil }
        let body = message[message.index(after: newlineIndex)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }
}

struct CommitTrailer: Codable, Sendable, Identifiable {
    var id: String { "\(name):\(value)" }
    let name: String
    let value: String
}

struct ParentCommit: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let shortId: String
    let author: ParentAuthor
}

struct ParentAuthor: Codable, Sendable, Hashable {
    let name: String
}

struct CommitTree: Codable, Sendable {
    let entries: CommitTreeEntries
}

struct CommitTreeEntries: Codable, Sendable {
    let results: [CommitTreeEntry]
    let cursor: String?
}

struct CommitTreeEntry: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let mode: Int
    let object: CommitTreeObject?
}

struct CommitTreeObject: Codable, Sendable {
    let type: String?
    let id: String?
    let shortId: String?
}
