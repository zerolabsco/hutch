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
    let updated: Date
    let mailingLists: [MailingList]
    let sources: [SourceRepo]
    let trackers: [Tracker]
    let isFullyLoaded: Bool

    init(
        id: String,
        name: String,
        description: String?,
        website: String?,
        visibility: Visibility,
        tags: [String],
        updated: Date,
        mailingLists: [MailingList],
        sources: [SourceRepo],
        trackers: [Tracker],
        isFullyLoaded: Bool = true
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.website = website
        self.visibility = visibility
        self.tags = tags
        self.updated = updated
        self.mailingLists = mailingLists
        self.sources = sources
        self.trackers = trackers
        self.isFullyLoaded = isFullyLoaded
    }

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

    var displayName: String {
        Self.normalizedText(name) ?? "Untitled Project"
    }

    var displayDescription: String? {
        Self.normalizedText(description)
    }

    var displayTags: [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            guard let normalized = Self.normalizedText(tag) else { return nil }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return normalized
        }
    }

    var websiteURL: URL? {
        guard let website = Self.normalizedText(website) else { return nil }
        return URL(string: website)
    }

    var hasLinkedResources: Bool {
        !sources.isEmpty || !trackers.isEmpty || !mailingLists.isEmpty
    }

    var metadataLine: String {
        var parts = [visibility.displayName, updated.relativeDescription]
        if let summary = resourceSummary {
            parts.append(summary)
        }
        return parts.joined(separator: " • ")
    }

    private static func resourceCountText(count: Int, singular: String) -> String? {
        guard count > 0 else { return nil }
        let label = count == 1 ? singular : "\(singular)s"
        return "\(count) \(label)"
    }

    fileprivate static func normalizedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

extension Project.MailingList {
    var displayName: String {
        Project.normalizedText(name) ?? "Untitled Mailing List"
    }

    var displayDescription: String? {
        Project.normalizedText(description)
    }

    var ownerDisplayName: String {
        Project.normalizedText(owner.canonicalName) ?? "~unknown"
    }
}

extension Project.SourceRepo {
    var displayName: String {
        Project.normalizedText(name) ?? "Untitled Repository"
    }

    var displayDescription: String? {
        Project.normalizedText(description)
    }

    var ownerDisplayName: String {
        Project.normalizedText(owner.canonicalName) ?? "~unknown"
    }

    var webURL: URL? {
        SRHTWebURL.projectSource(self)
    }
}

extension Project.Tracker {
    var displayName: String {
        Project.normalizedText(name) ?? "Untitled Tracker"
    }

    var displayDescription: String? {
        Project.normalizedText(description)
    }

    var ownerDisplayName: String {
        Project.normalizedText(owner.canonicalName) ?? "~unknown"
    }

    var webURL: URL? {
        SRHTWebURL.tracker(ownerUsername: ownerUsername, trackerName: name)
    }
}

extension String {
    var srhtUsername: String {
        hasPrefix("~") ? String(dropFirst()) : self
    }
}

extension Visibility {
    var displayName: String {
        switch self {
        case .public:
            "Public"
        case .unlisted:
            "Unlisted"
        case .private:
            "Private"
        }
    }
}
