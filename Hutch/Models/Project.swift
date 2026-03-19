import Foundation

struct Project: Identifiable, Hashable, Sendable {
    struct MailingList: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let description: String?
        let visibility: Visibility
        let owner: Entity

        var ownerUsername: String {
            owner.canonicalName.srhtUsername
        }

        var inboxReference: InboxMailingListReference {
            InboxMailingListReference(
                id: 0,
                rid: id,
                name: name,
                owner: owner
            )
        }
    }

    struct SourceRepo: Identifiable, Hashable, Sendable {
        enum RepoType: String, Decodable, Sendable {
            case git = "GIT"
            case hg = "HG"

            var service: SRHTService {
                switch self {
                case .git: .git
                case .hg: .hg
                }
            }
        }

        let id: String
        let name: String
        let description: String?
        let visibility: Visibility
        let owner: Entity
        let repoType: RepoType

        var ownerUsername: String {
            owner.canonicalName.srhtUsername
        }
    }

    struct Tracker: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let description: String?
        let visibility: Visibility
        let owner: Entity

        var ownerUsername: String {
            owner.canonicalName.srhtUsername
        }
    }

    let id: String
    let name: String
    let description: String?
    let website: String?
    let visibility: Visibility
    let tags: [String]
    let mailingLists: [MailingList]
    let sources: [SourceRepo]
    let trackers: [Tracker]

    var resourceSummary: String? {
        let parts = [
            Self.resourceCountText(count: sources.count, singular: "repo"),
            Self.resourceCountText(count: trackers.count, singular: "tracker"),
            Self.resourceCountText(count: mailingLists.count, singular: "list")
        ].compactMap { $0 }

        if !parts.isEmpty {
            return parts.joined(separator: " • ")
        }

        if let website, !website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Website linked"
        }

        return nil
    }

    private static func resourceCountText(count: Int, singular: String) -> String? {
        guard count > 0 else { return nil }
        let label = count == 1 ? singular : "\(singular)s"
        return "\(count) \(label)"
    }
}

extension String {
    var srhtUsername: String {
        hasPrefix("~") ? String(dropFirst()) : self
    }
}
