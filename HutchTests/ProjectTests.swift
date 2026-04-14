import Foundation
import Testing
@testable import Hutch

struct ProjectTests {
    private enum Fixture {
        static let exampleWebsite = "https://example.com"
    }

    @Test
    func resourceSummaryIncludesCounts() {
        let project = Project(
            metadata: .init(
                id: "project-1",
                name: "Hutch",
                description: nil,
                website: nil,
                visibility: .public,
                tags: [],
                updated: Date(timeIntervalSince1970: 0)
            ),
            resources: .init(
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
                ],
                isFullyLoaded: true
            )
        )

        #expect(project.resourceSummary == "2 repos • 1 tracker • 1 list")
    }

    @Test
    func resourceSummaryFallsBackToWebsite() {
        let project = Project(
            metadata: .init(
                id: "project-1",
                name: "Docs",
                description: nil,
                website: Fixture.exampleWebsite,
                visibility: .public,
                tags: [],
                updated: Date(timeIntervalSince1970: 0)
            ),
            resources: .init(mailingLists: [], sources: [], trackers: [], isFullyLoaded: true)
        )

        #expect(project.resourceSummary == "Website linked")
    }

    @Test
    func displayHelpersNormalizeBlankValues() {
        let project = Project(
            metadata: .init(
                id: "project-1",
                name: "  ",
                description: "\n",
                website: Fixture.exampleWebsite,
                visibility: .unlisted,
                tags: [" docs ", "", "Docs", "ios"],
                updated: Date(timeIntervalSince1970: 0)
            ),
            resources: .init(mailingLists: [], sources: [], trackers: [], isFullyLoaded: true)
        )

        #expect(project.displayName == "Untitled Project")
        #expect(project.displayDescription == nil)
        #expect(project.displayTags == ["docs", "ios"])
        #expect(project.metadataLine.contains("Unlisted"))
    }
}
