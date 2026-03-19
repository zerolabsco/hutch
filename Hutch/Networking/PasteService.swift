import Foundation

struct PasteListPage: Decodable, Sendable {
    let results: [Paste]
    let cursor: String?
}

final class PasteService: Sendable {
    private let client: SRHTClient

    init(client: SRHTClient) {
        self.client = client
    }

    private static let listQuery = """
    query pastes($cursor: Cursor) {
        pastes(cursor: $cursor) {
            results {
                id
                created
                visibility
                files {
                    filename
                    hash
                }
                user {
                    canonicalName
                }
            }
            cursor
        }
    }
    """

    private static let detailQuery = """
    query paste($id: String!) {
        paste(id: $id) {
            id
            created
            visibility
            files {
                filename
                hash
                contents
            }
            user {
                canonicalName
            }
        }
    }
    """

    private static let createMutation = """
    mutation createPaste($files: [Upload!]!, $visibility: Visibility!) {
        create(files: $files, visibility: $visibility) {
            id
            created
            visibility
            files {
                filename
                hash
                contents
            }
            user {
                canonicalName
            }
        }
    }
    """

    private static let updateMutation = """
    mutation updatePaste($id: String!, $visibility: Visibility!) {
        update(id: $id, visibility: $visibility) {
            id
            created
            visibility
            files {
                filename
                hash
                contents
            }
            user {
                canonicalName
            }
        }
    }
    """

    private static let deleteMutation = """
    mutation deletePaste($id: String!) {
        delete(id: $id) {
            id
            created
            visibility
            files {
                filename
                hash
            }
            user {
                canonicalName
            }
        }
    }
    """

    private static let cacheKey = "paste.pastes"

    func listPastes(cursor: String?, useCache: Bool) async throws -> PasteListPage {
        let variables = cursor.map { ["cursor": $0 as any Sendable] }
        let result: PasteListResponse
        if useCache, cursor == nil {
            result = try await client.executeAndCache(
                service: .paste,
                query: Self.listQuery,
                variables: variables,
                responseType: PasteListResponse.self,
                cacheKey: Self.cacheKey
            )
        } else {
            result = try await client.execute(
                service: .paste,
                query: Self.listQuery,
                variables: variables,
                responseType: PasteListResponse.self
            )
        }
        return result.pastes ?? PasteListPage(results: [], cursor: nil)
    }

    func loadCachedPastes() -> PasteListPage? {
        guard let data = client.responseCache.get(forKey: Self.cacheKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .srhtFlexible
        guard let response = try? decoder.decode(GraphQLResponse<PasteListResponse>.self, from: data) else {
            return nil
        }
        return response.data?.pastes
    }

    func loadPaste(id: String) async throws -> Paste? {
        let result = try await client.execute(
            service: .paste,
            query: Self.detailQuery,
            variables: ["id": id],
            responseType: PasteDetailResponse.self
        )
        return result.paste
    }

    func createPaste(files: [PasteUploadDraft], visibility: Visibility) async throws -> Paste {
        let uploadFiles = normalizedUploadFiles(from: files)
        let variables: [String: any Sendable] = [
            "files": [String?](repeating: nil, count: uploadFiles.count),
            "visibility": visibility.rawValue
        ]

        let result = try await client.executeMultipartFiles(
            service: .paste,
            query: Self.createMutation,
            variables: variables,
            files: uploadFiles.enumerated().map { index, file in
                MultipartUploadFile(
                    variablePath: "files.\(index)",
                    fileData: file.data,
                    fileName: file.fileName,
                    mimeType: "text/plain"
                )
            },
            responseType: CreatePasteResponse.self
        )
        return result.create
    }

    func updateVisibility(id: String, visibility: Visibility) async throws -> Paste? {
        let result = try await client.execute(
            service: .paste,
            query: Self.updateMutation,
            variables: ["id": id, "visibility": visibility.rawValue],
            responseType: UpdatePasteResponse.self
        )
        return result.update
    }

    func deletePaste(id: String) async throws -> Paste? {
        let result = try await client.execute(
            service: .paste,
            query: Self.deleteMutation,
            variables: ["id": id],
            responseType: DeletePasteResponse.self
        )
        return result.delete
    }

    func loadContents(from url: URL) async throws -> String {
        try await client.fetchText(url: url)
    }

    private func normalizedUploadFiles(from files: [PasteUploadDraft]) -> [(fileName: String, data: Data)] {
        files.compactMap { draft in
            let text = draft.contents
            guard let data = text.data(using: .utf8) else {
                return nil
            }

            return (draft.filename, data)
        }
    }
}

private struct PasteListResponse: Decodable, Sendable {
    let pastes: PasteListPage?
}

private struct PasteDetailResponse: Decodable, Sendable {
    let paste: Paste?
}

private struct CreatePasteResponse: Decodable, Sendable {
    let create: Paste
}

private struct UpdatePasteResponse: Decodable, Sendable {
    let update: Paste?
}

private struct DeletePasteResponse: Decodable, Sendable {
    let delete: Paste?
}
