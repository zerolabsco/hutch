import Foundation
import Testing
@testable import Hutch

struct ContributionCalendarTests {

    @Test
    @MainActor
    func contributionCalendarDecodingParsesDatesAndCounts() throws {
        let data = Data(
            """
            {
              "actor": "~ccleberg",
              "from": "2026-03-01",
              "to": "2026-04-15",
              "is_indexed": false,
              "last_polled_at": null,
              "indexing_state": "pending",
              "days": [
                { "date": "2026-03-19", "count": 24, "score": 24.0 },
                { "date": "2026-04-02", "count": 20, "score": 18.5 }
              ]
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(ContributionCalendarResponse.self, from: data)

        #expect(decoded.actor == "~ccleberg")
        #expect(decoded.from == ContributionDateParser.parse("2026-03-01"))
        #expect(decoded.to == ContributionDateParser.parse("2026-04-15"))
        #expect(decoded.isIndexed == false)
        #expect(decoded.lastPolledAt == nil)
        #expect(decoded.indexingState == .pending)
        #expect(decoded.days.count == 2)
        #expect(decoded.days[0].date == ContributionDateParser.parse("2026-03-19"))
        #expect(decoded.days[0].count == 24)
        #expect(decoded.days[1].score == 18.5)
    }

    @Test
    @MainActor
    func contributionStatsDecodingParsesSnakeCasePayload() throws {
        let data = Data(
            """
            {
              "actor": "~ccleberg",
              "from": "2026-03-01",
              "to": "2026-04-15",
              "is_indexed": true,
              "last_polled_at": "2026-04-15T15:42:18Z",
              "indexing_state": "indexed",
              "total_events": 126,
              "total_score": 116.75,
              "active_days": 14,
              "longest_streak": 5,
              "current_streak": 0
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(ContributionStatsResponse.self, from: data)

        #expect(decoded.totalEvents == 126)
        #expect(decoded.totalScore == 116.75)
        #expect(decoded.activeDays == 14)
        #expect(decoded.longestStreak == 5)
        #expect(decoded.currentStreak == 0)
        #expect(decoded.isIndexed)
        #expect(decoded.indexingState == .indexed)
        #expect(decoded.lastPolledAt == ContributionDateParser.parseTimestamp("2026-04-15T15:42:18Z"))
    }

    @Test
    func contributionDateParserRejectsInvalidDate() {
        #expect(ContributionDateParser.parse("2026-13-40") == nil)
    }

    @Test
    func contributionTimestampParserHandlesFractionalSecondsWithoutTimezone() {
        let parsed = ContributionDateParser.parseTimestamp("2026-04-11T19:26:45.538015")

        #expect(parsed != nil)
    }

    @Test
    func trailingRangeEndsTodayAndStartsOneYearEarlierPlusOneDay() {
        let service = HutchStatsService(configuration: AppConfiguration())
        let endDate = ContributionDateParser.parse("2026-04-11")!
        let range = service.trailingRange(endingOn: endDate)

        #expect(range.lowerBound == ContributionDateParser.parse("2025-04-12"))
        #expect(range.upperBound == endDate)
    }

    @Test
    func selfContributionRequestsIncludeExplicitPrioritySignal() {
        let service = HutchStatsService(
            configuration: AppConfiguration(),
            currentActor: "~alice"
        )
        let endDate = ContributionDateParser.parse("2026-04-11")!
        let queryItems = service.contributionQueryItems(actor: "~alice", endingOn: endDate)

        #expect(queryItems.contains(URLQueryItem(name: "prioritize", value: "self")))
    }

    @Test
    func otherContributionRequestsDoNotIncludePrioritySignal() {
        let service = HutchStatsService(
            configuration: AppConfiguration(),
            currentActor: "~alice"
        )
        let endDate = ContributionDateParser.parse("2026-04-11")!
        let queryItems = service.contributionQueryItems(actor: "~bob", endingOn: endDate)

        #expect(queryItems.contains(URLQueryItem(name: "prioritize", value: "self")) == false)
    }

    @Test
    func contributionIntensityBucketsMatchProductRules() {
        #expect(ContributionIntensity(count: 0) == .empty)
        #expect(ContributionIntensity(count: 1) == .level1)
        #expect(ContributionIntensity(count: 2) == .level2)
        #expect(ContributionIntensity(count: 3) == .level2)
        #expect(ContributionIntensity(count: 4) == .level3)
        #expect(ContributionIntensity(count: 6) == .level3)
        #expect(ContributionIntensity(count: 7) == .level4)
        #expect(ContributionIntensity(count: 12) == .level4)
    }

    @Test
    func weekColumnsGroupConsecutiveDaysIntoSundayBasedWeeks() {
        let days = [
            ContributionDay(date: ContributionDateParser.parse("2026-03-29")!, count: 1, score: 1),
            ContributionDay(date: ContributionDateParser.parse("2026-03-30")!, count: 2, score: 2),
            ContributionDay(date: ContributionDateParser.parse("2026-04-04")!, count: 3, score: 3),
            ContributionDay(date: ContributionDateParser.parse("2026-04-05")!, count: 4, score: 4)
        ]

        let weeks = ContributionCalendarLayout.weekColumns(from: days)

        #expect(weeks.count == 2)
        #expect(weeks[0].startDate == ContributionDateParser.parse("2026-03-29"))
        #expect(weeks[0].days.map(\.count) == [1, 2, 3])
        #expect(weeks[1].startDate == ContributionDateParser.parse("2026-04-05"))
        #expect(weeks[1].days.map(\.count) == [4])
    }

    @Test
    func recentWeeksReturnsTrailingWindow() {
        let days = (0..<21).compactMap { offset -> ContributionDay? in
            guard let date = Calendar.contributionCalendar.date(byAdding: .day, value: offset, to: ContributionDateParser.parse("2026-03-01")!) else {
                return nil
            }

            return ContributionDay(date: date, count: offset, score: Double(offset))
        }

        let weeks = ContributionCalendarLayout.recentWeeks(from: days, count: 2)

        #expect(weeks.count == 2)
        #expect(weeks[0].startDate == ContributionDateParser.parse("2026-03-08"))
        #expect(weeks[1].startDate == ContributionDateParser.parse("2026-03-15"))
    }

    @Test
    @MainActor
    func emptyCalendarResponseTreatsActivityAsNotIndexedYet() async {
        let service = MockContributionCalendarService(
            calendarResponses: [.pending(actor: "~alice", year: 2026)],
            statsResponses: [.pending(actor: "~alice", year: 2026)]
        )
        let viewModel = ContributionCalendarViewModel(
            actor: "~alice",
            service: service,
            selectedEndDate: ContributionDateParser.parse("2026-04-11")
        )

        await viewModel.load()

        #expect(viewModel.displayState == .indexing)
        #expect(viewModel.emptyStateTitle == "Indexing Activity")
        #expect(viewModel.emptyStateMessage == "This user’s SourceHut activity is being indexed. Check back soon.")
        #expect(viewModel.loadErrorMessage == nil)
    }

    @Test
    @MainActor
    func indexedEmptyCalendarShowsTrueEmptyState() async {
        let service = MockContributionCalendarService(
            calendarResponses: [.empty(actor: "~alice", year: 2026)],
            statsResponses: [.empty(actor: "~alice", year: 2026)]
        )
        let viewModel = ContributionCalendarViewModel(
            actor: "~alice",
            service: service,
            selectedEndDate: ContributionDateParser.parse("2026-04-11")
        )

        await viewModel.load()

        #expect(viewModel.displayState == .empty)
        #expect(viewModel.emptyStateTitle == "No Contribution Activity")
        #expect(viewModel.emptyStateMessage == "No activity was found for this time range.")
    }

    @Test
    @MainActor
    func errorIndexingStateShowsUnavailableState() async {
        let service = MockContributionCalendarService(
            calendarResponses: [.error(actor: "~alice", year: 2026)],
            statsResponses: [.error(actor: "~alice", year: 2026)]
        )
        let viewModel = ContributionCalendarViewModel(
            actor: "~alice",
            service: service,
            selectedEndDate: ContributionDateParser.parse("2026-04-11")
        )

        await viewModel.load()

        #expect(viewModel.displayState == .unavailable)
        #expect(viewModel.emptyStateTitle == "Activity Unavailable")
        #expect(viewModel.emptyStateMessage == "The contribution graph couldn’t be refreshed right now. Try again later.")
    }

    @Test
    @MainActor
    func populatedStatsExposeLastUpdatedText() async {
        let service = MockContributionCalendarService(
            calendarResponses: [.active(actor: "~alice", date: "2026-03-19", count: 4, score: 4)],
            statsResponses: [.active(actor: "~alice", year: 2026, totalEvents: 4, activeDays: 1, longestStreak: 1)]
        )
        let viewModel = ContributionCalendarViewModel(
            actor: "~alice",
            service: service,
            selectedEndDate: ContributionDateParser.parse("2026-04-11")
        )

        await viewModel.load()

        #expect(viewModel.displayState == .populated)
        #expect(viewModel.lastUpdatedText != nil)
    }
}

private final class MockContributionCalendarService: ContributionCalendarServing, @unchecked Sendable {
    var calendarResponses: [ContributionCalendarResponse]
    var statsResponses: [ContributionStatsResponse]
    private(set) var fetchCalendarCallCount = 0
    private(set) var fetchStatsCallCount = 0

    init(
        calendarResponses: [ContributionCalendarResponse],
        statsResponses: [ContributionStatsResponse]
    ) {
        self.calendarResponses = calendarResponses
        self.statsResponses = statsResponses
    }

    func fetchContributionCalendar(actor _: String, endingOn _: Date) async throws -> ContributionCalendarResponse {
        fetchCalendarCallCount += 1
        return calendarResponses[min(fetchCalendarCallCount - 1, calendarResponses.count - 1)]
    }

    func fetchContributionStats(actor _: String, endingOn _: Date) async throws -> ContributionStatsResponse {
        fetchStatsCallCount += 1
        return statsResponses[min(fetchStatsCallCount - 1, statsResponses.count - 1)]
    }
}

private extension ContributionCalendarResponse {
    static func empty(actor: String, year: Int) -> Self {
        let from = ContributionDateParser.parse("\(year)-01-01")!
        let to = ContributionDateParser.parse("\(year)-01-07")!
        return ContributionCalendarResponse(
            actor: actor,
            from: from,
            to: to,
            isIndexed: true,
            lastPolledAt: ContributionDateParser.parseTimestamp("\(year)-01-07T12:00:00Z"),
            indexingState: .indexed,
            days: (1...7).map { day in
                ContributionDay(
                    date: ContributionDateParser.parse("\(year)-01-0\(day)")!,
                    count: 0,
                    score: 0
                )
            }
        )
    }

    static func active(actor: String, date: String, count: Int, score: Double) -> Self {
        let resolvedDate = ContributionDateParser.parse(date)!
        return ContributionCalendarResponse(
            actor: actor,
            from: resolvedDate,
            to: resolvedDate,
            isIndexed: true,
            lastPolledAt: ContributionDateParser.parseTimestamp("2026-03-19T12:00:00Z"),
            indexingState: .indexed,
            days: [ContributionDay(date: resolvedDate, count: count, score: score)]
        )
    }

    static func pending(actor: String, year: Int) -> Self {
        let from = ContributionDateParser.parse("\(year)-01-01")!
        let to = ContributionDateParser.parse("\(year)-01-07")!
        return ContributionCalendarResponse(
            actor: actor,
            from: from,
            to: to,
            isIndexed: false,
            lastPolledAt: nil,
            indexingState: .pending,
            days: (1...7).map { day in
                ContributionDay(
                    date: ContributionDateParser.parse("\(year)-01-0\(day)")!,
                    count: 0,
                    score: 0
                )
            }
        )
    }

    static func error(actor: String, year: Int) -> Self {
        let from = ContributionDateParser.parse("\(year)-01-01")!
        let to = ContributionDateParser.parse("\(year)-01-07")!
        return ContributionCalendarResponse(
            actor: actor,
            from: from,
            to: to,
            isIndexed: false,
            lastPolledAt: nil,
            indexingState: .error,
            days: (1...7).map { day in
                ContributionDay(
                    date: ContributionDateParser.parse("\(year)-01-0\(day)")!,
                    count: 0,
                    score: 0
                )
            }
        )
    }
}

private extension ContributionStatsResponse {
    static func empty(actor: String, year: Int) -> Self {
        ContributionStatsResponse(
            window: .init(
                actor: actor,
                from: ContributionDateParser.parse("\(year)-01-01")!,
                to: ContributionDateParser.parse("\(year)-01-07")!,
                isIndexed: true,
                lastPolledAt: ContributionDateParser.parseTimestamp("\(year)-01-07T12:00:00Z"),
                indexingState: .indexed
            ),
            totals: .init(
                totalEvents: 0,
                totalScore: 0,
                activeDays: 0,
                longestStreak: 0,
                currentStreak: 0
            )
        )
    }

    static func active(actor: String, year: Int, totalEvents: Int, activeDays: Int, longestStreak: Int) -> Self {
        ContributionStatsResponse(
            window: .init(
                actor: actor,
                from: ContributionDateParser.parse("\(year)-01-01")!,
                to: ContributionDateParser.parse("\(year)-01-07")!,
                isIndexed: true,
                lastPolledAt: ContributionDateParser.parseTimestamp("\(year)-01-07T12:00:00Z"),
                indexingState: .indexed
            ),
            totals: .init(
                totalEvents: totalEvents,
                totalScore: Double(totalEvents),
                activeDays: activeDays,
                longestStreak: longestStreak,
                currentStreak: 0
            )
        )
    }

    static func pending(actor: String, year: Int) -> Self {
        ContributionStatsResponse(
            window: .init(
                actor: actor,
                from: ContributionDateParser.parse("\(year)-01-01")!,
                to: ContributionDateParser.parse("\(year)-01-07")!,
                isIndexed: false,
                lastPolledAt: nil,
                indexingState: .pending
            ),
            totals: .init(
                totalEvents: 0,
                totalScore: 0,
                activeDays: 0,
                longestStreak: 0,
                currentStreak: 0
            )
        )
    }

    static func error(actor: String, year: Int) -> Self {
        ContributionStatsResponse(
            window: .init(
                actor: actor,
                from: ContributionDateParser.parse("\(year)-01-01")!,
                to: ContributionDateParser.parse("\(year)-01-07")!,
                isIndexed: false,
                lastPolledAt: nil,
                indexingState: .error
            ),
            totals: .init(
                totalEvents: 0,
                totalScore: 0,
                activeDays: 0,
                longestStreak: 0,
                currentStreak: 0
            )
        )
    }
}
