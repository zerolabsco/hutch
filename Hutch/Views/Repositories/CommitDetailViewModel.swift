import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct CommitResponse: Decodable, Sendable {
    let repository: CommitRepository?
}

private struct CommitRepository: Decodable, Sendable {
    let revparseSingle: CommitDetail

    enum CodingKeys: String, CodingKey {
        case revparseSingle = "revparse_single"
    }
}

// MARK: - View Model

@Observable
@MainActor
final class CommitDetailViewModel {

    let repositoryRid: String
    let service: SRHTService
    private let client: SRHTClient

    private(set) var commit: CommitDetail?
    private(set) var isLoading = false
    var error: String?

    init(repositoryRid: String, service: SRHTService, commitId: String, client: SRHTClient) {
        self.repositoryRid = repositoryRid
        self.service = service
        self.commitId = commitId
        self.client = client
    }

    private let commitId: String

    // MARK: - Query

    private static let query = """
    query commit($rid: ID!, $id: String!) {
        repository(rid: $rid) {
            revparse_single(revspec: $id) {
                id
                shortId
                author { name email time }
                committer { name email time }
                message
                diff
                trailers { name value }
                parents { id shortId author { name } }
                tree {
                    entries {
                        results { id name mode object { type id shortId } }
                        cursor
                    }
                }
            }
        }
    }
    """

    func loadCommit() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            let result = try await executeWithRetry()
            commit = result.repository?.revparseSingle
        } catch {
            self.error = error.userFacingMessage
        }

        isLoading = false
    }

    /// Execute the commit query, retrying once after a 1-second delay on 502/503.
    private func executeWithRetry() async throws -> CommitResponse {
        do {
            return try await client.execute(
                service: service,
                query: Self.query,
                variables: [
                    "rid": repositoryRid,
                    "id": commitId
                ],
                responseType: CommitResponse.self
            )
        } catch let SRHTError.httpError(code) where code == 502 || code == 503 {
            try await Task.sleep(for: .seconds(1))
            return try await client.execute(
                service: service,
                query: Self.query,
                variables: [
                    "rid": repositoryRid,
                    "id": commitId
                ],
                responseType: CommitResponse.self
            )
        }
    }
}
