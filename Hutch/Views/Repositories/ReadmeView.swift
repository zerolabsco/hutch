import SwiftUI
import WebKit

struct ReadmeView: View {
    let viewModel: RepositoryDetailViewModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var isShowingRepositoryDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                metadataSection
                repositoryDetailsSection
                latestChangeSection
                readmeSection
            }
            .padding()
        }
        .task {
            async let readme: () = viewModel.loadReadme()
            async let commits: () = viewModel.loadCommits()
            async let refs: () = viewModel.loadReferences()
            _ = await (readme, commits, refs)
        }
        .navigationDestination(for: CommitSummary.self) { commit in
            CommitDetailView(
                commitSummary: commit,
                repository: viewModel.repository
            )
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.repository.owner.canonicalName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(viewModel.repository.name)
                .font(.largeTitle.weight(.semibold))
            if let description = viewModel.repository.description, !description.isEmpty {
                Text(description)
                    .font(.body)
            }
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SummaryMetadataRow(
                icon: "arrow.triangle.branch",
                title: viewModel.repository.head?.name ?? repositoryVisibilityLabel(viewModel.repository.visibility)
            )

            if let readmePath = viewModel.readmePath {
                SummaryMetadataRow(
                    icon: "doc.text",
                    title: readmePath
                )
            }
        }
    }

    private var repositoryDetailsSection: some View {
        DisclosureGroup(isExpanded: $isShowingRepositoryDetails) {
            VStack(alignment: .leading, spacing: 12) {
                SummaryDetailRow(label: "Visibility", value: repositoryVisibilityLabel(viewModel.repository.visibility))
                SummaryDetailRow(label: "Read-only", value: repositoryCloneURLs(for: viewModel.repository).readOnly, monospace: true)
                SummaryDetailRow(label: "Read/write", value: repositoryCloneURLs(for: viewModel.repository).readWrite, monospace: true)
                SummaryDetailRow(label: "RID", value: viewModel.repository.rid, monospace: true)
            }
            .padding(.top, 8)
        } label: {
            Text("Repository Details")
                .font(.subheadline.weight(.medium))
        }
    }

    @ViewBuilder
    private var latestChangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isLoadingCommits && viewModel.commits.isEmpty {
                SRHTLoadingStateView(message: "Loading latest change…")
                    .frame(maxWidth: .infinity)
            } else if let commit = viewModel.commits.first {
                NavigationLink(value: commit) {
                    SummaryMetadataRow(
                        icon: "arrow.trianglehead.clockwise",
                        title: commit.title,
                        subtitle: "\(commit.shortId) — \(commit.author.name) \(commit.author.time.relativeDescription)"
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if let error = viewModel.error, viewModel.commits.isEmpty {
                SRHTErrorStateView(
                    title: "Couldn't Load Latest Change",
                    message: error,
                    retryAction: { await viewModel.loadCommits() }
                )
            } else {
                ContentUnavailableView(
                    "No Recent Commits",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("This repository does not have any commit history yet.")
                )
            }
        }
    }

    @ViewBuilder
    private var readmeSection: some View {
        if viewModel.isLoadingReadme {
            SRHTLoadingStateView(message: "Loading README…")
        } else if let content = viewModel.readmeContent {
            RenderedMarkupContentView(
                content: sharedReadmeContent(from: content),
                readmePath: viewModel.readmePath,
                colorScheme: colorScheme,
                ownerCanonicalName: viewModel.repository.owner.canonicalName,
                repositoryName: viewModel.repository.name
            )
        } else if let error = viewModel.error, !viewModel.readmeLoaded {
            SRHTErrorStateView(
                title: "Couldn't Load README",
                message: error,
                retryAction: { await viewModel.loadReadme() }
            )
        } else {
            ContentUnavailableView(
                "No README",
                systemImage: "doc.text",
                description: Text("This repository does not have a README file.")
            )
        }
    }

    private func sharedReadmeContent(from content: RepositoryDetailViewModel.ReadmeContent) -> RenderedMarkupContent {
        switch content {
        case .html(let html):
            .html(html)
        case .markdown(let text):
            .markdown(text)
        case .org(let text):
            .org(text)
        case .plainText(let text):
            .plainText(text)
        }
    }
}

enum RenderedMarkupContent: Sendable {
    case html(String)
    case markdown(String)
    case org(String)
    case plainText(String)
}

struct RenderedMarkupContentView: View {
    let content: RenderedMarkupContent
    let readmePath: String?
    let colorScheme: ColorScheme
    let ownerCanonicalName: String
    let repositoryName: String
    var repositoryHost = "git.sr.ht"

    @State private var renderedHTML: String?

    private var cacheKey: String {
        switch content {
        case .html(let html):
            "html:\(readmePath ?? "custom"):\(html)"
        case .markdown(let text):
            "markdown:\(readmePath ?? ""):\(text)"
        case .org(let text):
            "org:\(readmePath ?? ""):\(text)"
        case .plainText(let text):
            "plain:\(readmePath ?? ""):\(text)"
        }
    }

    var body: some View {
        Group {
            switch content {
            case .html(let html):
                HTMLWebView(html: html, colorScheme: colorScheme)
            case .markdown, .org:
                if let renderedHTML {
                    HTMLWebView(html: renderedHTML, colorScheme: colorScheme)
                } else {
                    SRHTLoadingStateView(message: "Preparing README…")
                }
            case .plainText(let text):
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: cacheKey) {
            await prepareHTMLIfNeeded()
        }
    }

    private func prepareHTMLIfNeeded() async {
        switch content {
        case .html, .plainText:
            renderedHTML = nil
        case .markdown(let text):
            if let cached = RenderedReadmeHTMLCache.shared.html(forKey: cacheKey) {
                renderedHTML = cached
                return
            }
            let html = await Task.detached(priority: .userInitiated) {
                markdownToHTML(text) { source in
                    resolveRepositoryAssetURL(
                        source,
                        owner: ownerCanonicalName,
                        repositoryName: repositoryName,
                        readmePath: readmePath
                    )?
                    .replacingOccurrences(of: "git.sr.ht", with: repositoryHost)
                }
            }.value
            RenderedReadmeHTMLCache.shared.setHTML(html, forKey: cacheKey)
            guard !Task.isCancelled else { return }
            renderedHTML = html
        case .org(let text):
            if let cached = RenderedReadmeHTMLCache.shared.html(forKey: cacheKey) {
                renderedHTML = cached
                return
            }
            let html = await Task.detached(priority: .userInitiated) {
                orgToHTML(text) { source in
                    resolveRepositoryAssetURL(
                        source,
                        owner: ownerCanonicalName,
                        repositoryName: repositoryName,
                        readmePath: readmePath
                    )?
                    .replacingOccurrences(of: "git.sr.ht", with: repositoryHost)
                }
            }.value
            RenderedReadmeHTMLCache.shared.setHTML(html, forKey: cacheKey)
            guard !Task.isCancelled else { return }
            renderedHTML = html
        }
    }
}

private final class RenderedReadmeHTMLCache: @unchecked Sendable {
    static let shared = RenderedReadmeHTMLCache()

    private let storage = NSCache<NSString, NSString>()

    func html(forKey key: String) -> String? {
        storage.object(forKey: key as NSString) as String?
    }

    func setHTML(_ html: String, forKey key: String) {
        storage.setObject(html as NSString, forKey: key as NSString)
    }

    func removeAll() {
        storage.removeAllObjects()
    }
}

@MainActor
func clearWebContentRenderCaches() {
    RenderedReadmeHTMLCache.shared.removeAll()
    HTMLWebViewCoordinator.heightCache.removeAllObjects()
}

// MARK: - Markdown to HTML

nonisolated func markdownToHTML(_ text: String, imageURLResolver: ((String) -> String?)? = nil) -> String {
    let normalizedText = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalizedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var html = ""
    var inCodeBlock = false
    var inList = false
    var paragraph: [String] = []

    func flushParagraph() {
        if !paragraph.isEmpty {
            let normalizedParagraph = paragraph
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
            html += "<p>" + normalizedParagraph + "</p>\n"
            paragraph = []
        }
    }

    func closeList() {
        if inList {
            html += "</ul>\n"
            inList = false
        }
    }

    for line in lines {
        // Fenced code blocks
        if line.hasPrefix("```") {
            if inCodeBlock {
                html += "</code></pre>\n"
                inCodeBlock = false
            } else {
                flushParagraph()
                closeList()
                html += "<pre><code>"
                inCodeBlock = true
            }
            continue
        }

        if inCodeBlock {
            html += escapeHTML(line) + "\n"
            continue
        }

        // Headings
        if line.hasPrefix("### ") {
            flushParagraph()
            closeList()
            html += "<h3>" + processInline(String(line.dropFirst(4)), imageURLResolver: imageURLResolver) + "</h3>\n"
            continue
        }
        if line.hasPrefix("## ") {
            flushParagraph()
            closeList()
            html += "<h2>" + processInline(String(line.dropFirst(3)), imageURLResolver: imageURLResolver) + "</h2>\n"
            continue
        }
        if line.hasPrefix("# ") {
            flushParagraph()
            closeList()
            html += "<h1>" + processInline(String(line.dropFirst(2)), imageURLResolver: imageURLResolver) + "</h1>\n"
            continue
        }

        // List items
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            flushParagraph()
            if !inList {
                html += "<ul>\n"
                inList = true
            }
            html += "<li>" + renderTaskListItem(
                String(trimmed.dropFirst(2)),
                inlineRenderer: { processInline($0, imageURLResolver: imageURLResolver) }
            ) + "</li>\n"
            continue
        }

        // Blank line
        if trimmed.isEmpty {
            flushParagraph()
            closeList()
            continue
        }

        // Regular text — accumulate into paragraph
        paragraph.append(processInline(line, imageURLResolver: imageURLResolver))
    }

    // Flush remaining state
    if inCodeBlock {
        html += "</code></pre>\n"
    }
    flushParagraph()
    closeList()

    return html
}

nonisolated func processInline(_ text: String, imageURLResolver: ((String) -> String?)? = nil) -> String {
    var result = escapeHTML(text)

    // Images: ![alt](url)
    result = replaceMatches(in: result, pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) { match, nsText in
        let alt = nsText.substring(with: match.range(at: 1))
        let source = nsText.substring(with: match.range(at: 2))
        let resolvedSource = imageURLResolver?(source) ?? source
        guard let sanitizedSource = sanitizedReadmeImageURLString(resolvedSource) else {
            return escapeHTML(alt)
        }
        return #"<img src="\#(sanitizedSource)" alt="\#(escapeHTMLAttribute(alt))">"#
    }
    // Links: [text](url)
    result = replaceMatches(in: result, pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) { match, nsText in
        let label = nsText.substring(with: match.range(at: 1))
        let rawURL = nsText.substring(with: match.range(at: 2))
        guard let sanitizedURL = sanitizedReadmeLinkURLString(rawURL) else {
            return label
        }
        return #"<a href="\#(sanitizedURL)">\#(label)</a>"#
    }
    // Bold: **text**
    result = result.replacingOccurrences(
        of: #"\*\*(.+?)\*\*"#,
        with: "<strong>$1</strong>",
        options: .regularExpression
    )
    // Italic: *text*
    result = result.replacingOccurrences(
        of: #"\*(.+?)\*"#,
        with: "<em>$1</em>",
        options: .regularExpression
    )
    // Inline code: `text`
    result = result.replacingOccurrences(
        of: #"`([^`]+)`"#,
        with: "<code>$1</code>",
        options: .regularExpression
    )

    return result
}

// MARK: - Org-mode to HTML

nonisolated func orgToHTML(_ text: String, imageURLResolver: ((String) -> String?)? = nil) -> String {
    let normalizedText = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalizedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var html = ""
    var listType: OrgListType?
    var inQuoteBlock = false
    var inPropertyDrawer = false
    var srcLanguage: String?
    var paragraph: [String] = []
    var tableRows: [[String]] = []
    var propertyRows: [(String, String)] = []

    func flushParagraph() {
        if !paragraph.isEmpty {
            let normalizedParagraph = paragraph
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
            html += "<p>" + processOrgInline(normalizedParagraph, imageURLResolver: imageURLResolver) + "</p>\n"
            paragraph = []
        }
    }

    func closeList() {
        switch listType {
        case .unordered:
            html += "</ul>\n"
        case .ordered:
            html += "</ol>\n"
        case nil:
            break
        }
        listType = nil
    }

    func flushTable() {
        guard !tableRows.isEmpty else { return }
        let hasHeaderSeparator = tableRows.count > 1 && tableRows[1].allSatisfy(isOrgTableSeparatorCell)
        let headerRow = tableRows.first ?? []
        let bodyRows: [[String]]

        html += "<table>\n"
        if hasHeaderSeparator {
            html += "<thead><tr>"
            for cell in headerRow {
                html += "<th>" + processOrgInline(cell, imageURLResolver: imageURLResolver) + "</th>"
            }
            html += "</tr></thead>\n<tbody>\n"
            bodyRows = Array(tableRows.dropFirst(2))
        } else {
            bodyRows = tableRows
        }

        for row in bodyRows {
            html += "<tr>"
            for cell in row {
                html += "<td>" + processOrgInline(cell, imageURLResolver: imageURLResolver) + "</td>"
            }
            html += "</tr>\n"
        }

        if hasHeaderSeparator {
            html += "</tbody>\n"
        }
        html += "</table>\n"
        tableRows = []
    }

    func flushPropertyDrawer() {
        guard !propertyRows.isEmpty else { return }
        html += "<dl class=\"org-properties\">\n"
        for (key, value) in propertyRows {
            html += "<dt>" + escapeHTML(key) + "</dt>"
            html += "<dd>" + processOrgInline(value, imageURLResolver: imageURLResolver) + "</dd>\n"
        }
        html += "</dl>\n"
        propertyRows = []
    }

    func closeQuoteBlock() {
        if inQuoteBlock {
            flushParagraph()
            html += "</blockquote>\n"
            inQuoteBlock = false
        }
    }

    func closeSourceBlock() {
        if srcLanguage != nil {
            html += "</code></pre>\n"
            srcLanguage = nil
        }
    }

    func flushBlockState() {
        flushParagraph()
        closeList()
        flushTable()
        flushPropertyDrawer()
    }

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if srcLanguage != nil {
            if trimmed.lowercased() == "#+end_src" {
                closeSourceBlock()
            } else {
                html += escapeHTML(line) + "\n"
            }
            continue
        }

        if inQuoteBlock, trimmed.lowercased() == "#+end_quote" {
            closeQuoteBlock()
            continue
        }

        if trimmed.lowercased().hasPrefix("#+begin_src") {
            closeQuoteBlock()
            flushBlockState()
            let language = trimmed
                .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                .dropFirst()
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let classAttribute = language.map { " class=\"language-\(escapeHTMLAttribute($0))\"" } ?? ""
            html += "<pre><code\(classAttribute)>"
            srcLanguage = language ?? ""
            continue
        }

        if trimmed.lowercased() == "#+begin_quote" {
            flushBlockState()
            html += "<blockquote>\n"
            inQuoteBlock = true
            continue
        }

        if trimmed == ":PROPERTIES:" {
            closeQuoteBlock()
            flushBlockState()
            inPropertyDrawer = true
            continue
        }

        if trimmed == ":END:", inPropertyDrawer {
            flushPropertyDrawer()
            inPropertyDrawer = false
            continue
        }

        if inPropertyDrawer,
           trimmed.hasPrefix(":"),
           let secondColonIndex = trimmed.dropFirst().firstIndex(of: ":") {
            let keyStart = trimmed.index(after: trimmed.startIndex)
            let key = String(trimmed[keyStart..<secondColonIndex]).trimmingCharacters(in: .whitespaces)
            let valueStart = trimmed.index(after: secondColonIndex)
            let value = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                propertyRows.append((key, value))
                continue
            }
        }

        if isOrgTableLine(trimmed) {
            closeQuoteBlock()
            flushParagraph()
            closeList()
            tableRows.append(parseOrgTableRow(trimmed))
            continue
        } else {
            flushTable()
        }

        // Org headings: * heading, ** heading, *** heading
        if let match = trimmed.firstMatch(of: /^(\*{1,3})\s+(.+)$/) {
            closeQuoteBlock()
            flushBlockState()
            let level = match.1.count
            let content = processOrgInline(String(match.2), imageURLResolver: imageURLResolver)
            html += "<h\(level)>" + content + "</h\(level)>\n"
            continue
        }

        // List items: - item
        if trimmed.hasPrefix("- ") {
            flushParagraph()
            flushPropertyDrawer()
            if listType != .unordered {
                closeList()
                html += "<ul>\n"
                listType = .unordered
            }
            html += "<li>" + renderTaskListItem(
                String(trimmed.dropFirst(2)),
                inlineRenderer: { processOrgInline($0, imageURLResolver: imageURLResolver) }
            ) + "</li>\n"
            continue
        }

        if let orderedItem = orderedListItem(in: trimmed) {
            flushParagraph()
            flushPropertyDrawer()
            if listType != .ordered {
                closeList()
                html += "<ol>\n"
                listType = .ordered
            }
            html += "<li>" + renderTaskListItem(
                orderedItem,
                inlineRenderer: { processOrgInline($0, imageURLResolver: imageURLResolver) }
            ) + "</li>\n"
            continue
        }

        // Blank line
        if trimmed.isEmpty {
            if inQuoteBlock {
                flushParagraph()
            } else {
                flushBlockState()
            }
            continue
        }

        // Regular text
        paragraph.append(line)
    }

    closeSourceBlock()
    closeQuoteBlock()
    flushBlockState()

    return html
}

nonisolated private func processOrgInline(_ text: String, imageURLResolver: ((String) -> String?)? = nil) -> String {
    var result = escapeHTML(text)
    var protectedFragments: [String: String] = [:]

    result = protectMatches(
        in: result,
        pattern: #"\[\[([^\]]+)\]\[([^\]]+)\]\]"#,
        protectedFragments: &protectedFragments
    ) { match, nsText in
        let url = nsText.substring(with: match.range(at: 1))
        let label = nsText.substring(with: match.range(at: 2))
        if let imageHTML = makeOrgImageHTML(
            source: url,
            alt: label,
            imageURLResolver: imageURLResolver
        ) {
            return imageHTML
        }
        guard let sanitizedURL = sanitizedReadmeLinkURLString(url) else {
            return label
        }
        return #"<a href="\#(sanitizedURL)">\#(label)</a>"#
    }
    result = protectMatches(
        in: result,
        pattern: #"\[\[([^\]]+)\]\]"#,
        protectedFragments: &protectedFragments
    ) { match, nsText in
        let url = nsText.substring(with: match.range(at: 1))
        if let imageHTML = makeOrgImageHTML(
            source: url,
            alt: nil,
            imageURLResolver: imageURLResolver
        ) {
            return imageHTML
        }
        guard let sanitizedURL = sanitizedReadmeLinkURLString(url) else {
            return url
        }
        return #"<a href="\#(sanitizedURL)">\#(url)</a>"#
    }
    result = protectMatches(
        in: result,
        pattern: #"(?<!\S)~(.+?)~(?=\s|$|[.,;:!?])|(?<!\S)=(.+?)=(?=\s|$|[.,;:!?])"#,
        protectedFragments: &protectedFragments
    ) { match, nsText in
        let tildeRange = match.range(at: 1)
        let equalsRange = match.range(at: 2)
        let codeText: String
        if tildeRange.location != NSNotFound {
            codeText = nsText.substring(with: tildeRange)
        } else {
            codeText = nsText.substring(with: equalsRange)
        }
        return "<code>\(codeText)</code>"
    }

    // Bold: *text*
    result = result.replacingOccurrences(
        of: #"(?<!\S)\*(.+?)\*(?=\s|$|[.,;:!?])"#,
        with: "<strong>$1</strong>",
        options: .regularExpression
    )
    // Italic: /text/
    result = result.replacingOccurrences(
        of: #"(?<!\S)/(.+?)/(?=\s|$|[.,;:!?])"#,
        with: "<em>$1</em>",
        options: .regularExpression
    )

    for (token, fragment) in protectedFragments {
        result = result.replacingOccurrences(of: token, with: fragment)
    }

    return result
}

// MARK: - HTML Escaping

nonisolated func escapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

nonisolated private func escapeHTMLAttribute(_ text: String) -> String {
    escapeHTML(text).replacingOccurrences(of: "'", with: "&#39;")
}

nonisolated func sanitizedReadmeLinkURLString(_ rawURL: String) -> String? {
    sanitizeReadmeURLString(
        rawURL,
        allowedSchemes: ["http", "https", "mailto"],
        allowsFragmentOnly: true
    )
}

nonisolated func sanitizedReadmeImageURLString(_ rawURL: String) -> String? {
    sanitizeReadmeURLString(
        rawURL,
        allowedSchemes: ["http", "https"],
        allowsFragmentOnly: false
    )
}

nonisolated func isAllowedReadmeNavigationURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else {
        return false
    }
    if scheme == "about" || scheme == "data" {
        return true
    }
    guard let sanitizedURL = sanitizedReadmeLinkURLString(url.absoluteString) else {
        return false
    }
    return sanitizedURL == escapeHTMLAttribute(url.absoluteString)
}

nonisolated private func sanitizeReadmeURLString(
    _ rawURL: String,
    allowedSchemes: Set<String>,
    allowsFragmentOnly: Bool
) -> String? {
    let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedURL.isEmpty else { return nil }

    if allowsFragmentOnly, trimmedURL.hasPrefix("#"), trimmedURL.count > 1 {
        return escapeHTMLAttribute(trimmedURL)
    }

    guard let components = URLComponents(string: trimmedURL),
          let scheme = components.scheme?.lowercased(),
          allowedSchemes.contains(scheme),
          let sanitizedURL = components.url?.absoluteString else {
        return nil
    }

    return escapeHTMLAttribute(sanitizedURL)
}

nonisolated private func isOrgTableLine(_ line: String) -> Bool {
    line.hasPrefix("|") && line.hasSuffix("|")
}

nonisolated private func parseOrgTableRow(_ line: String) -> [String] {
    line
        .split(separator: "|", omittingEmptySubsequences: false)
        .dropFirst()
        .dropLast()
        .map { String($0).trimmingCharacters(in: .whitespaces) }
}

nonisolated private func isOrgTableSeparatorCell(_ cell: String) -> Bool {
    let trimmed = cell.trimmingCharacters(in: .whitespaces)
    return !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" || $0 == "+" }
}

private enum OrgListType {
    case unordered
    case ordered
}

nonisolated private func orderedListItem(in line: String) -> String? {
    guard let match = line.firstMatch(of: /^(\d+)\.\s+(.+)$/) else { return nil }
    return String(match.2)
}

nonisolated private func protectMatches(
    in text: String,
    pattern: String,
    protectedFragments: inout [String: String],
    transform: (NSTextCheckingResult, NSString) -> String
) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
    var result = text
    let matches = regex.matches(in: result, range: NSRange(location: 0, length: (result as NSString).length))

    for match in matches.reversed() {
        let token = "__ORG_PROTECTED_\(protectedFragments.count)__"
        let nsText = result as NSString
        protectedFragments[token] = transform(match, nsText)
        result = nsText.replacingCharacters(in: match.range, with: token)
    }

    return result
}

nonisolated private func replaceMatches(
    in text: String,
    pattern: String,
    transform: (NSTextCheckingResult, NSString) -> String
) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
    var result = text
    let matches = regex.matches(in: result, range: NSRange(location: 0, length: (result as NSString).length))

    for match in matches.reversed() {
        let nsText = result as NSString
        let replacement = transform(match, nsText)
        result = nsText.replacingCharacters(in: match.range, with: replacement)
    }

    return result
}

nonisolated private func makeOrgImageHTML(
    source: String,
    alt: String?,
    imageURLResolver: ((String) -> String?)?
) -> String? {
    guard isRenderableImageSource(source) else { return nil }
    let resolvedSource = imageURLResolver?(source) ?? source
    let altText = escapeHTMLAttribute(alt ?? "")
    return #"<img src="\#(resolvedSource)" alt="\#(altText)">"#
}

nonisolated private func isRenderableImageSource(_ source: String) -> Bool {
    let lowercased = source.lowercased()
    return [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp", ".heic"]
        .contains(where: { lowercased.hasSuffix($0) })
}

nonisolated func resolveRepositoryAssetURL(
    _ source: String,
    owner: String,
    repositoryName: String,
    readmePath: String?
) -> String? {
    let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSource.isEmpty else { return nil }

    if trimmedSource.hasPrefix("http://") || trimmedSource.hasPrefix("https://") || trimmedSource.hasPrefix("data:") {
        return trimmedSource
    }

    let relativePath: String
    if trimmedSource.hasPrefix("/") {
        relativePath = String(trimmedSource.dropFirst())
    } else {
        let readmeDirectory = (readmePath as NSString?)?.deletingLastPathComponent ?? ""
        relativePath = normalizeRepositoryPath(
            (readmeDirectory as NSString).appendingPathComponent(trimmedSource)
        )
    }

    guard !relativePath.isEmpty else { return nil }
    return "https://git.sr.ht/\(owner)/\(repositoryName)/blob/HEAD/\(relativePath)"
}

nonisolated private func normalizeRepositoryPath(_ path: String) -> String {
    var components: [String] = []

    for part in path.split(separator: "/") {
        switch part {
        case ".":
            continue
        case "..":
            if !components.isEmpty {
                components.removeLast()
            }
        default:
            components.append(String(part))
        }
    }

    return components.joined(separator: "/")
}

nonisolated private func renderTaskListItem(
    _ text: String,
    inlineRenderer: (String) -> String
) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard trimmed.count >= 4 else {
        return inlineRenderer(text)
    }

    let prefix = String(trimmed.prefix(4))
    let remainder = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)

    switch prefix {
    case "[ ] ":
        return #"<span class="task-list-item"><input type="checkbox" disabled> \#(inlineRenderer(remainder))</span>"#
    case "[x] ", "[X] ":
        return #"<span class="task-list-item"><input type="checkbox" checked disabled> \#(inlineRenderer(remainder))</span>"#
    default:
        return inlineRenderer(text)
    }
}

// MARK: - WKWebView Wrapper

/// A WKWebView wrapper that renders HTML inline and grows to fit its content.
struct HTMLWebView: View {
    let html: String
    let colorScheme: ColorScheme
    var style: HTMLWebViewStyle = .readme
    @Environment(\.openURL) private var openURL
    @State private var contentHeight: CGFloat = 1
    @State private var loadError: String?
    @State private var reloadToken = 0

    var body: some View {
        Group {
            if let loadError {
                SRHTErrorStateView(
                    title: "Couldn't Render Content",
                    message: loadError,
                    retryAction: {
                        await MainActor.run {
                            self.loadError = nil
                            reloadToken += 1
                        }
                    }
                )
            } else {
                HTMLWebViewRepresentable(
                    html: html,
                    colorScheme: colorScheme,
                    style: style,
                    openURL: openURL,
                    dynamicHeight: $contentHeight,
                    loadError: $loadError,
                    reloadToken: reloadToken
                )
                .frame(height: max(contentHeight, 1))
            }
        }
    }
}

struct HTMLWebViewStyle: Sendable {
    let bodyFontSize: Int
    let lineHeight: Double
    let codeFontSize: Int
    let viewport: String

    static let readme = HTMLWebViewStyle(
        bodyFontSize: 16,
        lineHeight: 1.6,
        codeFontSize: 13,
        viewport: "width=device-width, initial-scale=1, maximum-scale=1"
    )

    static let commentPreview = HTMLWebViewStyle(
        bodyFontSize: 15,
        lineHeight: 1.5,
        codeFontSize: 12,
        viewport: "width=device-width, initial-scale=1, user-scalable=no"
    )
}

private struct HTMLWebViewRepresentable: UIViewRepresentable {
    let html: String
    let colorScheme: ColorScheme
    let style: HTMLWebViewStyle
    let openURL: OpenURLAction
    @Binding var dynamicHeight: CGFloat
    @Binding var loadError: String?
    let reloadToken: Int

    func makeCoordinator() -> HTMLWebViewCoordinator {
        HTMLWebViewCoordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = HTMLWebViewCoordinator.websiteDataStore
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.clipsToBounds = false
        webView.allowsLinkPreview = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.clipsToBounds = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let textColor = colorScheme == .dark ? "#fff" : "#000"
        let linkColor = colorScheme == .dark ? "#58a6ff" : "#0066cc"

        let wrapped = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="\(style.viewport)">
        <style>
            body {
                font-family: -apple-system, system-ui, sans-serif;
                font-size: \(style.bodyFontSize)px;
                line-height: \(style.lineHeight);
                padding: 0;
                margin: 0;
                color: \(textColor);
                background: transparent;
                word-wrap: break-word;
                overflow-wrap: break-word;
                max-width: 100%;
            }
            * { box-sizing: border-box; }
            h1, h2, h3, h4, h5, h6 { line-height: 1.25; }
            p:first-child { margin-top: 0; }
            p:last-child { margin-bottom: 0; }
            pre, code {
                font-family: ui-monospace, Menlo, monospace;
                font-size: \(style.codeFontSize)px;
                background: rgba(128, 128, 128, 0.15);
                padding: 2px 4px;
                border-radius: 3px;
            }
            pre code { padding: 0; background: none; }
            pre {
                padding: 8px;
                overflow-x: auto;
                white-space: pre-wrap;
                word-wrap: break-word;
            }
            img { max-width: 100%; height: auto; }
            input[type="checkbox"] {
                margin-right: 0.45rem;
                vertical-align: middle;
            }
            .task-list-item {
                display: inline-flex;
                align-items: center;
                gap: 0.1rem;
            }
            a { color: \(linkColor); }
            table { border-collapse: collapse; width: 100%; }
            td, th { border: 1px solid #ccc; padding: 4px 8px; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """

        if let cachedHeight = HTMLWebViewCoordinator.heightCache.object(forKey: wrapped as NSString)?.doubleValue {
            let height = CGFloat(cachedHeight)
            if abs(dynamicHeight - height) > 0.5 {
                dynamicHeight = height
            }
        }

        guard context.coordinator.lastHTML != wrapped || context.coordinator.lastReloadToken != reloadToken else { return }
        context.coordinator.lastHTML = wrapped
        context.coordinator.lastReloadToken = reloadToken
        if loadError != nil {
            DispatchQueue.main.async {
                self.loadError = nil
            }
        }
        webView.loadHTMLString(wrapped, baseURL: nil)
    }
}

private final class HTMLWebViewCoordinator: NSObject, WKNavigationDelegate, @unchecked Sendable {
    static let websiteDataStore = WKWebsiteDataStore.nonPersistent()
    static let heightCache = NSCache<NSString, NSNumber>()

    let parent: HTMLWebViewRepresentable
    var lastHTML: String?
    var lastReloadToken = 0

    init(parent: HTMLWebViewRepresentable) {
        self.parent = parent
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.parent.loadError = nil
        }
        updateHeight(for: webView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak webView] in
            guard let self, let webView else { return }
            self.updateHeight(for: webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let requestURL = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if navigationAction.navigationType == .linkActivated {
            if isAllowedReadmeNavigationURL(requestURL) {
                parent.openURL(requestURL)
            }
            decisionHandler(.cancel)
            return
        }

        if isAllowedReadmeNavigationURL(requestURL) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    private func handleLoadFailure(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        DispatchQueue.main.async {
            self.parent.loadError = "The content could not be displayed right now."
        }
    }

    private func updateHeight(for webView: WKWebView) {
        webView.layoutIfNeeded()
        let height = ceil(max(webView.scrollView.contentSize.height, webView.sizeThatFits(.zero).height)) + 4
        guard height > 0 else { return }
        DispatchQueue.main.async {
            if let html = self.lastHTML {
                Self.heightCache.setObject(NSNumber(value: Double(height)), forKey: html as NSString)
            }
            if abs(self.parent.dynamicHeight - height) > 0.5 {
                self.parent.dynamicHeight = height
            }
        }
    }
}
