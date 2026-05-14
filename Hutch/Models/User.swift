import Foundation

/// A Sourcehut user from meta.sr.ht.
struct User: Decodable, Sendable, Hashable {
    let id: Int
    let created: String?
    let updated: String?
    let username: String
    let canonicalName: String
    let email: String
    let url: String?
    let location: String?
    let bio: String?
    let avatar: String?
    let pronouns: String?
    let userType: String?
    let receivesPaidServices: Bool?
    let suspensionNotice: String?
}
