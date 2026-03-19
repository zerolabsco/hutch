import Foundation
import Testing
@testable import Hutch

struct BuildTaskTests {

    @Test
    @MainActor
    func duplicateTaskNamesProduceDistinctIDsAndLogCacheKeys() {
        let firstTask = BuildTask(
            name: "test",
            status: .failed,
            log: BuildLog(fullURL: "https://builds.sr.ht/job/1/task/1")
        ).withOrdinal(0)

        let secondTask = BuildTask(
            name: "test",
            status: .failed,
            log: BuildLog(fullURL: "https://builds.sr.ht/job/1/task/2")
        ).withOrdinal(1)

        #expect(firstTask.id == "0:test")
        #expect(secondTask.id == "1:test")
        #expect(firstTask.id != secondTask.id)
        #expect(firstTask.logCacheKey != secondTask.logCacheKey)
    }
}
