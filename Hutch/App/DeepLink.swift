import Foundation
import os

private let deepLinkParserLogger = Logger(subsystem: "net.cleberg.Hutch", category: "DeepLink")

enum HutchWorkQueueScope: String, CaseIterable, Sendable {
    case all
    case unread
    case assigned
}

enum HutchRoute: Equatable, Sendable {
    case home
    case workQueue(scope: HutchWorkQueueScope = .all)
    case recentActivity
    case repository(service: SRHTService, owner: String, repo: String)
    case tracker(owner: String, tracker: String)
    case ticket(owner: String, tracker: String, ticketId: Int)
    case build(jobId: Int)
    case mailingList(owner: String, list: String)
    case userProfile(owner: String)
    case builds
    case failedBuilds
    case repositories
    case trackers
    case systemStatus
    case lookup
    case search(query: String)
    case projectDashboard(id: String, title: String?)

    init?(url: URL) {
        guard url.scheme == "hutch" else { return nil }

        let components = url.deepLinkPathComponents
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let queryValue: (String) -> String? = { name in
            queryItems.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        switch components.first {
        case "home", nil:
            self = .home

        case "recent", "recent-activity", "activity":
            self = .recentActivity

        case "work", "inbox":
            let scope = queryValue("scope").flatMap(HutchWorkQueueScope.init(rawValue:)) ?? .all
            self = .workQueue(scope: scope)

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

        case "todo" where components.count >= 3:
            self = .tracker(owner: components[1], tracker: components[2])

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
            self = queryValue("filter") == "failed" ? .failedBuilds : .builds

        case "lists" where components.count >= 3:
            self = .mailingList(owner: components[1], list: components[2])

        case "projects" where components.count >= 2:
            self = .projectDashboard(id: components[1], title: queryValue("title"))

        case "repositories":
            self = .repositories

        case "trackers":
            self = .trackers

        case "status":
            self = .systemStatus

        case "lookup" where components.count >= 2:
            self = .userProfile(owner: components[1])

        case "lookup":
            if let query = queryValue("q"), !query.isEmpty {
                self = .search(query: query)
            } else {
                self = .lookup
            }

        default:
            return nil
        }
    }

    var url: URL {
        switch self {
        case .home:
            return Self.makeURL(host: "home")
        case .workQueue(let scope):
            return Self.makeURL(
                host: "work",
                queryItems: scope == .all ? [] : [URLQueryItem(name: "scope", value: scope.rawValue)]
            )
        case .recentActivity:
            return Self.makeURL(host: "recent-activity")
        case .repository(let service, let owner, let repo):
            return Self.makeURL(host: service.rawValue, path: [owner, repo])
        case .tracker(let owner, let tracker):
            return Self.makeURL(host: "todo", path: [owner, tracker])
        case .ticket(let owner, let tracker, let ticketId):
            return Self.makeURL(host: "todo", path: [owner, tracker, String(ticketId)])
        case .build(let jobId):
            return Self.makeURL(host: "builds", path: [String(jobId)])
        case .mailingList(let owner, let list):
            return Self.makeURL(host: "lists", path: [owner, list])
        case .userProfile(let owner):
            return Self.makeURL(host: "lookup", path: [owner])
        case .builds:
            return Self.makeURL(host: "builds")
        case .failedBuilds:
            return Self.makeURL(host: "builds", queryItems: [URLQueryItem(name: "filter", value: "failed")])
        case .repositories:
            return Self.makeURL(host: "repositories")
        case .trackers:
            return Self.makeURL(host: "trackers")
        case .systemStatus:
            return Self.makeURL(host: "status")
        case .lookup:
            return Self.makeURL(host: "lookup")
        case .search(let query):
            return Self.makeURL(host: "lookup", queryItems: [URLQueryItem(name: "q", value: query)])
        case .projectDashboard(let id, let title):
            return Self.makeURL(
                host: "projects",
                path: [id],
                queryItems: title.map { [URLQueryItem(name: "title", value: $0)] } ?? []
            )
        }
    }

    private static func makeURL(
        host: String,
        path: [String] = [],
        queryItems: [URLQueryItem] = []
    ) -> URL {
        var components = URLComponents()
        components.scheme = "hutch"
        components.host = host
        if !path.isEmpty {
            components.path = "/" + path.joined(separator: "/")
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url!
    }
}

/// Represents a parsed `hutch://` deep link.
enum DeepLink: Equatable {
    case home
    case work
    case workQueue(scope: HutchWorkQueueScope)
    case recentActivity
    /// hutch://git/<owner>/<repo> or hutch://hg/<owner>/<repo>
    case repository(service: SRHTService, owner: String, repo: String)
    /// hutch://todo/<owner>/<tracker>
    case tracker(owner: String, tracker: String)
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
    /// hutch://lookup?q=<query>
    case search(query: String)
    /// hutch://builds?filter=failed
    case failedBuilds
    /// hutch://projects/<rid>
    case projectDashboard(id: String, title: String?)

    /// Attempt to parse a URL into a DeepLink.
    /// Expected format: hutch://<path>
    init?(url: URL) {
        let components = url.deepLinkPathComponents
        deepLinkParserLogger.info("DeepLink parser components for \(url.absoluteString, privacy: .public): \(components.joined(separator: ","), privacy: .public)")
        guard let route = HutchRoute(url: url) else { return nil }
        self = Self(route: route)
    }

    init(route: HutchRoute) {
        switch route {
        case .home:
            self = .home
        case .workQueue(let scope):
            self = scope == .all ? .work : .workQueue(scope: scope)
        case .recentActivity:
            self = .recentActivity
        case .repository(let service, let owner, let repo):
            self = .repository(service: service, owner: owner, repo: repo)
        case .tracker(let owner, let tracker):
            self = .tracker(owner: owner, tracker: tracker)
        case .ticket(let owner, let tracker, let ticketId):
            self = .ticket(owner: owner, tracker: tracker, ticketId: ticketId)
        case .build(let jobId):
            self = .build(jobId: jobId)
        case .mailingList(let owner, let list):
            self = .mailingList(owner: owner, list: list)
        case .userProfile(let owner):
            self = .userProfile(owner: owner)
        case .builds:
            self = .buildsTab
        case .failedBuilds:
            self = .failedBuilds
        case .repositories:
            self = .repositoriesTab
        case .trackers:
            self = .trackersTab
        case .systemStatus:
            self = .systemStatus
        case .lookup:
            self = .lookup
        case .search(let query):
            self = .search(query: query)
        case .projectDashboard(let id, let title):
            self = .projectDashboard(id: id, title: title)
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
