import Foundation
import Testing
@testable import Hutch

struct BuildListViewModelTests {

    @Test
    func filteredJobsReturnsAllWhenSearchTextIsEmpty() {
        let jobs = [makeJob(id: 1, tags: ["ci"]), makeJob(id: 2, tags: [])]
        let filtered = filterJobs(jobs, query: "")

        #expect(filtered.count == 2)
    }

    @Test
    func filteredJobsMatchesByTag() {
        let jobs = [makeJob(id: 1, tags: ["ci", "deploy"]), makeJob(id: 2, tags: ["lint"])]
        let filtered = filterJobs(jobs, query: "deploy")

        #expect(filtered.map(\.id) == [1])
    }

    @Test
    func filteredJobsMatchesByJobId() {
        let jobs = [makeJob(id: 42, tags: []), makeJob(id: 99, tags: [])]
        let filtered = filterJobs(jobs, query: "42")

        #expect(filtered.map(\.id) == [42])
    }

    @Test
    func filteredJobsMatchesByStatus() {
        let jobs = [
            makeJob(id: 1, status: .running, tags: []),
            makeJob(id: 2, status: .success, tags: [])
        ]

        let filtered = filterJobs(jobs, query: "running")

        #expect(filtered.map(\.id) == [1])
    }

    @Test
    func buildFilterPrioritizesActionableStates() {
        let jobs = [
            makeJob(id: 1, status: .success, tags: []),
            makeJob(id: 2, status: .failed, tags: []),
            makeJob(id: 3, status: .running, tags: []),
            makeJob(id: 4, status: .cancelled, tags: [])
        ]

        let attention = BuildListViewModel.filterJobs(jobs, filter: .attention)
        let active = BuildListViewModel.filterJobs(jobs, filter: .active)

        #expect(attention.map(\.id) == [2, 3])
        #expect(active.map(\.id) == [3])
    }

    private func filterJobs(_ jobs: [JobSummary], query: String) -> [JobSummary] {
        BuildListViewModel.searchJobs(jobs, matching: query)
    }

    private func makeJob(id: Int, status: JobStatus = .success, tags: [String]) -> JobSummary {
        JobSummary(
            id: id,
            created: Date(),
            updated: Date(),
            status: status,
            note: nil,
            tags: tags,
            visibility: nil,
            image: nil,
            tasks: []
        )
    }
}
