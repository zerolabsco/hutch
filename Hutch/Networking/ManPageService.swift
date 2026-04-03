import Foundation

/// Fetches and parses man.sr.ht wiki pages over plain HTTP (no auth required).
struct ManPage: Sendable {
    let url: URL
    let title: String
    let contentHTML: String
}

struct ManPageService {
    static let baseURL = URL(string: "https://man.sr.ht")!
    static let pagesBaseURL = URL(string: "https://srht.site/")!

    /// Fetches a man.sr.ht page and extracts the article content.
    /// Uses an unauthenticated URLSession because man.sr.ht pages are public.
    static func fetch(url: URL) async throws -> ManPage {
        guard isTrustedDocumentationURL(url) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        return ManPage(
            url: url,
            title: extractTitle(from: html, fallbackURL: url),
            contentHTML: sanitizeContentHTML(extractContent(from: html))
        )
    }

    static func isTrustedDocumentationURL(_ url: URL) -> Bool {
        guard url.scheme?.localizedCaseInsensitiveCompare("https") == .orderedSame,
              let host = url.host?.lowercased() else {
            return false
        }

        return host == "man.sr.ht"
            || host.hasSuffix(".man.sr.ht")
            || host == "srht.site"
    }

    private static func extractTitle(from html: String, fallbackURL: URL) -> String {
        if let headerHTML = substring(
            in: html,
            startingAtFirstOccurrenceOf: #"<div class="header-tabbed">"#
        ),
           let h2Contents = firstMatch(in: headerHTML, pattern: #"<h2\b[^>]*>(.*?)</h2>"#) {
            let title = stripHTML(from: h2Contents).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return title
            }
        }

        if let titleContents = firstMatch(in: html, pattern: #"<title\b[^>]*>(.*?)</title>"#) {
            let rawTitle = stripHTML(from: titleContents).trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = " - man.sr.ht"
            let normalizedTitle: String
            if rawTitle.hasSuffix(suffix) {
                normalizedTitle = String(rawTitle.dropLast(suffix.count))
            } else {
                normalizedTitle = rawTitle
            }

            if !normalizedTitle.isEmpty {
                return normalizedTitle
            }
        }

        let lastComponent = fallbackURL.pathComponents.last { $0 != "/" } ?? ""
        return lastComponent.isEmpty ? fallbackURL.absoluteString : lastComponent
    }

    private static func extractContent(from html: String) -> String {
        if let content = extractDivBlock(from: html, className: "markdown"), !content.isEmpty {
            return content
        }

        if let content = extractArticleBlock(from: html, className: "content"), !content.isEmpty {
            return content
        }

        if let content = extractDivBlock(from: html, className: "content"), !content.isEmpty {
            return content
        }

        return ""
    }

    private static func sanitizeContentHTML(_ html: String) -> String {
        html.replacingOccurrences(
            of: ###"<a\b[^>]*aria-hidden="true"[^>]*href="#[^"]*"[^>]*>\s*#\s*</a>"###,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func extractArticleBlock(from html: String, className: String) -> String? {
        extractElementBlock(from: html, elementName: "article", className: className)
    }

    private static func extractDivBlock(from html: String, className: String) -> String? {
        extractElementBlock(from: html, elementName: "div", className: className)
    }

    private static func extractElementBlock(
        from html: String,
        elementName: String,
        className: String
    ) -> String? {
        guard let startRange = html.range(of: #"<\#(elementName) class="\#(className)""#) else {
            return nil
        }

        let characters = Array(html)
        var index = html.distance(from: html.startIndex, to: startRange.lowerBound)
        var depth = 0
        var foundOpeningDiv = false

        while index < characters.count {
            guard characters[index] == "<" else {
                index += 1
                continue
            }

            if hasPrefix("</\(elementName)", at: index, in: characters) {
                if foundOpeningDiv {
                    depth -= 1
                    if depth == 0 {
                        let closeEnd = endOfTag(startingAt: index, in: characters)
                        return String(characters[html.distance(from: html.startIndex, to: startRange.lowerBound)..<closeEnd])
                    }
                }
                index += 1
                continue
            }

            if hasPrefix("<\(elementName)", at: index, in: characters) {
                if !isSelfClosingTag(startingAt: index, in: characters) {
                    depth += 1
                    foundOpeningDiv = true
                }
                index += 1
                continue
            }

            index += 1
        }

        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[captureRange])
    }

    private static func substring(in text: String, startingAtFirstOccurrenceOf needle: String) -> String? {
        guard let range = text.range(of: needle) else {
            return nil
        }

        return String(text[range.lowerBound...])
    }

    private static func stripHTML(from text: String) -> String {
        let noTags = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )

        return decodeHTMLEntities(noTags)
    }

    private static func hasPrefix(_ prefix: String, at index: Int, in characters: [Character]) -> Bool {
        guard index + prefix.count <= characters.count else { return false }
        return String(characters[index..<(index + prefix.count)]).lowercased() == prefix
    }

    private static func isSelfClosingTag(startingAt index: Int, in characters: [Character]) -> Bool {
        let tagEnd = endOfTag(startingAt: index, in: characters)
        guard tagEnd > index else { return false }
        let tagContents = String(characters[index..<tagEnd])
        return tagContents.contains("/>")
    }

    private static func endOfTag(startingAt index: Int, in characters: [Character]) -> Int {
        var current = index
        while current < characters.count {
            if characters[current] == ">" {
                return current + 1
            }
            current += 1
        }
        return characters.count
    }
}
