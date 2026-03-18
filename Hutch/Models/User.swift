import Foundation

/// A Sourcehut user from meta.sr.ht.
struct User: Decodable, Sendable {
    let id: Int
    let username: String
    let canonicalName: String
    let email: String
    let avatar: String?
}
