import Foundation
import os

private let deepLinkParserLogger = Logger(subsystem: "net.cleberg.Hutch", category: "DeepLink")

/// Represents a parsed `hutch://` deep link.
enum DeepLink: Equatable {
    case home
    case work
    /// hutch://git/<owner>/<repo> or hutch://hg/<owner>/<repo>
    case repository(service: SRHTService, owner: String, repo: String)
    /// hutch://todo/<owner>/<tracker>/<ticketId>
    case ticket(owner: String, tracker: String, ticketId: Int)
    /// hutch://builds/<jobId> or hutch://builds/<owner>/job/<jobId>
    case build(jobId: Int)
    /// hutch://lists/<owner>/<list>
    case mailingList(owner: String, list: String)
    /// hutch://lookup/<owner>
    case userProfile(owner: String)
    /// hutch://builds (tab-level)
    case buildsTab
    /// hutch://repositories (tab-level)
    case repositoriesTab
    /// hutch://trackers (tab-level)
    case trackersTab
    /// hutch://status
    case systemStatus
    /// hutch://lookup
    case lookup

    /// Attempt to parse a URL into a DeepLink.
    /// Expected format: hutch://<path>
    init?(url: URL) {
        guard url.scheme == "hutch" else { return nil }

        let components = url.deepLinkPathComponents
        deepLinkParserLogger.info("DeepLink parser components for \(url.absoluteString, privacy: .public): \(components.joined(separator: ","), privacy: .public)")

        switch components.first {
        case "home", nil:
            self = .home

        case "work", "inbox":
            self = .work

        case let .some(serviceName) where ["git", "hg", "todo", "builds", "lists"].contains(serviceName)
            && components.count == 2
            && components[1].hasPrefix("~"):
            deepLinkParserLogger.info("Treating owner-root service URL as user profile: service=\(serviceName, privacy: .public), owner=\(components[1], privacy: .public)")
            self = .userProfile(owner: components[1])

        case let .some(serviceName) where ["git", "hg"].contains(serviceName) && components.count >= 3:
            guard let service = SRHTService(rawValue: serviceName)
            else { return nil }
            let owner = components[1]
            let repo = components[2]
            self = .repository(service: service, owner: owner, repo: repo)

        case "todo" where components.count >= 4:
            let owner = components[1]
            let tracker = components[2]
            guard let ticketId = Int(components[3]) else { return nil }
            self = .ticket(owner: owner, tracker: tracker, ticketId: ticketId)

        case "builds" where components.count >= 2:
            let rawJobId: String
            if components.count >= 4, components[2] == "job" {
                rawJobId = components[3]
            } else {
                rawJobId = components[1]
            }
            guard let jobId = Int(rawJobId) else { return nil }
            self = .build(jobId: jobId)

        case "builds":
            self = .buildsTab

        case "lists" where components.count >= 3:
            self = .mailingList(owner: components[1], list: components[2])

        case "repositories":
            self = .repositoriesTab

        case "trackers":
            self = .trackersTab

        case "status":
            self = .systemStatus

        case "lookup" where components.count >= 2:
            self = .userProfile(owner: components[1])

        case "lookup":
            self = .lookup

        default:
            return nil
        }
    }
}

private extension URL {
    var deepLinkPathComponents: [String] {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return []
        }

        let pathComponents = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        if let host = components.host, !host.isEmpty {
            return [host] + pathComponents
        }
        return pathComponents
    }
}
