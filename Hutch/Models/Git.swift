import Foundation

// MARK: - Enums

/// Repository visibility level.
enum Visibility: String, Codable, Sendable {
    case `public` = "PUBLIC"
    case unlisted = "UNLISTED"
    case `private` = "PRIVATE"
}

/// Repository access mode.
enum AccessMode: String, Codable, Sendable, CaseIterable {
    case ro = "RO"
    case rw = "RW"
}

// MARK: - Entity

/// The `Entity` GraphQL interface from git.sr.ht. Represents the owner of a
/// resource (typically a user).
struct Entity: Codable, Sendable, Hashable {
    let canonicalName: String
}

// MARK: - Repository

/// A git repository from git.sr.ht.
struct Repository: Codable, Sendable, Identifiable {
    let id: Int
    let created: Date
    let updated: Date
    let name: String
    let description: String?
    let visibility: Visibility
    let readme: String?
    let accessMode: AccessMode
    let owner: Entity

    enum CodingKeys: String, CodingKey {
        case id, created, updated, name, description, visibility, readme
        case accessMode = "access"
        case owner
    }
}

// MARK: - Signature

/// A Git commit/tag signature (author or committer).
struct Signature: Codable, Sendable {
    let name: String
    let email: String
    let time: Date
}

// MARK: - Trailer

/// A Git commit trailer (e.g. "Signed-off-by", "Co-authored-by").
struct Trailer: Codable, Sendable {
    let name: String
    let value: String
}

// MARK: - Commit

/// A Git commit from git.sr.ht.
struct Commit: Codable, Sendable, Identifiable {
    let id: String
    let shortId: String
    let author: Signature
    let committer: Signature
    let message: String
    let diff: String?
    let trailers: [Trailer]
}

// MARK: - Reference

/// A Git reference (branch or tag name).
struct Reference: Codable, Sendable, Hashable {
    let name: String
    let target: String?
}

/// A Git reference enriched with the date of its tip commit or tag, for display in the Refs tab.
struct ReferenceDetail: Sendable, Hashable {
    let name: String
    let target: String?
    let date: Date?
}

// MARK: - TreeEntry

/// An entry in a Git tree (file or directory).
struct TreeEntry: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let mode: Int?
    let object: GitObject?
}

/// A Git object returned by the git.sr.ht GraphQL API.
/// The API returns `type` as "TREE", "BLOB", "COMMIT", or "TAG".
/// Both TextBlob and BinaryBlob have type == "BLOB"; they are
/// distinguished by the presence of the "text" key (TextBlob) vs
/// the "content" key (BinaryBlob).
enum GitObject: Sendable {
    case tree(GitTree)
    case textBlob(GitTextBlob)
    case binaryBlob(GitBinaryBlob)
    case unknown
}

struct GitTree: Codable, Sendable {
    let id: String?
    let shortId: String?
    let entries: GitTreeEntryPage?
}

struct GitTextBlob: Codable, Sendable {
    let id: String?
    let shortId: String?
    let text: String?
    let size: Int?
}

struct GitBinaryBlob: Codable, Sendable {
    let id: String?
    let shortId: String?
    let size: Int?
    let content: String?
}

struct GitTreeEntryPage: Codable, Sendable {
    let results: [TreeEntry]
    let cursor: String?
}

// MARK: - GitObject Codable

extension GitObject: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, id, shortId, entries, text, size, content
        case typename = "__typename"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)
        let typename = try container.decodeIfPresent(String.self, forKey: .typename)

        switch type ?? typename {
        case "TREE", "Tree":
            let tree = GitTree(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                shortId: try container.decodeIfPresent(String.self, forKey: .shortId),
                entries: try container.decodeIfPresent(GitTreeEntryPage.self, forKey: .entries)
            )
            self = .tree(tree)

        case "BLOB", "TextBlob", "BinaryBlob":
            if typename == "TextBlob" || container.contains(.text) {
                let blob = GitTextBlob(
                    id: try container.decodeIfPresent(String.self, forKey: .id),
                    shortId: try container.decodeIfPresent(String.self, forKey: .shortId),
                    text: try container.decodeIfPresent(String.self, forKey: .text),
                    size: try container.decodeIfPresent(Int.self, forKey: .size)
                )
                self = .textBlob(blob)
            } else {
                let blob = GitBinaryBlob(
                    id: try container.decodeIfPresent(String.self, forKey: .id),
                    shortId: try container.decodeIfPresent(String.self, forKey: .shortId),
                    size: try container.decodeIfPresent(Int.self, forKey: .size),
                    content: try container.decodeIfPresent(String.self, forKey: .content)
                )
                self = .binaryBlob(blob)
            }

        default:
            self = .unknown
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tree(let tree):
            try container.encode("TREE", forKey: .type)
            try container.encodeIfPresent(tree.id, forKey: .id)
            try container.encodeIfPresent(tree.shortId, forKey: .shortId)
            try container.encodeIfPresent(tree.entries, forKey: .entries)
        case .textBlob(let blob):
            try container.encode("BLOB", forKey: .type)
            try container.encode("TextBlob", forKey: .typename)
            try container.encodeIfPresent(blob.id, forKey: .id)
            try container.encodeIfPresent(blob.shortId, forKey: .shortId)
            try container.encodeIfPresent(blob.text, forKey: .text)
            try container.encodeIfPresent(blob.size, forKey: .size)
        case .binaryBlob(let blob):
            try container.encode("BLOB", forKey: .type)
            try container.encode("BinaryBlob", forKey: .typename)
            try container.encodeIfPresent(blob.id, forKey: .id)
            try container.encodeIfPresent(blob.shortId, forKey: .shortId)
            try container.encodeIfPresent(blob.size, forKey: .size)
            try container.encodeIfPresent(blob.content, forKey: .content)
        case .unknown:
            break
        }
    }
}

/// Convenience helpers for checking object type.
extension GitObject {
    var isTree: Bool {
        if case .tree = self { return true }
        return false
    }

    var treeId: String? {
        switch self {
        case .tree(let t): t.id
        case .textBlob(let b): b.id
        case .binaryBlob(let b): b.id
        case .unknown: nil
        }
    }
}

// MARK: - Tag

/// An annotated Git tag from git.sr.ht.
struct Tag: Codable, Sendable, Identifiable {
    let id: String
    let shortId: String
    let name: String
    let message: String?
    let tagger: Signature?
}

// MARK: - Artifact

/// A release artifact attached to a Git tag.
struct Artifact: Codable, Sendable, Identifiable {
    let id: Int
    let created: Date
    let filename: String
    let checksum: String
    let size: Int
    let url: URL
}
