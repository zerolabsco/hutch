import Foundation

// MARK: - User Profile (full)

/// Extended user profile from meta.sr.ht with all fields from the `me` query.
struct UserProfile: Codable, Sendable {
    let username: String
    let canonicalName: String
    let email: String
    let url: String?
    let location: String?
    let bio: String?
    let avatar: String?
    let userType: String?
    let sshKeys: SSHKeyPage
    let pgpKeys: PGPKeyPage
    let paymentStatus: String?
    let subscription: Subscription?
}

// MARK: - SSH Key

struct SSHKey: Codable, Sendable, Identifiable {
    let id: Int
    let fingerprint: String
    let comment: String?
    let created: Date
    let lastUsed: Date?
}

struct SSHKeyPage: Codable, Sendable {
    let results: [SSHKey]
    let cursor: String?
}

// MARK: - PGP Key

struct PGPKey: Codable, Sendable, Identifiable {
    let id: Int
    let fingerprint: String
    let created: Date
}

struct PGPKeyPage: Codable, Sendable {
    let results: [PGPKey]
    let cursor: String?
}

// MARK: - Subscription

struct Subscription: Codable, Sendable {
    let status: String?
    let autorenew: Bool?
    let interval: String?
}

// MARK: - Personal Access Token

struct PersonalAccessToken: Codable, Sendable, Identifiable {
    let id: Int
    let issued: Date
    let expires: Date?
    let comment: String?
    let grants: String?
}
