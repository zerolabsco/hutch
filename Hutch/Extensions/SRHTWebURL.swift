import Foundation

enum SRHTWebURL {
    static let chat = URL(string: "https://chat.sr.ht")!
    static let status = URL(string: "https://status.sr.ht")!

    static func repository(_ repository: RepositorySummary) -> URL? {
        userScopedURL(
            host: "\(repository.service.rawValue).sr.ht",
            ownerCanonicalName: repository.owner.canonicalName,
            pathComponents: [repository.name]
        )
    }

    static func httpsCloneURL(_ repositorySummary: RepositorySummary) -> String? {
        repository(repositorySummary)?.absoluteString
    }

    static func sshCloneURL(_ repositorySummary: RepositorySummary) -> String {
        let host = "\(repositorySummary.service.rawValue).sr.ht"
        let user = repositorySummary.service == .hg ? "hg" : "git"
        return "\(user)@\(host):\(repositorySummary.owner.canonicalName)/\(repositorySummary.name)"
    }

    static func commit(repository: RepositorySummary, commitId: String) -> URL? {
        userScopedURL(
            host: "\(repository.service.rawValue).sr.ht",
            ownerCanonicalName: repository.owner.canonicalName,
            pathComponents: [repository.name, commitPathComponent(for: repository.service), commitId]
        )
    }

    static func file(repository: RepositorySummary, revspec: String, path: String) -> URL? {
        switch repository.service {
        case .git:
            return userScopedURL(
                host: "git.sr.ht",
                ownerCanonicalName: repository.owner.canonicalName,
                pathComponents: [repository.name, "tree", revspec, "item"] + pathComponents(from: path)
            )
        case .hg:
            var components = URLComponents()
            components.scheme = "https"
            components.host = "hg.sr.ht"

            let ownerUsername = username(from: repository.owner.canonicalName)
            let encodedRepository = repository.name.addingPercentEncoding(withAllowedCharacters: pathComponentCharacterSet) ?? repository.name
            let encodedPath = path.split(separator: "/").map {
                String($0).addingPercentEncoding(withAllowedCharacters: pathComponentCharacterSet) ?? String($0)
            }.joined(separator: "/")

            components.percentEncodedPath = "/~\(ownerUsername)/\(encodedRepository)/browse/\(encodedPath)"
            components.queryItems = [URLQueryItem(name: "rev", value: revspec)]
            return components.url
        default:
            return nil
        }
    }

    static func build(jobId: Int, ownerCanonicalName: String) -> URL? {
        userScopedURL(
            host: "builds.sr.ht",
            ownerCanonicalName: ownerCanonicalName,
            pathComponents: ["job", String(jobId)]
        )
    }

    static func tracker(ownerUsername: String, trackerName: String) -> URL? {
        userScopedURL(
            host: "todo.sr.ht",
            ownerUsername: ownerUsername,
            pathComponents: [trackerName]
        )
    }

    static func tracker(_ trackerSummary: TrackerSummary) -> URL? {
        tracker(ownerUsername: trackerSummary.owner.canonicalName.srhtUsername, trackerName: trackerSummary.name)
    }

    static func projectSource(_ source: Project.SourceRepo) -> URL? {
        userScopedURL(
            host: "\(source.repoType.service.rawValue).sr.ht",
            ownerUsername: source.ownerUsername,
            pathComponents: [source.name]
        )
    }

    static func mailingList(ownerUsername: String, listName: String) -> URL? {
        userScopedURL(
            host: "lists.sr.ht",
            ownerUsername: ownerUsername,
            pathComponents: [listName]
        )
    }

    static func ticket(ownerUsername: String, trackerName: String, ticketId: Int) -> URL? {
        userScopedURL(
            host: "todo.sr.ht",
            ownerUsername: ownerUsername,
            pathComponents: [trackerName, String(ticketId)]
        )
    }

    static func profile(canonicalName: String) -> URL? {
        userScopedURL(
            host: "sr.ht",
            ownerCanonicalName: canonicalName,
            pathComponents: []
        )
    }

    static func paste(ownerCanonicalName: String, pasteId: String) -> URL? {
        userScopedURL(
            host: "paste.sr.ht",
            ownerCanonicalName: ownerCanonicalName,
            pathComponents: [pasteId]
        )
    }

    private static func userScopedURL(
        host: String,
        ownerCanonicalName: String,
        pathComponents: [String]
    ) -> URL? {
        userScopedURL(
            host: host,
            ownerUsername: username(from: ownerCanonicalName),
            pathComponents: pathComponents
        )
    }

    private static func userScopedURL(
        host: String,
        ownerUsername: String,
        pathComponents: [String]
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host

        let encodedComponents = (["~\(ownerUsername)"] + pathComponents).map { pathComponent in
            pathComponent.addingPercentEncoding(withAllowedCharacters: pathComponentCharacterSet) ?? pathComponent
        }
        components.percentEncodedPath = "/" + encodedComponents.joined(separator: "/")
        return components.url
    }

    private static func username(from canonicalName: String) -> String {
        if canonicalName.hasPrefix("~") {
            return String(canonicalName.dropFirst())
        }
        return canonicalName
    }

    private static func commitPathComponent(for service: SRHTService) -> String {
        switch service {
        case .hg:
            return "rev"
        default:
            return "commit"
        }
    }

    private static let pathComponentCharacterSet: CharacterSet = {
        var characterSet = CharacterSet.urlPathAllowed
        characterSet.remove(charactersIn: "/")
        return characterSet
    }()

    private static func pathComponents(from path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }
}
