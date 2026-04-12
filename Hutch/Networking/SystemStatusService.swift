import Foundation

struct SystemStatusService: Sendable {
    nonisolated static let statusURL = URL(string: "https://status.sr.ht/")!
    nonisolated static let feedURL = URL(string: "https://status.sr.ht/index.xml")!

    private let session: URLSession
    private let now: @Sendable () -> Date

    nonisolated init(session: URLSession = .shared, now: @escaping @Sendable () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    func fetchSnapshot() async throws -> SystemStatusSnapshot {
        let html = try await fetchSnapshotHTML()
        return try Self.parseSnapshotHTML(html, fetchedAt: now())
    }

    func fetchIncidentFeed() async throws -> [StatusIncident] {
        let data = try await fetchIncidentFeedData()
        return try await Self.parseIncidentFeedXML(data)
    }

    func fetchSnapshotHTML() async throws -> String {
        try await fetchText(from: Self.statusURL, accept: "text/html,application/xhtml+xml")
    }

    func fetchIncidentFeedData() async throws -> Data {
        try await fetchData(from: Self.feedURL, accept: "application/rss+xml,application/xml,text/xml")
    }

    private func fetchText(from url: URL, accept: String) async throws -> String {
        let data = try await fetchData(from: url, accept: accept)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SRHTError.decodingError(
                DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Response is not UTF-8 text"))
            )
        }
        return text
    }

    private func fetchData(from url: URL, accept: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SRHTError.networkError(error)
        }

        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw SRHTError.httpError(http.statusCode)
        }

        return data
    }

    private var userAgent: String {
        let bundle = Bundle.main
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Hutch"
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
        return "\(name)/\(version) (System Status)"
    }
}

extension SystemStatusService: SystemStatusServing {}

extension SystemStatusService {
    nonisolated static func parseSnapshotHTML(_ html: String, fetchedAt: Date) throws -> SystemStatusSnapshot {
        let services = parseServices(in: html)
        let incidents = parseHTMLIncidentCards(in: html)
        let summaries = parseActiveIncidentSummaries(in: html)

        let activeIncidents = incidents
            .filter { $0.isActive == true }
            .map { incident in
                let summary = incident.url.flatMap { summaries[$0.absoluteString] } ?? incident.summary
                return StatusIncident(
                    id: incident.id,
                    title: incident.title,
                    summary: summary,
                    url: incident.url,
                    publishedAt: incident.publishedAt,
                    updatedAt: incident.updatedAt,
                    isActive: incident.isActive
                )
            }

        return SystemStatusSnapshot(services: services, activeIncidents: activeIncidents, lastUpdated: fetchedAt)
    }

    nonisolated static func parseIncidentFeedXML(_ data: Data) async throws -> [StatusIncident] {
        try await MainActor.run {
            let parser = SystemStatusFeedParser()
            return try parser.parse(data: data)
        }
    }

    nonisolated private static func parseServices(in html: String) -> [StatusServiceState] {
        firstMatches(
            in: html,
            pattern: #"<div\b(?=[^>]*\bclass\s*=\s*["'][^"']*\bcomponent\b[^"']*["'])(?=[^>]*\bdata-status\s*=\s*["']([^"']+)["'])[^>]*>([\s\S]*?)</div>"#
        ).compactMap { captures in
            guard captures.count >= 2 else { return nil }

            let rawStatus = captures[0]
            let content = captures[1]
            guard let linkCaptures = firstMatches(
                in: content,
                pattern: #"<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#
            ).first,
                  linkCaptures.count >= 2 else {
                return nil
            }

            let href = linkCaptures[0]
            let cleanedName = cleanText(linkCaptures[1])
            let readableStatus = firstMatch(
                in: content,
                pattern: #"<(?:span|small|div)\b(?=[^>]*\bclass\s*=\s*["'][^"']*\bcomponent-status\b[^"']*["'])[^>]*>([\s\S]*?)</(?:span|small|div)>"#
            ).map(cleanText) ?? firstStatusLabel(in: content) ?? ""
            let level = statusLevel(fromHTMLStatus: rawStatus)

            return StatusServiceState(
                id: normalizedSlug(from: href, fallback: cleanedName) ?? cleanedName,
                name: cleanedName,
                slug: normalizedSlug(from: href, fallback: cleanedName),
                status: level == .unknown ? statusLevel(fromLabel: readableStatus) : level,
                description: nil
            )
        }
    }

    nonisolated private static func parseHTMLIncidentCards(in html: String) -> [StatusIncident] {
        firstMatches(
            in: html,
            pattern: #"<a\b(?=[^>]*\bclass\s*=\s*["'][^"']*\bissue\b[^"']*["'])(?=[^>]*\bhref\s*=\s*["']([^"']+)["'])[^>]*>([\s\S]*?)</a>"#
        ).compactMap { captures in
            guard captures.count >= 2 else { return nil }
            let href = captures[0]
            let content = captures[1]
            guard let titleHTML = firstMatch(in: content, pattern: #"<h[1-6][^>]*>\s*([\s\S]*?)\s*</h[1-6]>"#)
                    ?? firstMatch(in: content, pattern: #"<strong[^>]*>\s*([\s\S]*?)\s*</strong>"#)
                    ?? firstMatch(in: content, pattern: #"<span[^>]*>\s*([\s\S]*?)\s*</span>"#),
                  let publishedAt = publishedIncidentDate(in: content) else {
                return nil
            }

            let url = URL(string: href, relativeTo: statusURL)?.absoluteURL
            return StatusIncident(
                id: url?.absoluteString ?? cleanText(titleHTML),
                title: cleanText(titleHTML),
                summary: nil,
                url: url,
                publishedAt: publishedAt,
                updatedAt: nil,
                isActive: isActiveIncidentCard(content)
            )
        }
    }

    nonisolated private static func parseActiveIncidentSummaries(in html: String) -> [String: String] {
        firstMatches(
            in: html,
            pattern: #"<div\b(?=[^>]*\bclass\s*=\s*["'][^"']*\bannouncement-box\b[^"']*["'])[^>]*>([\s\S]*?)</div>\s*(?:<hr\b[^>]*\bannouncement-box\b[^>]*>)?"#
        ).reduce(into: [:]) { partialResult, captures in
            guard let content = captures.first,
                  let titleLinkCaptures = firstMatches(
                    in: content,
                    pattern: #"<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#
                  ).first,
                  let href = titleLinkCaptures.first else {
                return
            }

            let paragraphs = firstMatches(in: content, pattern: #"<p>([\s\S]*?)</p>"#)
                .compactMap(\.first)
                .map(cleanText)
                .filter { !$0.isEmpty }

            let summary = paragraphs.dropFirst(2).first ?? paragraphs.dropFirst().first
            guard let summary, !summary.isEmpty else { return }
            if let url = URL(string: href, relativeTo: statusURL)?.absoluteURL {
                partialResult[url.absoluteString] = summary
            }
        }
    }

    nonisolated private static func statusLevel(fromHTMLStatus status: String) -> StatusLevel {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ok":
            .operational
        case "disrupted":
            .degraded
        case "down":
            .majorOutage
        case "notice":
            .maintenance
        default:
            .unknown
        }
    }

    nonisolated private static func statusLevel(fromLabel label: String) -> StatusLevel {
        let normalizedLabel = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return switch normalizedLabel {
        case "operational", "all systems operational":
            StatusLevel.operational
        case "disrupted", "degraded", "partial outage":
            StatusLevel.degraded
        case "down", "major outage", "outage":
            StatusLevel.majorOutage
        case "maintenance", "scheduled maintenance", "under maintenance":
            StatusLevel.maintenance
        default:
            StatusLevel.unknown
        }
    }

    nonisolated private static func normalizedSlug(from href: String, fallback name: String) -> String? {
        if href.contains("/affected/") {
            let trimmed = href.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let slug = trimmed.split(separator: "/").last {
                return String(slug)
            }
        }
        return name.isEmpty ? nil : name
    }

    nonisolated private static func firstMatch(in text: String, pattern: String) -> String? {
        firstMatches(in: text, pattern: pattern).first?.first
    }

    nonisolated private static func firstMatches(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { captureIndex in
                guard let captureRange = Range(match.range(at: captureIndex), in: text) else { return nil }
                return String(text[captureRange])
            }
        }
    }

    nonisolated private static func cleanText(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let decoded = decodeHTMLEntities(stripped)
        return decoded
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([.,!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "→", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func firstStatusLabel(in text: String) -> String? {
        cleanText(text)
            .split(separator: "•")
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { statusLevel(fromLabel: $0) != .unknown })
    }

    nonisolated private static func publishedIncidentDate(in content: String) -> Date? {
        if let timeValue = firstMatch(in: content, pattern: #"<time\b[^>]*\bdatetime\s*=\s*["']([^"']+)["'][^>]*>"#),
           let parsed = parseISO8601Date(cleanText(timeValue)) {
            return parsed
        }

        if let titleAttribute = firstMatch(
            in: content,
            pattern: #"<(?:small|time)\b(?=[^>]*\bclass\s*=\s*["'][^"']*\bdate\b[^"']*["'])[^>]*\btitle\s*=\s*["']([^"']+)["'][^>]*>"#
        ) ?? firstMatch(in: content, pattern: #"\btitle\s*=\s*["']([^"']+UTC)["']"#) {
            return htmlIssueDateFormatter.date(from: cleanText(titleAttribute))
        }

        return nil
    }

    nonisolated private static func isActiveIncidentCard(_ content: String) -> Bool {
        let normalizedContent = cleanText(content).lowercased()
        return normalizedContent.contains("not resolved yet")
            || normalizedContent.contains("ongoing")
            || normalizedContent.contains("investigating")
    }

    nonisolated fileprivate static func parseISO8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? {
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]
            return fallbackFormatter.date(from: value)
        }()
    }

    nonisolated private static let htmlIssueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "MMM d HH:mm:ss yyyy zzz"
        return formatter
    }()

}

private final class SystemStatusFeedParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var incidents: [StatusIncident] = []
    private var currentItem: FeedItem?
    private var textBuffer = ""

    func parse(data: Data) throws -> [StatusIncident] {
        incidents = []
        currentItem = nil
        textBuffer = ""

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? SRHTError.decodingError(
                DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Failed to parse status feed"))
            )
        }
        return incidents.sorted { $0.publishedAt > $1.publishedAt }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        textBuffer = ""
        if elementName == "item" {
            currentItem = FeedItem()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            textBuffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard var currentItem else {
            textBuffer = ""
            return
        }

        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "title":
            currentItem.title = value
        case "link":
            currentItem.link = value
        case "guid":
            currentItem.guid = value
        case "description":
            currentItem.description = value
        case "pubDate", "dc:date":
            currentItem.pubDate = value
        case "category":
            currentItem.category = value
        case "item":
            if let incident = currentItem.makeIncident() {
                incidents.append(incident)
            }
            self.currentItem = nil
        default:
            self.currentItem = currentItem
        }

        if elementName != "item" {
            self.currentItem = currentItem
        }
        textBuffer = ""
    }

    private struct FeedItem {
        var title = ""
        var link = ""
        var guid = ""
        var description = ""
        var pubDate = ""
        var category = ""

        func makeIncident() -> StatusIncident? {
            let cleanedTitle = title.replacingOccurrences(of: "[Resolved] ", with: "")
            guard !cleanedTitle.isEmpty,
                  let publishedAt = SystemStatusFeedParser.parsePubDate(pubDate) else {
                return nil
            }

            let url = URL(string: link)
            let updatedAt = category.isEmpty ? nil : SystemStatusFeedParser.updatedDateFormatter.date(from: category)

            return StatusIncident(
                id: guid.isEmpty ? (url?.absoluteString ?? cleanedTitle) : guid,
                title: cleanedTitle,
                summary: SystemStatusFeedParser.summary(from: description),
                url: url,
                publishedAt: publishedAt,
                updatedAt: updatedAt,
                isActive: category.isEmpty
            )
        }
    }

    nonisolated private static func summary(from html: String) -> String? {
        html
            .components(separatedBy: "</p>")
            .map { $0.replacingOccurrences(of: "<p>", with: "") }
            .map(stripHTML)
            .map {
                $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+([.,!?;:])"#, with: "$1", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first { !$0.isEmpty }
    }

    nonisolated private static func stripHTML(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return decodeHTMLEntities(stripped)
    }

    nonisolated private static func parsePubDate(_ value: String) -> Date? {
        pubDateFormatter.date(from: value) ?? SystemStatusService.parseISO8601Date(value)
    }

    nonisolated private static let pubDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    nonisolated private static let updatedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
