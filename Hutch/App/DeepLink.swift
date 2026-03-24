import Foundation

/// Represents a parsed `hutch://` deep link.
enum DeepLink: Equatable {
    case home
    /// hutch://git/<owner>/<repo>
    case repository(owner: String, repo: String)
    /// hutch://todo/<owner>/<tracker>/<ticketId>
    case ticket(owner: String, tracker: String, ticketId: Int)
    /// hutch://builds/<jobId>
    case build(jobId: Int)

    /// Attempt to parse a URL into a DeepLink.
    /// Expected format: hutch://<path>
    init?(url: URL) {
        guard url.scheme == "hutch" else { return nil }

        // url.host gives the first path component for opaque URLs;
        // use standardized path components from the full string.
        let components = url.pathComponents(fromScheme: "hutch")

        switch components.first {
        case "home", nil:
            self = .home

        case "git" where components.count >= 3:
            let owner = components[1]
            let repo = components[2]
            self = .repository(owner: owner, repo: repo)

        case "todo" where components.count >= 4:
            let owner = components[1]
            let tracker = components[2]
            guard let ticketId = Int(components[3]) else { return nil }
            self = .ticket(owner: owner, tracker: tracker, ticketId: ticketId)

        case "builds" where components.count >= 2:
            guard let jobId = Int(components[1]) else { return nil }
            self = .build(jobId: jobId)

        default:
            return nil
        }
    }
}

private extension URL {
    /// Parse path components from a custom-scheme URL.
    /// For `hutch://git/~user/repo`, returns `["git", "~user", "repo"]`.
    func pathComponents(fromScheme scheme: String) -> [String] {
        // Remove scheme prefix and split by "/"
        var str = absoluteString
        if str.hasPrefix("\(scheme)://") {
            str = String(str.dropFirst("\(scheme)://".count))
        }
        return str.split(separator: "/").map(String.init)
    }
}
