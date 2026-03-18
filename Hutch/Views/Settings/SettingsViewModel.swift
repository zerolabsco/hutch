import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct MeProfileResponse: Decodable, Sendable {
    let me: UserProfile
}

private struct UpdateUserResponse: Decodable, Sendable {
    let updateUser: UpdatedUser
}

private struct UpdatedUser: Decodable, Sendable {
    let username: String
    let email: String
    let url: String?
    let location: String?
    let bio: String?
    let avatar: String?
}

private struct CreateSSHKeyResponse: Decodable, Sendable {
    let createSSHKey: SSHKey
}

private struct DeleteSSHKeyResponse: Decodable, Sendable {
    let deleteSSHKey: DeleteResult
}

private struct CreatePGPKeyResponse: Decodable, Sendable {
    let createPGPKey: PGPKey
}

private struct DeletePGPKeyResponse: Decodable, Sendable {
    let deletePGPKey: DeleteResult
}

private struct DeleteResult: Decodable, Sendable {
    let id: Int?
}

private struct PATListResponse: Decodable, Sendable {
    let personalAccessTokens: [PersonalAccessToken]
}

// MARK: - View Model

@Observable
@MainActor
final class SettingsViewModel {

    private(set) var profile: UserProfile?
    private(set) var sshKeys: [SSHKey] = []
    private(set) var pgpKeys: [PGPKey] = []
    private(set) var personalAccessTokens: [PersonalAccessToken] = []

    private(set) var isLoading = false
    private(set) var isLoadingPATs = false
    private(set) var isSavingProfile = false
    private(set) var isUploadingAvatar = false
    var error: String?

    var isEditingProfile = false

    // Add SSH key fields
    var newSSHKey = ""
    var isAddingSSHKey = false

    // Add PGP key fields
    var newPGPKey = ""
    var isAddingPGPKey = false

    private let client: SRHTClient

    init(client: SRHTClient) {
        self.client = client
    }

    // MARK: - Queries

    private static let profileQuery = """
    query me {
        me {
            username
            canonicalName
            email
            url
            location
            bio
            avatar
            userType
            sshKeys {
                results { id fingerprint comment created lastUsed }
                cursor
            }
            pgpKeys {
                results { id fingerprint created }
                cursor
            }
            paymentStatus
            subscription { status autorenew interval }
        }
    }
    """

    private static let updateUserMutation = """
    mutation updateUser($input: UserInput!) {
        updateUser(input: $input) {
            username email url location bio avatar
        }
    }
    """

    private static let createSSHKeyMutation = """
    mutation createSSHKey($key: String!) {
        createSSHKey(key: $key) {
            id fingerprint comment created lastUsed
        }
    }
    """

    private static let deleteSSHKeyMutation = """
    mutation deleteSSHKey($id: Int!) {
        deleteSSHKey(id: $id) { id }
    }
    """

    private static let createPGPKeyMutation = """
    mutation createPGPKey($key: String!) {
        createPGPKey(key: $key) {
            id fingerprint created
        }
    }
    """

    private static let deletePGPKeyMutation = """
    mutation deletePGPKey($id: Int!) {
        deletePGPKey(id: $id) { id }
    }
    """

    private static let personalAccessTokensQuery = """
    query personalAccessTokens {
        personalAccessTokens { id issued expires comment grants }
    }
    """

    // MARK: - Load Profile

    func loadProfile() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            let result = try await client.execute(
                service: .meta,
                query: Self.profileQuery,
                responseType: MeProfileResponse.self
            )
            profile = result.me
            sshKeys = result.me.sshKeys.results
            pgpKeys = result.me.pgpKeys.results
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Update Profile

    func saveProfile(email: String, url: String, location: String, bio: String) async {
        guard !isSavingProfile else { return }
        isSavingProfile = true
        error = nil

        do {
            let input: [String: any Sendable] = [
                "email": email,
                "url": url.isEmpty ? nil as String? as Any : url,
                "location": location.isEmpty ? nil as String? as Any : location,
                "bio": bio.isEmpty ? nil as String? as Any : bio
            ]
            let result = try await client.execute(
                service: .meta,
                query: Self.updateUserMutation,
                variables: ["input": input],
                responseType: UpdateUserResponse.self
            )
            let updated = result.updateUser
            if let p = profile {
                profile = UserProfile(
                    username: p.username,
                    canonicalName: p.canonicalName,
                    email: updated.email,
                    url: updated.url,
                    location: updated.location,
                    bio: updated.bio,
                    avatar: updated.avatar ?? p.avatar,
                    userType: p.userType,
                    sshKeys: p.sshKeys,
                    pgpKeys: p.pgpKeys,
                    paymentStatus: p.paymentStatus,
                    subscription: p.subscription
                )
            }
            isEditingProfile = false
        } catch {
            self.error = error.localizedDescription
        }

        isSavingProfile = false
    }

    // MARK: - Avatar

    func uploadAvatar(jpegData: Data) async {
        guard !isUploadingAvatar else { return }
        isUploadingAvatar = true
        error = nil

        do {
            // The input variable has avatar set to null; the actual file
            // is sent as a separate multipart part per graphql-multipart-request-spec.
            let input: [String: any Sendable] = ["avatar": nil as String? as Any]
            let result = try await client.executeMultipart(
                service: .meta,
                query: Self.updateUserMutation,
                variables: ["input": input],
                fileVariablePath: "input.avatar",
                fileData: jpegData,
                fileName: "avatar.jpg",
                mimeType: "image/jpeg",
                responseType: UpdateUserResponse.self
            )
            let updated = result.updateUser
            if let p = profile {
                profile = UserProfile(
                    username: p.username,
                    canonicalName: p.canonicalName,
                    email: updated.email,
                    url: updated.url,
                    location: updated.location,
                    bio: updated.bio,
                    avatar: updated.avatar ?? p.avatar,
                    userType: p.userType,
                    sshKeys: p.sshKeys,
                    pgpKeys: p.pgpKeys,
                    paymentStatus: p.paymentStatus,
                    subscription: p.subscription
                )
            }
        } catch {
            self.error = error.localizedDescription
        }

        isUploadingAvatar = false
    }

    func removeAvatar() async {
        guard !isUploadingAvatar else { return }
        isUploadingAvatar = true
        error = nil

        do {
            let input: [String: any Sendable] = ["avatar": nil as String? as Any]
            let result = try await client.execute(
                service: .meta,
                query: Self.updateUserMutation,
                variables: ["input": input],
                responseType: UpdateUserResponse.self
            )
            let updated = result.updateUser
            if let p = profile {
                profile = UserProfile(
                    username: p.username,
                    canonicalName: p.canonicalName,
                    email: updated.email,
                    url: updated.url,
                    location: updated.location,
                    bio: updated.bio,
                    avatar: nil,
                    userType: p.userType,
                    sshKeys: p.sshKeys,
                    pgpKeys: p.pgpKeys,
                    paymentStatus: p.paymentStatus,
                    subscription: p.subscription
                )
            }
        } catch {
            self.error = error.localizedDescription
        }

        isUploadingAvatar = false
    }

    // MARK: - SSH Keys

    func addSSHKey() async {
        let key = newSSHKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        error = nil

        do {
            let result = try await client.execute(
                service: .meta,
                query: Self.createSSHKeyMutation,
                variables: ["key": key],
                responseType: CreateSSHKeyResponse.self
            )
            sshKeys.append(result.createSSHKey)
            newSSHKey = ""
            isAddingSSHKey = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteSSHKey(_ key: SSHKey) async {
        error = nil

        do {
            _ = try await client.execute(
                service: .meta,
                query: Self.deleteSSHKeyMutation,
                variables: ["id": key.id],
                responseType: DeleteSSHKeyResponse.self
            )
            sshKeys.removeAll { $0.id == key.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - PGP Keys

    func addPGPKey() async {
        let key = newPGPKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        error = nil

        do {
            let result = try await client.execute(
                service: .meta,
                query: Self.createPGPKeyMutation,
                variables: ["key": key],
                responseType: CreatePGPKeyResponse.self
            )
            pgpKeys.append(result.createPGPKey)
            newPGPKey = ""
            isAddingPGPKey = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deletePGPKey(_ key: PGPKey) async {
        error = nil

        do {
            _ = try await client.execute(
                service: .meta,
                query: Self.deletePGPKeyMutation,
                variables: ["id": key.id],
                responseType: DeletePGPKeyResponse.self
            )
            pgpKeys.removeAll { $0.id == key.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Personal Access Tokens

    func loadPersonalAccessTokens() async {
        guard !isLoadingPATs else { return }
        isLoadingPATs = true

        do {
            let result = try await client.execute(
                service: .meta,
                query: Self.personalAccessTokensQuery,
                responseType: PATListResponse.self
            )
            personalAccessTokens = result.personalAccessTokens
        } catch {
            self.error = error.localizedDescription
        }

        isLoadingPATs = false
    }

}
