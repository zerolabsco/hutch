import Foundation

protocol RepositoryACLServicing {
    func fetchACLs(repositoryRid: String) async throws -> [RepositoryACLEntry]
    func upsertACL(repositoryId: Int, entity: String, mode: AccessMode) async throws -> RepositoryACLEntry
    func deleteACL(entryId: Int) async throws
}

private struct RepositoryACLQueryResponse: Decodable, Sendable {
    let repository: RepositoryACLQueryRepository?
}

private struct RepositoryACLQueryRepository: Decodable, Sendable {
    let acls: RepositoryACLPage
}

private struct RepositoryACLPage: Decodable, Sendable {
    let results: [RepositoryACLEntry]
}

private struct RepositoryACLMutationResponse: Decodable, Sendable {
    let updateACL: RepositoryACLEntry
}

private struct RepositoryACLDeleteResponse: Decodable, Sendable {
    let deleteACL: RepositoryACLDeletedEntry
}

private struct RepositoryACLDeletedEntry: Decodable, Sendable {
    let id: Int
}

struct RepositoryACLService: RepositoryACLServicing {
    private let client: SRHTClient
    private let service: SRHTService

    init(client: SRHTClient, service: SRHTService) {
        self.client = client
        self.service = service
    }

    func fetchACLs(repositoryRid: String) async throws -> [RepositoryACLEntry] {
        let response = try await client.execute(
            service: service,
            query: Self.aclsQuery,
            variables: ["rid": repositoryRid],
            responseType: RepositoryACLQueryResponse.self
        )
        return response.repository?.acls.results ?? []
    }

    func upsertACL(repositoryId: Int, entity: String, mode: AccessMode) async throws -> RepositoryACLEntry {
        let response = try await client.execute(
            service: service,
            query: Self.upsertACLMutation,
            variables: [
                "repoId": repositoryId,
                "entity": entity,
                "mode": mode.rawValue
            ],
            responseType: RepositoryACLMutationResponse.self
        )
        return response.updateACL
    }

    func deleteACL(entryId: Int) async throws {
        _ = try await client.execute(
            service: service,
            query: Self.deleteACLMutation,
            variables: ["id": entryId],
            responseType: RepositoryACLDeleteResponse.self
        )
    }
}

private extension RepositoryACLService {
    static let aclsQuery = """
    query repositoryACLs($rid: ID!) {
        repository(rid: $rid) {
            acls {
                results {
                    id
                    mode
                    entity { canonicalName }
                }
            }
        }
    }
    """

    static let upsertACLMutation = """
    mutation updateACL($repoId: Int!, $mode: AccessMode!, $entity: String!) {
        updateACL(repoId: $repoId, mode: $mode, entity: $entity) {
            id
            mode
            entity { canonicalName }
        }
    }
    """

    static let deleteACLMutation = """
    mutation deleteACL($id: Int!) {
        deleteACL(id: $id) { id }
    }
    """
}
