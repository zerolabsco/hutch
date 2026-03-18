import Foundation

/// Each Sourcehut service exposes its own GraphQL endpoint.
enum SRHTService: String, Codable, Sendable, CaseIterable {
    case meta
    case git
    case hg
    case builds
    case lists
    case todo
    case paste
    case pages
    case man

    /// The GraphQL endpoint URL for this service.
    var url: URL {
        // Force-unwrap is safe here — these are compile-time constant strings.
        URL(string: "https://\(rawValue).sr.ht/query")!
    }

    var displayName: String {
        switch self {
        case .meta:   "Meta"
        case .git:    "Git"
        case .hg:     "Mercurial"
        case .builds: "Builds"
        case .lists:  "Lists"
        case .todo:   "Todo"
        case .paste:  "Paste"
        case .pages:  "Pages"
        case .man:    "Man"
        }
    }
}
