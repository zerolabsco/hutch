import Foundation

/// Lightweight repository model matching the fields returned by the
/// repositories list query. Avoids optionalizing all fields on the full
/// `Repository` model.
struct RepositorySummary: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    /// GraphQL resource identifier used by `repository(rid:)` queries.
    let rid: String
    let service: SRHTService
    let name: String
    let description: String?
    let visibility: Visibility
    let updated: Date
    let owner: Entity
    let head: Reference?

    enum CodingKeys: String, CodingKey {
        case id, rid, service, name, description, visibility, updated, owner
        case head = "HEAD"
    }

    init(
        id: Int,
        rid: String,
        service: SRHTService,
        name: String,
        description: String?,
        visibility: Visibility,
        updated: Date,
        owner: Entity,
        head: Reference?
    ) {
        self.id = id
        self.rid = rid
        self.service = service
        self.name = name
        self.description = description
        self.visibility = visibility
        self.updated = updated
        self.owner = owner
        self.head = head
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.rid = try container.decode(String.self, forKey: .rid)
        self.service = try container.decodeIfPresent(SRHTService.self, forKey: .service) ?? .git
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.visibility = try container.decode(Visibility.self, forKey: .visibility)
        self.updated = try container.decode(Date.self, forKey: .updated)
        self.owner = try container.decode(Entity.self, forKey: .owner)
        self.head = try container.decodeIfPresent(Reference.self, forKey: .head)
    }
}

extension RepositorySummary {
    var defaultBranchName: String? {
        head?.name.replacingOccurrences(of: "refs/heads/", with: "")
    }

    func updating(
        name: String? = nil,
        description: String? = nil,
        visibility: Visibility? = nil,
        updated: Date? = nil,
        head: Reference? = nil
    ) -> RepositorySummary {
        RepositorySummary(
            id: id,
            rid: rid,
            service: service,
            name: name ?? self.name,
            description: description ?? self.description,
            visibility: visibility ?? self.visibility,
            updated: updated ?? self.updated,
            owner: owner,
            head: head ?? self.head
        )
    }

    static func displayBranchName(for reference: Reference) -> String {
        displayBranchName(for: reference.name)
    }

    static func displayBranchName(for referenceName: String) -> String {
        referenceName.replacingOccurrences(of: "refs/heads/", with: "")
    }
}
