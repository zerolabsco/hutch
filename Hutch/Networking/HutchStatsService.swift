import Foundation

protocol ContributionCalendarServing: Sendable {
    func fetchContributionCalendar(actor: String, endingOn endDate: Date) async throws -> ContributionCalendarResponse
    func fetchContributionStats(actor: String, endingOn endDate: Date) async throws -> ContributionStatsResponse
}

struct HutchStatsService: ContributionCalendarServing {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        configuration: AppConfiguration
    ) {
        self.session = session
        self.baseURL = configuration.hutchStatsBaseURL
        self.decoder = JSONDecoder()
    }

    func fetchContributionCalendar(actor: String, endingOn endDate: Date) async throws -> ContributionCalendarResponse {
        debugLog("calendar request actor=\(actor) endDate=\(Self.rangeFormatter.string(from: endDate))")
        return try await fetch(
            path: "api/contributions/\(actor)",
            queryItems: trailingYearQueryItems(endingOn: endDate),
            responseType: ContributionCalendarResponse.self
        )
    }

    func fetchContributionStats(actor: String, endingOn endDate: Date) async throws -> ContributionStatsResponse {
        debugLog("stats request actor=\(actor) endDate=\(Self.rangeFormatter.string(from: endDate))")
        return try await fetch(
            path: "api/contributions/\(actor)/stats",
            queryItems: trailingYearQueryItems(endingOn: endDate),
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

        debugLog("request \(url.absoluteString)")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            debugLog("network failure \(url.absoluteString) error=\(error.localizedDescription)")
            throw SRHTError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse {
            debugLog("response \(url.absoluteString) status=\(httpResponse.statusCode) bytes=\(data.count)")
            if !(200...299).contains(httpResponse.statusCode) {
                throw SRHTError.httpError(httpResponse.statusCode)
            }
        }

        do {
            return try decoder.decode(responseType, from: data)
        } catch {
            let preview = String(decoding: data.prefix(300), as: UTF8.self)
            debugLog("decode failure \(url.absoluteString) error=\(error.localizedDescription) body=\(preview)")
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

    private func trailingYearQueryItems(endingOn endDate: Date) -> [URLQueryItem] {
        let range = trailingRange(endingOn: endDate)
        let start = Self.rangeFormatter.string(from: range.lowerBound)
        let end = Self.rangeFormatter.string(from: range.upperBound)

        return [
            URLQueryItem(name: "from", value: start),
            URLQueryItem(name: "to", value: end)
        ]
    }

    private static let rangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .contributionCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func debugLog(_ message: String) {
#if DEBUG
        print("[HutchStatsService] \(message)")
#endif
    }
}
