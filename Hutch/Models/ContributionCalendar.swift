import Foundation

struct ContributionCalendarResponse: Decodable, Sendable, Hashable {
    let actor: String
    let from: Date
    let to: Date
    let isIndexed: Bool
    let lastPolledAt: Date?
    let indexingState: ContributionIndexingState
    let days: [ContributionDay]

    enum CodingKeys: String, CodingKey {
        case actor
        case from
        case to
        case isIndexed = "is_indexed"
        case lastPolledAt = "last_polled_at"
        case indexingState = "indexing_state"
        case days
    }

    init(
        actor: String,
        from: Date,
        to: Date,
        isIndexed: Bool,
        lastPolledAt: Date?,
        indexingState: ContributionIndexingState,
        days: [ContributionDay]
    ) {
        self.actor = actor
        self.from = from
        self.to = to
        self.isIndexed = isIndexed
        self.lastPolledAt = lastPolledAt
        self.indexingState = indexingState
        self.days = days.sorted { $0.date < $1.date }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actor = try container.decode(String.self, forKey: .actor)
        from = try ContributionDateParser.decodeDateString(from: container, forKey: .from)
        to = try ContributionDateParser.decodeDateString(from: container, forKey: .to)
        isIndexed = try container.decodeIfPresent(Bool.self, forKey: .isIndexed) ?? false
        lastPolledAt = try ContributionDateParser.decodeOptionalTimestamp(from: container, forKey: .lastPolledAt)
        indexingState = try container.decodeIfPresent(ContributionIndexingState.self, forKey: .indexingState) ?? .indexed
        days = try container.decode([ContributionDay].self, forKey: .days).sorted { $0.date < $1.date }
    }

    var totalCount: Int {
        days.reduce(into: 0) { partialResult, day in
            partialResult += day.count
        }
    }

    var isEmpty: Bool {
        totalCount == 0
    }
}

struct ContributionDay: Decodable, Sendable, Hashable, Identifiable {
    var id: Date { date }

    let date: Date
    let count: Int
    let score: Double

    enum CodingKeys: String, CodingKey {
        case date
        case count
        case score
    }

    init(date: Date, count: Int, score: Double) {
        self.date = date
        self.count = count
        self.score = score
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try ContributionDateParser.decodeDateString(from: container, forKey: .date)
        count = try container.decode(Int.self, forKey: .count)
        score = try container.decode(Double.self, forKey: .score)
    }

    var intensity: ContributionIntensity {
        ContributionIntensity(count: count)
    }
}

struct ContributionStatsResponse: Decodable, Sendable, Hashable {
    let actor: String
    let from: Date
    let to: Date
    let isIndexed: Bool
    let lastPolledAt: Date?
    let indexingState: ContributionIndexingState
    let totalEvents: Int
    let totalScore: Double
    let activeDays: Int
    let longestStreak: Int
    let currentStreak: Int

    enum CodingKeys: String, CodingKey {
        case actor
        case from
        case to
        case isIndexed = "is_indexed"
        case lastPolledAt = "last_polled_at"
        case indexingState = "indexing_state"
        case totalEvents = "total_events"
        case totalScore = "total_score"
        case activeDays = "active_days"
        case longestStreak = "longest_streak"
        case currentStreak = "current_streak"
    }

    init(
        actor: String,
        from: Date,
        to: Date,
        isIndexed: Bool,
        lastPolledAt: Date?,
        indexingState: ContributionIndexingState,
        totalEvents: Int,
        totalScore: Double,
        activeDays: Int,
        longestStreak: Int,
        currentStreak: Int
    ) {
        self.actor = actor
        self.from = from
        self.to = to
        self.isIndexed = isIndexed
        self.lastPolledAt = lastPolledAt
        self.indexingState = indexingState
        self.totalEvents = totalEvents
        self.totalScore = totalScore
        self.activeDays = activeDays
        self.longestStreak = longestStreak
        self.currentStreak = currentStreak
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actor = try container.decode(String.self, forKey: .actor)
        from = try ContributionDateParser.decodeDateString(from: container, forKey: .from)
        to = try ContributionDateParser.decodeDateString(from: container, forKey: .to)
        isIndexed = try container.decodeIfPresent(Bool.self, forKey: .isIndexed) ?? false
        lastPolledAt = try ContributionDateParser.decodeOptionalTimestamp(from: container, forKey: .lastPolledAt)
        indexingState = try container.decodeIfPresent(ContributionIndexingState.self, forKey: .indexingState) ?? .indexed
        totalEvents = try container.decode(Int.self, forKey: .totalEvents)
        totalScore = try container.decode(Double.self, forKey: .totalScore)
        activeDays = try container.decode(Int.self, forKey: .activeDays)
        longestStreak = try container.decode(Int.self, forKey: .longestStreak)
        currentStreak = try container.decode(Int.self, forKey: .currentStreak)
    }
}

enum ContributionIndexingState: String, Codable, Sendable, Hashable {
    case pending
    case indexed
    case error
}

enum ContributionIntensity: Int, Sendable, CaseIterable {
    case empty = 0
    case level1 = 1
    case level2 = 2
    case level3 = 3
    case level4 = 4

    init(count: Int) {
        switch count {
        case ..<1:
            self = .empty
        case 1:
            self = .level1
        case 2...3:
            self = .level2
        case 4...6:
            self = .level3
        default:
            self = .level4
        }
    }
}

struct ContributionWeek: Sendable, Hashable {
    let startDate: Date
    let days: [ContributionDay]
}

enum ContributionCalendarLayout {
    static func weekColumns(
        from days: [ContributionDay],
        calendar: Calendar = .contributionCalendar
    ) -> [ContributionWeek] {
        let groupedDays = Dictionary(grouping: days) { day in
            calendar.startOfWeek(for: day.date)
        }

        return groupedDays.keys.sorted().map { weekStart in
            ContributionWeek(
                startDate: weekStart,
                days: groupedDays[weekStart, default: []].sorted { $0.date < $1.date }
            )
        }
    }

    static func recentWeeks(
        from days: [ContributionDay],
        count: Int,
        calendar: Calendar = .contributionCalendar
    ) -> [ContributionWeek] {
        Array(weekColumns(from: days, calendar: calendar).suffix(count))
    }
}

enum ContributionDateParser {
    static func parse(_ rawValue: String) -> Date? {
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return nil
        }

        var components = DateComponents()
        components.calendar = .contributionCalendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day

        guard let date = components.date else {
            return nil
        }

        let resolvedComponents = Calendar.contributionCalendar.dateComponents([.year, .month, .day], from: date)
        guard
            resolvedComponents.year == year,
            resolvedComponents.month == month,
            resolvedComponents.day == day
        else {
            return nil
        }

        return date
    }

    static func decodeDateString<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Date {
        let rawValue = try container.decode(String.self, forKey: key)

        guard let date = parse(rawValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Invalid contribution date: \(rawValue)"
            )
        }

        return date
    }

    static func parseTimestamp(_ rawValue: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        if let date = formatter.date(from: rawValue) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: rawValue) {
            return date
        }

        let fallbackFormats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss"
        ]

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = .contributionCalendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in fallbackFormats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: rawValue) {
                return date
            }
        }

        return nil
    }

    static func decodeOptionalTimestamp<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Date? {
        guard let rawValue = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        guard let date = parseTimestamp(rawValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Invalid contribution timestamp: \(rawValue)"
            )
        }

        return date
    }
}

extension Calendar {
    static var contributionCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}
