import SwiftUI
import WidgetKit

struct ContributionGraphEntry: TimelineEntry {
    let date: Date
    let actor: String?
    let state: State
    let weeks: [ContributionGraphWeek]

    enum State {
        case placeholder
        case disabled
        case unavailable
        case empty
        case indexing
        case populated
    }
}

struct ContributionGraphTimelineProvider: TimelineProvider {
    func placeholder(in _: Context) -> ContributionGraphEntry {
        ContributionGraphEntry(
            date: .now,
            actor: "~ccleberg",
            state: .placeholder,
            weeks: ContributionGraphSampleData.placeholderWeeks
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (ContributionGraphEntry) -> Void) {
        Task {
            completion(await loadEntry())
        }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<ContributionGraphEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            let refreshDate = Calendar.contributionCalendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))
        }
    }

    private func loadEntry() async -> ContributionGraphEntry {
        guard ContributionWidgetContextStore.isEnabled() else {
            return ContributionGraphEntry(date: .now, actor: nil, state: .disabled, weeks: [])
        }

        guard let actor = ContributionWidgetContextStore.loadActor(), !actor.isEmpty else {
            return ContributionGraphEntry(date: .now, actor: nil, state: .unavailable, weeks: [])
        }

        do {
            let response = try await ContributionGraphWidgetService().fetchCalendar(actor: actor)
            let state: ContributionGraphEntry.State
            if response.totalCount > 0 {
                state = .populated
            } else {
                switch response.indexingState {
                case .pending:
                    state = .indexing
                case .error:
                    state = .unavailable
                case .indexed:
                    state = .empty
                }
            }

            return ContributionGraphEntry(
                date: .now,
                actor: actor,
                state: state,
                weeks: ContributionGraphLayout.weekColumns(from: response.days)
            )
        } catch {
            return ContributionGraphEntry(date: .now, actor: actor, state: .unavailable, weeks: [])
        }
    }
}

struct ContributionGraphWidget: Widget {
    static let kind = ContributionGraphWidgetConfiguration.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ContributionGraphTimelineProvider()) { entry in
            ContributionGraphWidgetView(entry: entry)
        }
        .configurationDisplayName("Contribution Graph")
        .description("A trailing 365-day SourceHut contribution heatmap for your current profile.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct ContributionGraphWidgetView: View {
    let entry: ContributionGraphEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch entry.state {
            case .disabled:
                messageView(
                    title: "Contributions Disabled",
                    detail: "Enable contribution graphs in Hutch settings to use this widget."
                )
            case .unavailable:
                messageView(
                    title: "Open Hutch",
                    detail: "Sign in and open your profile to load contribution data."
                )
            default:
                graphView
            }
        }
        .widgetURL(URL(string: "hutch://home"))
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private var graphView: some View {
        GeometryReader { geometry in
            let cellSize = ContributionGraphSizing.baseCellSize(availableHeight: geometry.size.height)
            let layout = ContributionGraphSizing.layout(availableSize: geometry.size, cellSize: cellSize)
            let weeks = displayedWeeks(columnCount: layout.columns)

            let actualSize = ContributionGraphSizing.contentSize(
                columns: weeks.count, cellSize: layout.cellSize, spacing: layout.spacing
            )

            ContributionGraphGridView(
                weeks: weeks,
                squareSize: layout.cellSize,
                spacing: layout.spacing
            )
            .frame(width: actualSize.width, height: actualSize.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func messageView(title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(family == .systemSmall ? .headline : .title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func displayedWeeks(columnCount: Int) -> [ContributionGraphWeek] {
        var baseWeeks = switch entry.state {
        case .populated, .indexing:
            entry.weeks
        case .empty:
            ContributionGraphSampleData.emptyWeeks
        case .placeholder, .disabled, .unavailable:
            ContributionGraphSampleData.placeholderWeeks
        }

        if entry.state != .empty {
            // Drop any trailing week where every day has zero contributions.
            while let last = baseWeeks.last, last.days.allSatisfy({ $0.count == 0 }) {
                baseWeeks.removeLast()
            }
        }

        return Array(baseWeeks.suffix(columnCount))
    }
}

private struct ContributionGraphGridView: View {
    let weeks: [ContributionGraphWeek]
    let squareSize: CGFloat
    let spacing: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(weeks, id: \.startDate) { week in
                VStack(spacing: spacing) {
                    ForEach(Array(week.slots.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: squareSize * 0.2, style: .continuous)
                            .fill((day?.intensity ?? .empty).color)
                            .frame(width: squareSize, height: squareSize)
                            .overlay {
                                let intensity = day?.intensity ?? .empty
                                RoundedRectangle(cornerRadius: squareSize * 0.2, style: .continuous)
                                    .stroke(Color.primary.opacity(intensity == .empty ? 0.08 : 0), lineWidth: 0.5)
                            }
                    }
                }
            }
        }
    }
}

private enum ContributionGraphSizing {
    static let rowCount = 7
    static let cellSpacing: CGFloat = 3

    struct GridLayout {
        let rows: Int
        let columns: Int
        let cellSize: CGFloat
        let spacing: CGFloat

        var contentSize: CGSize {
            let w = CGFloat(columns) * cellSize + CGFloat(max(0, columns - 1)) * spacing
            let h = CGFloat(rows) * cellSize + CGFloat(max(0, rows - 1)) * spacing
            return CGSize(width: w, height: h)
        }
    }

    /// Cell size derived from available height so 7 rows fill it exactly.
    static func baseCellSize(availableHeight: CGFloat) -> CGFloat {
        floor((availableHeight - cellSpacing * CGFloat(rowCount - 1)) / CGFloat(rowCount))
    }

    /// Compute layout for any family: 7 rows, as many columns as fit at the given cell size.
    static func layout(availableSize: CGSize, cellSize: CGFloat) -> GridLayout {
        let columns = max(1, Int(floor((availableSize.width + cellSpacing) / (cellSize + cellSpacing))))
        return GridLayout(rows: rowCount, columns: columns, cellSize: cellSize, spacing: cellSpacing)
    }

    /// Content size for the actual number of displayed columns (may differ from layout max).
    static func contentSize(columns: Int, cellSize: CGFloat, spacing: CGFloat) -> CGSize {
        let w = CGFloat(columns) * cellSize + CGFloat(max(0, columns - 1)) * spacing
        let h = CGFloat(rowCount) * cellSize + CGFloat(max(0, rowCount - 1)) * spacing
        return CGSize(width: w, height: h)
    }
}

private struct ContributionGraphWidgetService {
    private let baseURL = URL(string: "https://hutch-stats.zerolabs.sh")!

    func fetchCalendar(actor: String) async throws -> ContributionGraphResponse {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        components.path = "/api/contributions/\(actor)"
        let range = trailingRange(endingOn: Date())
        components.queryItems = [
            URLQueryItem(name: "from", value: Self.rangeFormatter.string(from: range.lowerBound)),
            URLQueryItem(name: "to", value: Self.rangeFormatter.string(from: range.upperBound))
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(ContributionGraphResponse.self, from: data)
    }

    private func trailingRange(endingOn endDate: Date) -> ClosedRange<Date> {
        let normalizedEndDate = Calendar.contributionCalendar.startOfDay(for: endDate)
        let oneYearBack = Calendar.contributionCalendar.date(byAdding: .year, value: -1, to: normalizedEndDate) ?? normalizedEndDate
        let normalizedStartDate = Calendar.contributionCalendar.date(byAdding: .day, value: 1, to: oneYearBack) ?? oneYearBack
        return normalizedStartDate...normalizedEndDate
    }

    private static let rangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .contributionCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct ContributionGraphResponse: Decodable {
    let actor: String
    let indexingState: ContributionGraphIndexingState
    let days: [ContributionGraphDay]

    enum CodingKeys: String, CodingKey {
        case actor
        case indexingState = "indexing_state"
        case days
    }

    var totalCount: Int {
        days.reduce(0) { $0 + $1.count }
    }
}

struct ContributionGraphDay: Decodable, Identifiable {
    var id: Date { date }

    let date: Date
    let count: Int

    enum CodingKeys: String, CodingKey {
        case date
        case count
    }

    var intensity: ContributionGraphIntensity {
        ContributionGraphIntensity(count: count)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try ContributionGraphDateParser.decodeDateString(from: container, forKey: .date)
        count = try container.decode(Int.self, forKey: .count)
    }
}

private enum ContributionGraphIndexingState: String, Decodable {
    case pending
    case indexed
    case error
}

enum ContributionGraphIntensity: Int, CaseIterable {
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

    var color: Color {
        switch self {
        case .empty:
            Color(uiColor: .secondarySystemFill)
        case .level1:
            Color(red: 0.82, green: 0.92, blue: 0.83)
        case .level2:
            Color(red: 0.58, green: 0.83, blue: 0.61)
        case .level3:
            Color(red: 0.25, green: 0.69, blue: 0.36)
        case .level4:
            Color(red: 0.12, green: 0.47, blue: 0.21)
        }
    }
}

struct ContributionGraphWeek {
    let startDate: Date
    let days: [ContributionGraphDay]

    var slots: [ContributionGraphDay?] {
        let calendar = Calendar.contributionCalendar
        let indexedDays = Dictionary(uniqueKeysWithValues: days.map { day in
            (calendar.component(.weekday, from: day.date), day)
        })

        return (1...7).map { weekday in
            indexedDays[weekday]
        }
    }
}

private enum ContributionGraphLayout {
    static func weekColumns(from days: [ContributionGraphDay]) -> [ContributionGraphWeek] {
        let groupedDays = Dictionary(grouping: days) { day in
            Calendar.contributionCalendar.startOfWeek(for: day.date)
        }

        return groupedDays.keys.sorted().map { weekStart in
            ContributionGraphWeek(
                startDate: weekStart,
                days: groupedDays[weekStart, default: []].sorted { $0.date < $1.date }
            )
        }
    }
}

private enum ContributionGraphDateParser {
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
        return components.date
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
}

private enum ContributionGraphSampleData {
    static let emptyWeeks: [ContributionGraphWeek] = {
        let startDate = Calendar.contributionCalendar.startOfDay(for: .now)
        let days = (0..<371).compactMap { offset -> ContributionGraphDay? in
            guard let date = Calendar.contributionCalendar.date(byAdding: .day, value: -offset, to: startDate) else {
                return nil
            }
            return ContributionGraphDay(date: date, count: 0, score: 0)
        }
        return ContributionGraphLayout.weekColumns(from: days)
    }()

    static let placeholderWeeks: [ContributionGraphWeek] = {
        let startDate = Calendar.contributionCalendar.startOfDay(for: .now)
        let days = (0..<150).compactMap { offset -> ContributionGraphDay? in
            guard let date = Calendar.contributionCalendar.date(byAdding: .day, value: -offset, to: startDate) else {
                return nil
            }
            return ContributionGraphDay(date: date, count: (offset % 8), score: 0)
        }
        return ContributionGraphLayout.weekColumns(from: days)
    }()
}

private extension ContributionGraphDay {
    init(date: Date, count: Int, score _: Double) {
        self.date = date
        self.count = count
    }
}

private extension Calendar {
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
