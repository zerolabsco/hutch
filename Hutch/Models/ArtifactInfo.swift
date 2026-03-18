import Foundation

/// An artifact with its parent reference name, used in the artifacts tab.
struct ArtifactInfo: Codable, Sendable, Identifiable {
    let id: Int
    let filename: String
    let checksum: String
    let size: Int
    let url: URL
}

struct ArtifactPage: Codable, Sendable {
    let results: [ArtifactInfo]
    let cursor: String?
}

/// A reference (tag) that has associated artifacts.
struct ReferenceWithArtifacts: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let artifacts: [ArtifactInfo]
}
