import Foundation

struct PasteFile: Codable, Sendable, Hashable, Identifiable {
    let filename: String?
    let hash: String
    let contents: URL?

    var id: String { hash }
}

struct Paste: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let created: Date
    let visibility: Visibility
    let files: [PasteFile]
    let user: Entity
}

struct PasteUploadDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var filename: String
    var contents: String

    init(id: UUID = UUID(), filename: String = "", contents: String = "") {
        self.id = id
        self.filename = filename
        self.contents = contents
    }
}
