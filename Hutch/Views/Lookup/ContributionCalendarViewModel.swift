import Foundation

@Observable
@MainActor
final class ContributionCalendarViewModel {
    enum DisplayState: Equatable {
        case populated
        case indexing
        case empty
        case unavailable
    }

    private(set) var calendar: ContributionCalendarResponse?
    private(set) var stats: ContributionStatsResponse?
    private(set) var isLoading = false
    var loadErrorMessage: String?
    var selectedEndDate: Date

    let actor: String

    private let service: any ContributionCalendarServing
    private let currentEndDate: Date

    init(
        actor: String,
        service: any ContributionCalendarServing,
        selectedEndDate: Date? = nil
    ) {
        self.actor = actor
        self.service = service
        let today = Calendar.contributionCalendar.startOfDay(for: Date())
        let resolvedEndDate = Calendar.contributionCalendar.startOfDay(for: selectedEndDate ?? today)
        self.selectedEndDate = resolvedEndDate
        self.currentEndDate = today
    }

    var weekColumns: [ContributionWeek] {
        ContributionCalendarLayout.weekColumns(from: calendar?.days ?? [])
    }

    var recentWeekColumns: [ContributionWeek] {
        ContributionCalendarLayout.recentWeeks(from: calendar?.days ?? [], count: 8)
    }

    var isEmpty: Bool {
        calendar?.isEmpty ?? false
    }

    var isIndexedButEmpty: Bool {
        displayState != .populated
            && displayState != .unavailable
            && ((stats?.totalEvents == 0) || (calendar?.isEmpty == true))
    }

    var displayState: DisplayState {
        if hasActivity {
            return .populated
        }

        switch effectiveIndexingState {
        case .pending:
            return .indexing
        case .error:
            return .unavailable
        case .indexed:
            return .empty
        case nil:
            return .empty
        }
    }

    var emptyStateTitle: String {
        switch displayState {
        case .indexing:
            "Indexing Activity"
        case .empty:
            "No Contribution Activity"
        case .unavailable:
            "Activity Unavailable"
        case .populated:
            ""
        }
    }

    var emptyStateMessage: String {
        switch displayState {
        case .indexing:
            "This user’s SourceHut activity is being indexed. Check back soon."
        case .empty:
            "No activity was found for this time range."
        case .unavailable:
            "The contribution graph couldn’t be refreshed right now. Try again later."
        case .populated:
            ""
        }
    }

    var lastUpdatedText: String? {
        guard let lastPolledAt = effectiveLastPolledAt else {
            return nil
        }

        return "Updated \(lastPolledAt.formatted(date: .abbreviated, time: .shortened))"
    }

    var canAdvanceYear: Bool {
        selectedEndDate < currentEndDate
    }

    var displayedRangeText: String {
        let range = trailingRange
        return "\(range.lowerBound.formatted(date: .abbreviated, time: .omitted)) to \(range.upperBound.formatted(date: .abbreviated, time: .omitted))"
    }

    func load() async {
        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }
        let fetchedCalendar: ContributionCalendarResponse?
        let fetchedStats: ContributionStatsResponse?
        var errors: [any Error] = []

        do {
            fetchedCalendar = try await service.fetchContributionCalendar(actor: actor, endingOn: selectedEndDate)
        } catch {
            fetchedCalendar = nil
            errors.append(error)
        }

        do {
            fetchedStats = try await service.fetchContributionStats(actor: actor, endingOn: selectedEndDate)
        } catch {
            fetchedStats = nil
            errors.append(error)
        }

        calendar = fetchedCalendar
        stats = fetchedStats

        if displayState != .unavailable {
            loadErrorMessage = nil
        } else if fetchedCalendar == nil && fetchedStats == nil {
            loadErrorMessage = errors.first?.userFacingMessage
        } else {
            loadErrorMessage = errors.first?.userFacingMessage
        }

    }

    func selectPreviousYear() async {
        guard let previousEndDate = Calendar.contributionCalendar.date(byAdding: .year, value: -1, to: selectedEndDate) else {
            return
        }
        selectedEndDate = previousEndDate
        await load()
    }

    func selectNextYear() async {
        guard canAdvanceYear else { return }
        let advancedDate = Calendar.contributionCalendar.date(byAdding: .year, value: 1, to: selectedEndDate) ?? currentEndDate
        selectedEndDate = min(advancedDate, currentEndDate)
        await load()
    }

    private var hasActivity: Bool {
        if let stats, stats.totalEvents > 0 {
            return true
        }

        if let calendar, !calendar.isEmpty {
            return true
        }

        return false
    }

    private var effectiveIndexingState: ContributionIndexingState? {
        stats?.indexingState ?? calendar?.indexingState
    }

    private var effectiveLastPolledAt: Date? {
        stats?.lastPolledAt ?? calendar?.lastPolledAt
    }

    private var trailingRange: ClosedRange<Date> {
        let normalizedEndDate = Calendar.contributionCalendar.startOfDay(for: selectedEndDate)
        let oneYearBack = Calendar.contributionCalendar.date(byAdding: .year, value: -1, to: normalizedEndDate) ?? normalizedEndDate
        let normalizedStartDate = Calendar.contributionCalendar.date(byAdding: .day, value: 1, to: oneYearBack) ?? oneYearBack
        return normalizedStartDate...normalizedEndDate
    }

}
