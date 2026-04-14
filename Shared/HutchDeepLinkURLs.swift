import Foundation

/// Canonical `hutch://` URLs for widgets, tests, and in-app links.
enum HutchDeepLinkURL {
    static let home = URL(string: "hutch://home")!
    static let emptyHost = URL(string: "hutch://")!
    static let repositoryGit = URL(string: "hutch://git/~user/repo")!
    static let ticket = URL(string: "hutch://todo/~owner/tracker/42")!
    static let buildJob = URL(string: "hutch://builds/12345")!
    static let trackers = URL(string: "hutch://trackers")!
    static let builds = URL(string: "hutch://builds")!
    static let repositories = URL(string: "hutch://repositories")!
    static let status = URL(string: "hutch://status")!
    static let lookup = URL(string: "hutch://lookup")!
    static let unknown = URL(string: "hutch://unknown")!
    static let invalidTicketId = URL(string: "hutch://todo/~owner/tracker/abc")!
    static let invalidBuildId = URL(string: "hutch://builds/abc")!
}

/// Default Hutch Stats API base URL (mirrors `AppConfiguration` fallback).
enum HutchStatsAPI {
    static let defaultBaseURL = URL(string: "https://hutch-stats.zerolabs.sh")!
}
