import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct PatchsetDetailResponse: Decodable, Sendable {
    let patchset: PatchsetDetailPayload?
}

private struct PatchsetDetailPayload: Decodable, Sendable {
    let id: Int
    let created: Date
    let updated: Date
    let subject: String
    let version: Int
    let prefix: String?
    let status: PatchsetStatus
    let submitter: Entity
    let coverLetter: PatchsetEmailPayload?
    let supersededBy: PatchsetReferencePayload?
    let supersedes: PatchsetReferencePayload?
    let patches: PatchsetPatchPage
    let tools: [PatchsetToolPayload]
    let mbox: URL?
}

private struct PatchsetReferencePayload: Decodable, Sendable {
    let id: Int
}

private struct PatchsetPatchPage: Decodable, Sendable {
    let results: [PatchsetEmailPayload]
    let cursor: String?
}

private struct PatchsetEmailPayload: Decodable, Sendable {
    let id: Int
    let subject: String
    let date: Date?
    let sender: Entity
    let body: String
    let patch: PatchIndexPayload?
}

private struct PatchIndexPayload: Decodable, Sendable {
    let index: Int?
    let count: Int?
}

private struct PatchsetToolPayload: Decodable, Sendable {
    let id: Int
    let icon: PatchsetToolIcon
    let details: String
}

private struct UpdatePatchsetResponse: Decodable, Sendable {
    let patchset: UpdatedPatchsetPayload?
}

private struct UpdatedPatchsetPayload: Decodable, Sendable {
    let status: PatchsetStatus
}

// MARK: - View Model

@Observable
@MainActor
final class PatchsetDetailViewModel {

    let patchsetID: Int

    private(set) var patchset: PatchsetDetail?
    private(set) var isLoading = false
    private(set) var isUpdatingStatus = false
    var error: String?

    private let client: SRHTClient

    init(patchsetID: Int, client: SRHTClient) {
        self.patchsetID = patchsetID
        self.client = client
    }

    // MARK: - Queries

    /// `patches` is paginated, but a series is small and reviewing half of one is
    /// worse than useless, so every page is walked before rendering.
    private static let detailQuery = """
    query patchset($id: Int!, $cursor: Cursor) {
        patchset(id: $id) {
            id
            created
            updated
            subject
            version
            prefix
            status
            submitter { canonicalName }
            supersededBy { id }
            supersedes { id }
            coverLetter {
                id
                subject
                date
                sender { canonicalName }
                body
                patch { index count }
            }
            patches(cursor: $cursor) {
                results {
                    id
                    subject
                    date
                    sender { canonicalName }
                    body
                    patch { index count }
                }
                cursor
            }
            tools { id icon details }
            mbox
        }
    }
    """

    private static let updateStatusMutation = """
    mutation updatePatchset($id: Int!, $status: PatchsetStatus!) {
        patchset: updatePatchset(id: $id, status: $status) {
            status
        }
    }
    """

    // MARK: - Loading

    func loadPatchset() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            patchset = try await fetchPatchset()
        } catch {
            self.error = error.userFacingMessage
        }
    }

    private func fetchPatchset() async throws -> PatchsetDetail {
        var cursor: String?
        var payload: PatchsetDetailPayload?
        var patches: [PatchsetEmailPayload] = []

        // Walk the patches pages, keeping the first page's patchset fields.
        while true {
            var variables: [String: any Sendable] = ["id": patchsetID]
            if let cursor {
                variables["cursor"] = cursor
            }

            let response = try await client.execute(
                service: .lists,
                query: Self.detailQuery,
                variables: variables,
                responseType: PatchsetDetailResponse.self
            )

            guard let page = response.patchset else {
                throw SRHTError.graphQLErrors([
                    GraphQLError(message: "That patchset is no longer available.", locations: nil)
                ])
            }

            if payload == nil {
                payload = page
            }
            patches.append(contentsOf: page.patches.results)

            guard let next = page.patches.cursor, !next.isEmpty else { break }
            cursor = next
        }

        guard let payload else {
            throw SRHTError.graphQLErrors([
                GraphQLError(message: "That patchset is no longer available.", locations: nil)
            ])
        }

        return PatchsetDetail(
            id: payload.id,
            created: payload.created,
            updated: payload.updated,
            subject: payload.subject,
            version: payload.version,
            prefix: payload.prefix,
            status: payload.status,
            submitter: payload.submitter,
            coverLetter: payload.coverLetter.map { Self.makeEmail(from: $0, isPatch: false) },
            patches: Self.orderPatches(patches.map { Self.makeEmail(from: $0, isPatch: true) }),
            supersededBy: payload.supersededBy?.id,
            supersedes: payload.supersedes?.id,
            tools: payload.tools.map {
                PatchsetToolResult(id: $0.id, icon: $0.icon, details: $0.details)
            },
            mbox: payload.mbox
        )
    }

    // MARK: - Status

    /// Sets the review status. Returns true on success.
    @discardableResult
    func updateStatus(to newStatus: PatchsetStatus) async -> Bool {
        guard !isUpdatingStatus, let current = patchset else { return false }
        guard newStatus != current.status else { return true }

        isUpdatingStatus = true
        error = nil
        defer { isUpdatingStatus = false }

        do {
            let response = try await client.execute(
                service: .lists,
                query: Self.updateStatusMutation,
                variables: [
                    "id": patchsetID,
                    "status": newStatus.rawValue
                ],
                responseType: UpdatePatchsetResponse.self
            )

            // updatePatchset is nullable: null means the server declined without
            // erroring, so the local status must not be advanced.
            guard let updated = response.patchset else {
                self.error = "SourceHut did not apply that status change."
                return false
            }

            apply(status: updated.status)
            return true
        } catch {
            self.error = error.userFacingMessage
            return false
        }
    }

    private func apply(status: PatchsetStatus) {
        guard let current = patchset else { return }
        patchset = PatchsetDetail(
            id: current.id,
            created: current.created,
            updated: current.updated,
            subject: current.subject,
            version: current.version,
            prefix: current.prefix,
            status: status,
            submitter: current.submitter,
            coverLetter: current.coverLetter,
            patches: current.patches,
            supersededBy: current.supersededBy,
            supersedes: current.supersedes,
            tools: current.tools,
            mbox: current.mbox
        )
    }

    // MARK: - Mapping

    private nonisolated static func makeEmail(
        from payload: PatchsetEmailPayload,
        isPatch: Bool
    ) -> PatchsetEmail {
        PatchsetEmail(
            id: payload.id,
            subject: payload.subject,
            date: payload.date,
            sender: payload.sender,
            contentBlocks: InboxThreadUtilities.segmentMessageBody(payload.body, isPatch: isPatch),
            index: payload.patch?.index,
            count: payload.patch?.count
        )
    }

    /// Orders a series by its `[PATCH n/m]` index.
    ///
    /// sr.ht returns patches in receipt order, which is not series order when a
    /// contributor's mail arrives out of sequence. Patches without an index keep
    /// their relative position at the end rather than being dropped.
    nonisolated static func orderPatches(_ patches: [PatchsetEmail]) -> [PatchsetEmail] {
        let indexed = patches.filter { $0.index != nil }
        let unindexed = patches.filter { $0.index == nil }
        return indexed.sorted { ($0.index ?? 0) < ($1.index ?? 0) } + unindexed
    }
}
