import Foundation

protocol ContributionCalendarServing: Sendable {
    func fetchContributionCalendar(actor: String, endingOn endDate: Date) async throws -> ContributionCalendarResponse
    func fetchContributionStats(actor: String, endingOn endDate: Date) async throws -> ContributionStatsResponse
}

struct HutchStatsService: ContributionCalendarServing {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let baseURL: URL
    private let currentActor: String?

    init(
        session: URLSession = .shared,
        configuration: AppConfiguration,
        currentActor: String? = nil
    ) {
        self.session = session
        self.baseURL = configuration.hutchStatsBaseURL
        self.decoder = JSONDecoder()
        self.currentActor = currentActor
    }

    func fetchContributionCalendar(actor: String, endingOn endDate: Date) async throws -> ContributionCalendarResponse {
        return try await fetch(
            path: "api/contributions/\(actor)",
            queryItems: contributionQueryItems(actor: actor, endingOn: endDate),
            responseType: ContributionCalendarResponse.self
        )
    }

    func fetchContributionStats(actor: String, endingOn endDate: Date) async throws -> ContributionStatsResponse {
        return try await fetch(
            path: "api/contributions/\(actor)/stats",
            queryItems: contributionQueryItems(actor: actor, endingOn: endDate),
            responseType: ContributionStatsResponse.self
        )
    }

    private func fetch<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        responseType: Response.Type
    ) async throws -> Response {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        components.path = normalizedPath(basePath: components.path, appendedPath: path)
        components.queryItems = queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw SRHTError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse {
            if !(200...299).contains(httpResponse.statusCode) {
                throw SRHTError.httpError(httpResponse.statusCode)
            }
        }

        do {
            return try decoder.decode(responseType, from: data)
        } catch {
            throw SRHTError.decodingError(error)
        }
    }

    private func normalizedPath(basePath: String, appendedPath: String) -> String {
        let trimmedBase = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedAppendix = appendedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let pathComponents = [trimmedBase, trimmedAppendix].filter { !$0.isEmpty }
        return "/" + pathComponents.joined(separator: "/")
    }

    func trailingRange(endingOn endDate: Date) -> ClosedRange<Date> {
        let normalizedEndDate = Calendar.contributionCalendar.startOfDay(for: endDate)
        let oneYearBack = Calendar.contributionCalendar.date(byAdding: .year, value: -1, to: normalizedEndDate) ?? normalizedEndDate
        let normalizedStartDate = Calendar.contributionCalendar.date(byAdding: .day, value: 1, to: oneYearBack) ?? oneYearBack
        return normalizedStartDate...normalizedEndDate
    }

    func contributionQueryItems(actor: String, endingOn endDate: Date) -> [URLQueryItem] {
        let range = trailingRange(endingOn: endDate)
        let start = Self.rangeFormatter.string(from: range.lowerBound)
        let end = Self.rangeFormatter.string(from: range.upperBound)

        var queryItems = [
            URLQueryItem(name: "from", value: start),
            URLQueryItem(name: "to", value: end)
        ]

        if actor == currentActor {
            queryItems.append(URLQueryItem(name: "prioritize", value: "self"))
        }

        return queryItems
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
