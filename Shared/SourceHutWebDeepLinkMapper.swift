import Foundation

enum SourceHutWebDeepLinkMapper {
    static let supportedHosts: Set<String> = [
        "git.sr.ht",
        "hg.sr.ht",
        "todo.sr.ht",
        "builds.sr.ht",
        "lists.sr.ht",
        "meta.sr.ht",
        "sr.ht",
    ]

    static func deepLink(for webURL: URL) -> URL? {
        guard let components = URLComponents(url: webURL, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              let host = components.host?.lowercased(),
              supportedHosts.contains(host)
        else {
            return nil
        }

        let path = normalizedPercentEncodedPath(from: components.percentEncodedPath)
        let deepLinkPath = normalizedDeepLinkPath(for: host, path: path)
        let service = deepLinkService(for: host, path: deepLinkPath)
        var deepLinkComponents = URLComponents()
        deepLinkComponents.scheme = "hutch"
        deepLinkComponents.host = service

        if !deepLinkPath.isEmpty {
            deepLinkComponents.percentEncodedPath = "/" + deepLinkPath
        }
        deepLinkComponents.percentEncodedQuery = components.percentEncodedQuery
        deepLinkComponents.percentEncodedFragment = components.percentEncodedFragment
        return deepLinkComponents.url
    }

    private static func deepLinkService(for host: String, path: String) -> String {
        if isOwnerRootPath(path) {
            return "lookup"
        }

        switch host {
        case "git.sr.ht":
            return "git"
        case "hg.sr.ht":
            return "hg"
        case "todo.sr.ht":
            return "todo"
        case "builds.sr.ht":
            return "builds"
        case "lists.sr.ht":
            return "lists"
        default:
            return "lookup"
        }
    }

    private static func isOwnerRootPath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return components.count == 1 && components[0].hasPrefix("~")
    }

    private static func normalizedDeepLinkPath(for host: String, path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        if host == "sr.ht",
           components.count == 2,
           components[0] == "projects",
           components[1].hasPrefix("~") {
            return String(components[1])
        }
        return path
    }

    private static func normalizedPercentEncodedPath(from path: String) -> String {
        path
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }
}
