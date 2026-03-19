import Foundation
import Testing
@testable import Hutch

struct ProjectTests {
    @Test
    func resourceSummaryIncludesCounts() {
        let project = Project(
            id: "project-1",
            name: "Hutch",
            description: nil,
            website: nil,
            visibility: .public,
            tags: [],
            mailingLists: [
                Project.MailingList(
                    id: "list-1",
                    name: "hutch-devel",
                    description: nil,
                    visibility: .public,
                    owner: Entity(canonicalName: "~owner")
                )
            ],
            sources: [
                Project.SourceRepo(
                    id: "repo-1",
                    name: "hutch",
                    description: nil,
                    visibility: .public,
                    owner: Entity(canonicalName: "~owner"),
                    repoType: .git
                ),
                Project.SourceRepo(
                    id: "repo-2",
                    name: "hutch-web",
                    description: nil,
                    visibility: .public,
                    owner: Entity(canonicalName: "~owner"),
                    repoType: .git
                )
            ],
            trackers: [
                Project.Tracker(
                    id: "tracker-1",
                    name: "bugs",
                    description: nil,
                    visibility: .public,
                    owner: Entity(canonicalName: "~owner")
                )
            ]
        )

        #expect(project.resourceSummary == "2 repos • 1 tracker • 1 list")
    }

    @Test
    func resourceSummaryFallsBackToWebsite() {
        let project = Project(
            id: "project-1",
            name: "Docs",
            description: nil,
            website: "https://example.com",
            visibility: .public,
            tags: [],
            mailingLists: [],
            sources: [],
            trackers: []
        )

        #expect(project.resourceSummary == "Website linked")
    }
}
