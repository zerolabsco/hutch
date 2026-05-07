import Foundation

enum APICacheKeys {
    static func repositories(service: SRHTService, owner: String? = nil, cursor: String? = nil, filter: String? = nil) -> String {
        make([
            service.rawValue,
            "repositories",
            owner.map { "owner:\(normalize($0))" },
            cursor.map { "cursor:\($0)" },
            filter.map { "filter:\(normalize($0))" }
        ])
    }

    static func repository(service: SRHTService, owner: String, name: String) -> String {
        make([service.rawValue, "repository", normalize(owner), normalize(name)])
    }

    static func repositoryRID(service: SRHTService, rid: String) -> String {
        make([service.rawValue, "repository", "rid:\(rid)"])
    }

    static func refs(service: SRHTService, rid: String, cursor: String? = nil) -> String {
        make([service.rawValue, "refs", "rid:\(rid)", cursor.map { "cursor:\($0)" }])
    }

    static func readme(service: SRHTService, rid: String, path: String? = nil, ref: String = "HEAD") -> String {
        make([service.rawValue, "readme", "rid:\(rid)", "ref:\(ref)", path.map { "path:\($0)" }])
    }

    static func treeRoot(service: SRHTService, rid: String, ref: String) -> String {
        make([service.rawValue, "tree", "rid:\(rid)", "ref:\(ref)", "root"])
    }

    static func treeEntries(service: SRHTService, rid: String, treeId: String, cursor: String? = nil) -> String {
        make([service.rawValue, "tree", "rid:\(rid)", "tree:\(treeId)", cursor.map { "cursor:\($0)" }])
    }

    static func blob(service: SRHTService, rid: String, blobId: String) -> String {
        make([service.rawValue, "blob", "rid:\(rid)", "blob:\(blobId)"])
    }

    static func path(service: SRHTService, rid: String, ref: String, path: String) -> String {
        make([service.rawValue, "path", "rid:\(rid)", "ref:\(ref)", "path:\(path)"])
    }

    static func ticketDetail(owner: String, trackerRid: String, ticketId: Int) -> String {
        make([SRHTService.todo.rawValue, "ticket", normalize(owner), "tracker:\(trackerRid)", "ticket:\(ticketId)"])
    }

    static func trackerLabels(trackerRid: String) -> String {
        make([SRHTService.todo.rawValue, "tracker-labels", "tracker:\(trackerRid)"])
    }

    static func builds(cursor: String? = nil, filter: String? = nil) -> String {
        make([SRHTService.builds.rawValue, "jobs", cursor.map { "cursor:\($0)" }, filter.map { "filter:\($0)" }])
    }

    static func buildDetail(jobId: Int) -> String {
        make([SRHTService.builds.rawValue, "job", "id:\(jobId)"])
    }

    static func buildLog(url: URL, jobId: Int? = nil, task: String? = nil) -> String {
        make([SRHTService.builds.rawValue, "log", jobId.map { "job:\($0)" }, task.map { "task:\($0)" }, url.absoluteString])
    }

    static func userRepositories(owner: String, cursor: String? = nil) -> String {
        make([SRHTService.git.rawValue, "user-repositories", normalize(owner), cursor.map { "cursor:\($0)" }])
    }

    static func userTrackers(owner: String, cursor: String? = nil) -> String {
        make([SRHTService.todo.rawValue, "user-trackers", normalize(owner), cursor.map { "cursor:\($0)" }])
    }

    static func pasteList(cursor: String? = nil) -> String {
        make([SRHTService.paste.rawValue, "pastes", cursor.map { "cursor:\($0)" }])
    }

    static func prefix(_ components: String...) -> String {
        make(components)
    }

    private static func make(_ parts: [String?]) -> String {
        parts.compactMap { $0?.replacingOccurrences(of: "|", with: "%7C") }
            .joined(separator: "|")
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum APICacheTTLs {
    // Active build data changes quickly; completed logs and content-addressed git data are effectively immutable.
    static let activeBuild: TimeInterval = 15
    static let completedBuildDetail: TimeInterval = 60 * 60
    static let completedBuildLog: TimeInterval = 30 * 24 * 60 * 60
    static let ticketDetail: TimeInterval = 5 * 60
    static let ticketList: TimeInterval = 2 * 60
    static let repositoryMetadata: TimeInterval = 30 * 60
    static let repositoryList: TimeInterval = 5 * 60
    static let immutableFileContent: TimeInterval = 14 * 24 * 60 * 60
    static let movingRefFileContent: TimeInterval = 10 * 60
    static let userProfile: TimeInterval = 30 * 60
    static let status: TimeInterval = 5 * 60
}
