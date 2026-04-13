import Foundation

private struct ProjectPageResponse: Decodable, Sendable {
    let me: ProjectPageUser
}

private struct ProjectPageUser: Decodable, Sendable {
    let projects: ProjectPage
}

private struct ProjectPage: Decodable, Sendable {
    let results: [ProjectSummaryPayload]
    let cursor: String?
}

private struct ProjectSummaryPayload: Decodable, Sendable {
    let rid: String
    let name: String
    let description: String?
    let website: String?
    let visibility: Visibility
    let tags: [String]
    let updated: Date
}

private struct ProjectDetailResponse: Decodable, Sendable {
    let project: ProjectDetailPayload?
}

private struct ProjectDetailPayload: Decodable, Sendable {
    let rid: String
    let name: String
    let description: String?
    let website: String?
    let visibility: Visibility
    let tags: [String]
    let updated: Date
    let mailingLists: ProjectMailingListPage
    let sources: ProjectSourcePage
    let trackers: ProjectTrackerPage
}

private struct ProjectMailingListPage: Decodable, Sendable {
    let results: [ProjectMailingListPayload]
    let cursor: String?
}

private struct ProjectMailingListPayload: Decodable, Sendable {
    let rid: String
    let name: String
    let description: String?
    let visibility: Visibility
    let owner: Entity
}

private struct ProjectSourcePage: Decodable, Sendable {
    let results: [ProjectSourcePayload]
    let cursor: String?
}

private struct ProjectSourcePayload: Decodable, Sendable {
    let rid: String
    let name: String
    let description: String?
    let visibility: Visibility
    let owner: Entity
    let repoType: Project.SourceRepo.RepoType
}

private struct ProjectTrackerPage: Decodable, Sendable {
    let results: [ProjectTrackerPayload]
    let cursor: String?
}

private struct ProjectTrackerPayload: Decodable, Sendable {
    let rid: String
    let name: String
    let description: String?
    let visibility: Visibility
    let owner: Entity
}

struct ProjectService: Sendable {
    private let client: SRHTClient

    private static let projectsQuery = """
    query meProjects($cursor: Cursor) {
        me {
            projects(cursor: $cursor) {
                results {
                    rid
                    name
                    description
                    website
                    visibility
                    tags
                    updated
                }
                cursor
            }
        }
    }
    """

    private static let projectDetailQuery = """
    query projectDetail($rid: ID!, $mailingListsCursor: Cursor, $sourcesCursor: Cursor, $trackersCursor: Cursor) {
        project(rid: $rid) {
            rid
            name
            description
            website
            visibility
            tags
            updated
            mailingLists(cursor: $mailingListsCursor) {
                results {
                    rid
                    name
                    description
                    visibility
                    owner { canonicalName }
                }
                cursor
            }
            sources(cursor: $sourcesCursor) {
                results {
                    rid
                    name
                    description
                    visibility
                    owner { canonicalName }
                    repoType
                }
                cursor
            }
            trackers(cursor: $trackersCursor) {
                results {
                    rid
                    name
                    description
                    visibility
                    owner { canonicalName }
                }
                cursor
            }
        }
    }
    """

    init(client: SRHTClient) {
        self.client = client
    }

    func fetchProjects() async throws -> [Project] {
        try await fetchProjectSummaries().map(Self.makeSummaryProject)
    }

    func fetchProjectDetail(rid: String) async throws -> Project {
        try await fetchProjectDetailPayload(rid: rid)
    }

    private func fetchProjectSummaries() async throws -> [ProjectSummaryPayload] {
        var results: [ProjectSummaryPayload] = []
        var cursor: String?

        while true {
            var variables: [String: any Sendable] = [:]
            if let cursor {
                variables["cursor"] = cursor
            }

            let response = try await client.execute(
                service: .hub,
                query: Self.projectsQuery,
                variables: variables.isEmpty ? nil : variables,
                responseType: ProjectPageResponse.self
            )

            results.append(contentsOf: response.me.projects.results)
            guard let nextCursor = response.me.projects.cursor else {
                break
            }
            cursor = nextCursor
        }

        return results.sorted { $0.updated > $1.updated }
    }

    private func fetchProjectDetailPayload(rid: String) async throws -> Project {
        var mailingLists: [Project.MailingList] = []
        var sources: [Project.SourceRepo] = []
        var trackers: [Project.Tracker] = []
        var mailingListsCursor: String?
        var sourcesCursor: String?
        var trackersCursor: String?

        while true {
            var variables: [String: any Sendable] = ["rid": rid]
            if let mailingListsCursor {
                variables["mailingListsCursor"] = mailingListsCursor
            }
            if let sourcesCursor {
                variables["sourcesCursor"] = sourcesCursor
            }
            if let trackersCursor {
                variables["trackersCursor"] = trackersCursor
            }

            let response = try await client.execute(
                service: .hub,
                query: Self.projectDetailQuery,
                variables: variables,
                responseType: ProjectDetailResponse.self
            )

            guard let project = response.project else {
                throw SRHTError.decodingError(
                    DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing project payload"))
                )
            }

            mailingLists.append(contentsOf: project.mailingLists.results.map {
                Project.MailingList(
                    id: $0.rid,
                    name: $0.name,
                    description: $0.description,
                    visibility: $0.visibility,
                    owner: $0.owner
                )
            })
            sources.append(contentsOf: project.sources.results.map {
                Project.SourceRepo(
                    id: $0.rid,
                    name: $0.name,
                    description: $0.description,
                    visibility: $0.visibility,
                    owner: $0.owner,
                    repoType: $0.repoType
                )
            })
            trackers.append(contentsOf: project.trackers.results.map {
                Project.Tracker(
                    id: $0.rid,
                    name: $0.name,
                    description: $0.description,
                    visibility: $0.visibility,
                    owner: $0.owner
                )
            })

            mailingListsCursor = project.mailingLists.cursor
            sourcesCursor = project.sources.cursor
            trackersCursor = project.trackers.cursor

            if mailingListsCursor == nil, sourcesCursor == nil, trackersCursor == nil {
                return Project(
                    id: project.rid,
                    name: project.name,
                    description: project.description,
                    website: project.website,
                    visibility: project.visibility,
                    tags: project.tags,
                    updated: project.updated,
                    mailingLists: deduplicate(mailingLists),
                    sources: deduplicate(sources),
                    trackers: deduplicate(trackers),
                    isFullyLoaded: true
                )
            }
        }
    }

    private static func makeSummaryProject(from summary: ProjectSummaryPayload) -> Project {
        Project(
            id: summary.rid,
            name: summary.name,
            description: summary.description,
            website: summary.website,
            visibility: summary.visibility,
            tags: summary.tags,
            updated: summary.updated,
            mailingLists: [],
            sources: [],
            trackers: [],
            isFullyLoaded: false
        )
    }

    private func deduplicate<T: Identifiable & Hashable>(_ items: [T]) -> [T] where T.ID: Hashable {
        var seen = Set<T.ID>()
        return items.filter { item in
            seen.insert(item.id).inserted
        }
    }
}
