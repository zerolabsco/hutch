import SwiftUI
import WebKit

struct ReadmeView: View {
    @Environment(AppState.self) private var appState
    let viewModel: RepositoryDetailViewModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var isShowingRepositoryDetails = false
    @State private var linkedFile: LinkedFileRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                metadataSection
                repositoryDetailsSection
                latestChangeSection
                readmeSection
                if appState.isDebugModeEnabled {
                    debugSection
                }
            }
            .padding()
        }
        .sheet(item: $linkedFile) { request in
            LinkedFileSheetView(
                rid: viewModel.repository.rid,
                service: viewModel.repository.service,
                client: appState.client,
                request: request
            )
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
            if let branchLabel = repositoryPrimaryBranchLabel(for: viewModel.repository) {
                SummaryMetadataRow(
                    icon: "arrow.triangle.branch",
                    title: branchLabel
                )
            }

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
                SummaryDetailRow(label: "Forge", value: repositoryForgeLabel(viewModel.repository.service))
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
                repositoryName: viewModel.repository.name,
                onInterceptURL: { url in
                    guard let request = parseLinkedFileRequest(url) else { return false }
                    linkedFile = request
                    return true
                }
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

    /// Parses a resolved blob URL for this repository and returns a `LinkedFileRequest`
    /// if the URL matches the pattern `{host}/{owner}/{repo}/blob/{revspec}/{path}`.
    /// Returns `nil` for any other URL (external links, fragment links, etc.).
    private func parseLinkedFileRequest(_ url: URL) -> LinkedFileRequest? {
        let expectedHost = "\(viewModel.repository.service.rawValue).sr.ht"
        guard let host = url.host, host == expectedHost else { return nil }

        // pathComponents for https://git.sr.ht/~owner/repo/blob/HEAD/file
        // → ["/", "~owner", "repo", "blob", "HEAD", "file"]
        let parts = url.pathComponents
        guard parts.count >= 6,
              parts[1] == viewModel.repository.owner.canonicalName,
              parts[2] == viewModel.repository.name,
              parts[3] == "blob" else { return nil }

        let revspec = parts[4]
        let path = parts[5...].joined(separator: "/")
        guard !path.isEmpty else { return nil }

        let fileName = parts.last ?? path
        return LinkedFileRequest(path: path, revspec: revspec, fileName: fileName)
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

    private var debugSection: some View {
        DebugTextBlock(
            title: "Debug",
            content: """
            repositoryId: \(viewModel.repository.id)
            rid: \(viewModel.repository.rid)
            service: \(viewModel.repository.service.rawValue)
            defaultBranch: \(viewModel.repository.defaultBranchName ?? "none")
            webURL: \(SRHTWebURL.repository(viewModel.repository)?.absoluteString ?? "unavailable")
            httpsClone: \(SRHTWebURL.httpsCloneURL(viewModel.repository) ?? "unavailable")
            sshClone: \(SRHTWebURL.sshCloneURL(viewModel.repository))
            readmePath: \(viewModel.readmePath ?? "none")
            commitsLoaded: \(viewModel.commits.count)
            branchesLoaded: \(viewModel.branches.count)
            tagsLoaded: \(viewModel.tags.count)
            """
        )
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
    var onInterceptURL: ((URL) -> Bool)? = nil

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
                HTMLWebView(html: html, colorScheme: colorScheme, onInterceptURL: onInterceptURL)
            case .markdown, .org:
                if let renderedHTML {
                    HTMLWebView(html: renderedHTML, colorScheme: colorScheme, onInterceptURL: onInterceptURL)
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
                markdownToHTML(
                    text,
                    imageURLResolver: { source in
                        resolveRepositoryAssetURL(
                            source,
                            owner: ownerCanonicalName,
                            repositoryName: repositoryName,
                            readmePath: readmePath
                        )?
                        .replacingOccurrences(of: "git.sr.ht", with: repositoryHost)
                    },
                    linkURLResolver: { source in
                        resolveRepositoryLinkURL(
                            source,
                            owner: ownerCanonicalName,
                            repositoryName: repositoryName,
                            readmePath: readmePath
                        )?
                        .replacingOccurrences(of: "git.sr.ht", with: repositoryHost)
                    }
                )
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
                orgToHTML(
                    text,
                    imageURLResolver: { source in
                        resolveRepositoryAssetURL(
                            source,
                            owner: ownerCanonicalName,
                            repositoryName: repositoryName,
                            readmePath: readmePath
                        )?
                        .replacingOccurrences(of: "git.sr.ht", with: repositoryHost)
                    },
                    linkURLResolver: { source in
                        resolveRepositoryLinkURL(
                            source,
                            owner: ownerCanonicalName,
                            repositoryName: repositoryName,
                            readmePath: readmePath
                        )?
                        .replacingOccurrences(of: "git.sr.ht", with: repositoryHost)
                    }
                )
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

nonisolated func processInline(
    _ text: String,
    imageURLResolver: ((String) -> String?)? = nil,
    linkURLResolver: ((String) -> String?)? = nil
) -> String {

    var protectedFragments: [String: String] = [:]
    var result = protectMatches(
        in: text,
        pattern: #"</?[A-Za-z][^>]*?>"#,
        protectedFragments: &protectedFragments
    ) { match, nsText in
        let rawTag = nsText.substring(with: match.range)
        return sanitizedMarkdownHTMLTag(rawTag) ?? escapeHTML(rawTag)
    }

    result = escapeHTML(result)

    // Images: ![alt](url)
    result = replaceMatches(in: result, pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) { match, nsText in
        let alt = nsText.substring(with: match.range(at: 1))
        let source = decodeHTMLEntities(nsText.substring(with: match.range(at: 2)))
        let resolvedSource = imageURLResolver?(source) ?? source
        guard let sanitizedSource = sanitizedReadmeImageURLString(resolvedSource) else {
            return escapeHTML(alt)
        }
        return #"<img src="\#(sanitizedSource)" alt="\#(escapeHTMLAttribute(alt))">"#
    }
    // Links: [text](url)
    result = replaceMatches(in: result, pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) { match, nsText in
        let label = nsText.substring(with: match.range(at: 1))
        let rawURL = decodeHTMLEntities(nsText.substring(with: match.range(at: 2)))
        let resolvedURL = linkURLResolver?(rawURL) ?? rawURL
        guard let sanitizedURL = sanitizedReadmeLinkURLString(resolvedURL) else {
            return label
        }
        return #"<a href="\#(sanitizedURL)">\#(label)</a>"#
    }
    // Plain email autolinks
    result = replaceMatches(
        in: result,
        pattern: #"(?i)(?<![\w.%+\-])([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})(?![\w\-])"#
    ) { match, nsText in
        guard !isInsideHTMLTag(nsText, range: match.range) else {
            return nsText.substring(with: match.range)
        }
        let email = nsText.substring(with: match.range(at: 1))
        let href = escapeHTMLAttribute("mailto:\(email)")
        return #"<a href="\#(href)">\#(email)</a>"#
    }
    // Strikethrough: ~~text~~
    result = result.replacingOccurrences(
        of: #"~~(.+?)~~"#,
        with: "<del>$1</del>",
        options: .regularExpression
    )
    // Bold: **text**
    result = result.replacingOccurrences(
        of: #"\*\*(.+?)\*\*"#,
        with: "<strong>$1</strong>",
        options: .regularExpression
    )
    // Italic: *text*
    result = result.replacingOccurrences(
        of: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#,
        with: "<em>$1</em>",
        options: .regularExpression
    )
    // Italic: _text_
    result = result.replacingOccurrences(
        of: #"(?<!\w)_(.+?)_(?!\w)"#,
        with: "<em>$1</em>",
        options: .regularExpression
    )
    // Inline code: `text`
    result = result.replacingOccurrences(
        of: #"`([^`]+)`"#,
        with: "<code>$1</code>",
        options: .regularExpression
    )

    for (token, fragment) in protectedFragments {
        result = result.replacingOccurrences(of: token, with: fragment)
    }

    return result
}

// MARK: - Org-mode to HTML

nonisolated func orgToHTML(
    _ text: String,
    imageURLResolver: ((String) -> String?)? = nil,
    linkURLResolver: ((String) -> String?)? = nil
) -> String {
    let normalizedText = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let rawLines = normalizedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var title: String?
    var author: String?
    var date: String?
    let lines = rawLines.filter { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let directive = orgKeywordDirective(in: trimmed) else {
            return true
        }
        switch directive.keyword {
        case "title":
            title = directive.value
            return false
        case "author":
            author = directive.value
            return false
        case "date":
            date = directive.value
            return false
        default:
            return true
        }
    }
    var html = ""
    var listType: OrgListType?
    var inQuoteBlock = false
    var inPropertyDrawer = false
    var srcLanguage: String?
    var inExampleBlock = false
    var inCenterBlock = false
    var inVerseBlock = false
    var currentListItemLines: [String] = []
    var paragraph: [String] = []
    var tableRows: [[String]] = []
    var propertyRows: [(String, String)] = []
    var verseLines: [String] = []
    var pendingBlockName: String?
    var pendingBlockCaption: String?
    var activeBlockCaption: String?
    var isWrappingBlockFigure = false

    func beginPendingBlockWrapperIfNeeded() {
        guard pendingBlockName != nil || pendingBlockCaption != nil else { return }
        let idAttribute = pendingBlockName.map { #" id="\#(escapeHTMLAttribute($0))""# } ?? ""
        html += #"<figure class="org-block"\#(idAttribute)>"# + "\n"
        activeBlockCaption = pendingBlockCaption
        isWrappingBlockFigure = true
        pendingBlockName = nil
        pendingBlockCaption = nil
    }

    func closePendingBlockWrapper() {
        guard isWrappingBlockFigure else { return }
        if let activeBlockCaption {
            html += "<figcaption>" + processOrgInline(activeBlockCaption, imageURLResolver: imageURLResolver, linkURLResolver: linkURLResolver) + "</figcaption>\n"
        }
        html += "</figure>\n"
        activeBlockCaption = nil
        isWrappingBlockFigure = false
    }

    func flushParagraph() {
        if !paragraph.isEmpty {
            let normalizedParagraph = paragraph
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
            html += "<p>" + processOrgInline(normalizedParagraph, imageURLResolver: imageURLResolver, linkURLResolver: linkURLResolver) + "</p>\n"
            paragraph = []
        }
    }

    func flushListItem() {
        guard !currentListItemLines.isEmpty else { return }
        html += "<li>" + renderOrgListItemBody(
            currentListItemLines,
            imageURLResolver: imageURLResolver,
            linkURLResolver: linkURLResolver
        ) + "</li>\n"
        currentListItemLines = []
    }

    func closeList() {
        flushListItem()
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
        beginPendingBlockWrapperIfNeeded()
        html += renderHTMLTable(
            rows: tableRows,
            inlineRenderer: { processOrgInline($0, imageURLResolver: imageURLResolver, linkURLResolver: linkURLResolver) }
        )
        closePendingBlockWrapper()
        tableRows = []
    }

    func flushPropertyDrawer() {
        guard !propertyRows.isEmpty else { return }
        html += "<dl class=\"org-properties\">\n"
        for (key, value) in propertyRows {
            html += "<dt>" + escapeHTML(key) + "</dt>"
            html += "<dd>" + processOrgInline(value, imageURLResolver: imageURLResolver, linkURLResolver: linkURLResolver) + "</dd>\n"
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
            closePendingBlockWrapper()
        }
    }

    func closeExampleBlock() {
        if inExampleBlock {
            html += "</code></pre>\n"
            inExampleBlock = false
            closePendingBlockWrapper()
        }
    }

    func closeCenterBlock() {
        if inCenterBlock {
            flushParagraph()
            html += "</div>\n"
            inCenterBlock = false
            closePendingBlockWrapper()
        }
    }

    func closeVerseBlock() {
        if inVerseBlock {
            let content = verseLines
                .map { processOrgInline($0, imageURLResolver: imageURLResolver, linkURLResolver: linkURLResolver) }
                .joined(separator: "\n")
            html += #"<blockquote class="org-verse">"# + "\n"
            html += content + "\n"
            html += "</blockquote>\n"
            verseLines = []
            inVerseBlock = false
            closePendingBlockWrapper()
        }
    }

    func flushBlockState() {
        flushParagraph()
        closeList()
        flushTable()
        flushPropertyDrawer()
    }

    if title != nil || author != nil || date != nil {
        html += "<div class=\"org-metadata\">\n"
        if let title {
            html += "<h1 class=\"org-title\">" + escapeHTML(title) + "</h1>\n"
        }
        if let author {
            html += "<p class=\"org-author\">" + escapeHTML(author) + "</p>\n"
        }
        if let date {
            html += "<p class=\"org-date\">" + escapeHTML(date) + "</p>\n"
        }
        html += "</div>\n"
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

        if inExampleBlock {
            if trimmed.lowercased() == "#+end_example" {
                closeExampleBlock()
            } else {
                html += escapeHTML(line) + "\n"
            }
            continue
        }

        if inVerseBlock {
            if trimmed.lowercased() == "#+end_verse" {
                closeVerseBlock()
            } else {
                verseLines.append(line)
            }
            continue
        }

        if inQuoteBlock, trimmed.lowercased() == "#+end_quote" {
            closeQuoteBlock()
            continue
        }

        if inCenterBlock {
            if trimmed.lowercased() == "#+end_center" {
                closeCenterBlock()
            } else if trimmed.isEmpty {
                flushParagraph()
            } else {
                paragraph.append(line)
            }
            continue
        }

        if trimmed == "#" || trimmed.hasPrefix("# ") {
            continue
        }

        if let directive = orgKeywordDirective(in: trimmed) {
            switch directive.keyword {
            case "caption":
                pendingBlockCaption = directive.value
                continue
            case "name":
                pendingBlockName = directive.value
                continue
            case "options", "property":
                continue
            default:
                break
            }
        }

        if trimmed.lowercased().hasPrefix("#+begin_src") {
            closeQuoteBlock()
            flushBlockState()
            beginPendingBlockWrapperIfNeeded()
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

        if trimmed.lowercased() == "#+begin_example" {
            closeQuoteBlock()
            flushBlockState()
            beginPendingBlockWrapperIfNeeded()
            html += "<pre><code>"
            inExampleBlock = true
            continue
        }

        if trimmed.lowercased() == "#+begin_quote" {
            flushBlockState()
            beginPendingBlockWrapperIfNeeded()
            html += "<blockquote>\n"
            inQuoteBlock = true
            continue
        }

        if trimmed.lowercased() == "#+begin_center" {
            closeQuoteBlock()
            flushBlockState()
            beginPendingBlockWrapperIfNeeded()
            html += "<div style=\"text-align:center\">\n"
            inCenterBlock = true
            continue
        }

        if trimmed.lowercased() == "#+begin_verse" {
            closeQuoteBlock()
            flushBlockState()
            beginPendingBlockWrapperIfNeeded()
            verseLines = []
            inVerseBlock = true
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

        if isTableLine(trimmed) {
            closeQuoteBlock()
            flushParagraph()
            closeList()
            tableRows.append(parseTableRow(trimmed))
            continue
        } else {
            flushTable()
        }

        if isOrgHorizontalRule(trimmed) {
            closeQuoteBlock()
            flushBlockState()
            html += "<hr>\n"
            continue
        }

        // Org headings: * heading, ** heading, *** heading
        if let match = trimmed.firstMatch(of: /^(\*{1,6})\s+(.+)$/) {
            closeQuoteBlock()
            flushBlockState()
            let level = match.1.count
            let content = processOrgInline(String(match.2), imageURLResolver: imageURLResolver, linkURLResolver: linkURLResolver)
            html += "<h\(level)>" + content + "</h\(level)>\n"
            continue
        }

        if listType != nil && isIndentedContinuationLine(line) {
            currentListItemLines.append(line)
            continue
        }

        // List items: - item
        if !isIndentedContinuationLine(line), trimmed.hasPrefix("- ") {
            flushParagraph()
            flushPropertyDrawer()
            if listType != .unordered {
                closeList()
                html += "<ul>\n"
                listType = .unordered
            }
            flushListItem()
            currentListItemLines = [String(trimmed.dropFirst(2))]
            continue
        }

        if !isIndentedContinuationLine(line), let orderedItem = orderedListItem(in: trimmed) {
            flushParagraph()
            flushPropertyDrawer()
            if listType != .ordered {
                closeList()
                html += "<ol>\n"
                listType = .ordered
            }
            flushListItem()
            currentListItemLines = [orderedItem]
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
        if pendingBlockName != nil || pendingBlockCaption != nil {
            pendingBlockName = nil
            pendingBlockCaption = nil
        }
        paragraph.append(line)
    }

    closeSourceBlock()
    closeExampleBlock()
    closeCenterBlock()
    closeVerseBlock()
    closeQuoteBlock()
    flushBlockState()

    return html
}

nonisolated private func processOrgInline(
    _ text: String,
    imageURLResolver: ((String) -> String?)? = nil,
    linkURLResolver: ((String) -> String?)? = nil
) -> String {
    var result = escapeHTML(text)
    var protectedFragments: [String: String] = [:]

    result = protectMatches(
        in: result,
        pattern: #"\[\[([^\]]+)\]\[\[([^\]]+)\]\]\]"#,
        protectedFragments: &protectedFragments
    ) { match, nsText in
        let destination = nsText.substring(with: match.range(at: 1))
        let source = nsText.substring(with: match.range(at: 2))
        guard let imageHTML = makeOrgImageHTML(
            source: source,
            alt: nil,
            imageURLResolver: imageURLResolver
        ) else {
            return source
        }
        let resolvedDestination = linkURLResolver?(destination) ?? destination
        guard let sanitizedURL = sanitizedReadmeLinkURLString(resolvedDestination) else {
            return imageHTML
        }
        return #"<a href="\#(sanitizedURL)">\#(imageHTML)</a>"#
    }

    result = protectOrgLinks(
        in: result,
        protectedFragments: &protectedFragments,
        imageURLResolver: imageURLResolver,
        linkURLResolver: linkURLResolver
    )
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
    result = protectMatches(
        in: result,
        pattern: #"(?<!\S)\+(.+?)\+(?=\s|$|[.,;:!?])"#,
        protectedFragments: &protectedFragments
    ) { match, nsText in
        let value = nsText.substring(with: match.range(at: 1))
        return "<del>\(value)</del>"
    }
    result = protectMatches(
        in: result,
        pattern: #"(?<!\S)_(.+?)_(?=\s|$|[.,;:!?])"#,
        protectedFragments: &protectedFragments
    ) { match, nsText in
        let value = nsText.substring(with: match.range(at: 1))
        return "<u>\(value)</u>"
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
    result = replaceMatches(
        in: result,
        pattern: #"(?i)(?<![\w.%+\-])([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})(?![\w\-])"#
    ) { match, nsText in
        guard !isInsideHTMLTag(nsText, range: match.range) else {
            return nsText.substring(with: match.range)
        }
        let email = nsText.substring(with: match.range(at: 1))
        let href = escapeHTMLAttribute("mailto:\(email)")
        return #"<a href="\#(href)">\#(email)</a>"#
    }

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

nonisolated func escapeHTMLAttribute(_ text: String) -> String {
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

nonisolated private func isTableLine(_ line: String) -> Bool {
    line.hasPrefix("|") && line.hasSuffix("|")
}

nonisolated private func parseTableRow(_ line: String) -> [String] {
    line
        .split(separator: "|", omittingEmptySubsequences: false)
        .dropFirst()
        .dropLast()
        .map { String($0).trimmingCharacters(in: .whitespaces) }
}

nonisolated private func parseOrgTableSeparatorRow(_ line: String) -> [String] {
    var content = line.trimmingCharacters(in: .whitespaces)
    if content.hasPrefix("|") {
        content.removeFirst()
    }
    if content.hasSuffix("|") {
        content.removeLast()
    }
    return content
        .split(separator: "+", omittingEmptySubsequences: false)
        .map { String($0).trimmingCharacters(in: .whitespaces) }
}

nonisolated private func isTableSeparatorCell(_ cell: String) -> Bool {
    tableAlignment(for: cell) != nil
}

nonisolated private func tableAlignment(for cell: String) -> String? {
    let trimmed = cell.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }

    let core = trimmed.replacingOccurrences(of: ":", with: "")
    guard !core.isEmpty, core.allSatisfy({ $0 == "-" || $0 == "+" }) else {
        return nil
    }

    let isLeftAligned = trimmed.hasPrefix(":")
    let isRightAligned = trimmed.hasSuffix(":")
    switch (isLeftAligned, isRightAligned) {
    case (true, true):
        return "center"
    case (true, false):
        return "left"
    case (false, true):
        return "right"
    case (false, false):
        return ""
    }
}

nonisolated private func renderHTMLTable(
    rows: [[String]],
    inlineRenderer: (String) -> String
) -> String {
    guard !rows.isEmpty else { return "" }
    let separatorCells: [String]
    if rows.count > 1, rows[1].count == 1 {
        separatorCells = parseOrgTableSeparatorRow(rows[1][0])
    } else {
        separatorCells = rows.count > 1 ? rows[1] : []
    }
    let hasHeaderSeparator = rows.count > 1 && !separatorCells.isEmpty && separatorCells.allSatisfy(isTableSeparatorCell)
    let headerRow = rows.first ?? []
    let bodyRows = hasHeaderSeparator ? Array(rows.dropFirst(2)) : rows
    let columnAlignments = hasHeaderSeparator ? separatorCells.map(tableAlignment) : []
    var html = "<table>\n"

    if hasHeaderSeparator {
        html += "<thead><tr>"
        for (index, cell) in headerRow.enumerated() {
            html += "<th" + tableAlignmentStyleAttribute(columnAlignment(at: index, in: columnAlignments)) + ">" + inlineRenderer(cell) + "</th>"
        }
        html += "</tr></thead>\n"
    }

    html += "<tbody>\n"
    for row in bodyRows {
        html += "<tr>"
        for (index, cell) in row.enumerated() {
            html += "<td" + tableAlignmentStyleAttribute(columnAlignment(at: index, in: columnAlignments)) + ">" + inlineRenderer(cell) + "</td>"
        }
        html += "</tr>\n"
    }
    html += "</tbody>\n"
    html += "</table>\n"
    return html
}

nonisolated private func columnAlignment(at index: Int, in alignments: [String?]) -> String? {
    guard alignments.indices.contains(index) else { return nil }
    return alignments[index]
}

nonisolated private func tableAlignmentStyleAttribute(_ alignment: String?) -> String {
    guard let alignment, !alignment.isEmpty else { return "" }
    return #" style="text-align: \#(alignment);""#
}

private enum OrgListType: Equatable {
    case unordered
    case ordered
}

nonisolated private func orderedListItem(in line: String) -> String? {
    guard let match = line.firstMatch(of: /^(\d+)\.\s+(.+)$/) else { return nil }
    return String(match.2)
}

nonisolated private func renderOrgListItemBody(
    _ lines: [String],
    imageURLResolver: ((String) -> String?)? = nil,
    linkURLResolver: ((String) -> String?)? = nil
) -> String {
    guard let firstLine = lines.first else { return "" }

    var contentLines: [String] = [firstLine.trimmingCharacters(in: .whitespaces)]
    var nestedLines: [String] = []

    for line in lines.dropFirst() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            continue
        }

        if isIndentedListItemLine(line) {
            nestedLines.append(outdentOrgListLine(line))
        } else {
            contentLines.append(trimmed)
        }
    }

    var html = renderTaskListItem(
        contentLines.joined(separator: " "),
        inlineRenderer: { processOrgInline($0, imageURLResolver: imageURLResolver, linkURLResolver: linkURLResolver) }
    )
    if !nestedLines.isEmpty {
        html += "\n" + renderNestedOrgListHTML(nestedLines, imageURLResolver: imageURLResolver, linkURLResolver: linkURLResolver)
    }
    return html
}

nonisolated private func renderNestedOrgListHTML(
    _ lines: [String],
    imageURLResolver: ((String) -> String?)? = nil,
    linkURLResolver: ((String) -> String?)? = nil
) -> String {
    var html = ""
    var listType: OrgListType?
    var currentItemLines: [String] = []

    func flushNestedItem() {
        guard !currentItemLines.isEmpty else { return }
        html += "<li>" + renderOrgListItemBody(currentItemLines, imageURLResolver: imageURLResolver, linkURLResolver: linkURLResolver) + "</li>\n"
        currentItemLines = []
    }

    func closeNestedList() {
        flushNestedItem()
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

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") {
            if listType != .unordered {
                closeNestedList()
                html += "<ul>\n"
                listType = .unordered
            }
            flushNestedItem()
            currentItemLines = [String(trimmed.dropFirst(2))]
            continue
        }

        if let orderedItem = orderedListItem(in: trimmed) {
            if listType != .ordered {
                closeNestedList()
                html += "<ol>\n"
                listType = .ordered
            }
            flushNestedItem()
            currentItemLines = [orderedItem]
            continue
        }

        if listType != nil {
            currentItemLines.append(line)
        }
    }

    closeNestedList()
    return html
}

nonisolated private func protectOrgLinks(
    in text: String,
    protectedFragments: inout [String: String],
    imageURLResolver: ((String) -> String?)? = nil,
    linkURLResolver: ((String) -> String?)? = nil
) -> String {
    var result = text

    while let range = result.range(of: "[[") {
        guard let parsed = parseOrgLink(in: result, from: range.lowerBound) else {
            break
        }
        let token = "ZZPROTECTED\(protectedFragments.count)ZZ"
        protectedFragments[token] = renderOrgLink(
            destination: parsed.destination,
            label: parsed.label,
            imageURLResolver: imageURLResolver,
            linkURLResolver: linkURLResolver
        )
        result.replaceSubrange(parsed.range, with: token)
    }

    return result
}

nonisolated private func parseOrgLink(
    in text: String,
    from start: String.Index
) -> (range: Range<String.Index>, destination: String, label: String?)? {
    guard text[start...].hasPrefix("[[") else { return nil }

    var index = text.index(start, offsetBy: 2)
    guard let destinationEnd = text[index...].range(of: "][" )?.lowerBound else {
        guard let end = text[index...].range(of: "]]")?.lowerBound else { return nil }
        return (start..<text.index(end, offsetBy: 2), String(text[index..<end]), nil)
    }

    let destination = String(text[index..<destinationEnd])
    index = text.index(destinationEnd, offsetBy: 2)
    let labelStart = index
    var depth = 0

    while index < text.endIndex {
        if text[index...].hasPrefix("[[") {
            depth += 1
            index = text.index(index, offsetBy: 2)
            continue
        }
        if text[index...].hasPrefix("]]") {
            if depth == 0 {
                let end = text.index(index, offsetBy: 2)
                return (start..<end, destination, String(text[labelStart..<index]))
            }
            depth -= 1
            index = text.index(index, offsetBy: 2)
            continue
        }
        index = text.index(after: index)
    }

    return nil
}

nonisolated private func renderOrgLink(
    destination: String,
    label: String?,
    imageURLResolver: ((String) -> String?)? = nil,
    linkURLResolver: ((String) -> String?)? = nil
) -> String {
    if let label, label.hasPrefix("[["), label.hasSuffix("]]") {
        let source = String(label.dropFirst(2).dropLast(2))
        if let imageHTML = makeOrgImageHTML(source: source, alt: nil, imageURLResolver: imageURLResolver) {
            let resolvedDestination = linkURLResolver?(destination) ?? destination
            guard let sanitizedURL = sanitizedReadmeLinkURLString(resolvedDestination) else {
                return imageHTML
            }
            return #"<a href="\#(sanitizedURL)">\#(imageHTML)</a>"#
        }
    }

    if let imageHTML = makeOrgImageHTML(
        source: destination,
        alt: label,
        imageURLResolver: imageURLResolver
    ) {
        return imageHTML
    }

    let resolvedDestination = linkURLResolver?(destination) ?? destination
    guard let sanitizedURL = sanitizedReadmeLinkURLString(resolvedDestination) else {
        return label ?? destination
    }

    let renderedLabel = label.map {
        processOrgInline($0, imageURLResolver: imageURLResolver, linkURLResolver: linkURLResolver)
    } ?? destination
    return #"<a href="\#(sanitizedURL)">\#(renderedLabel)</a>"#
}

nonisolated private func orgKeywordDirective(in line: String) -> (keyword: String, value: String)? {
    guard let match = line.firstMatch(of: /^#\+([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$/) else {
        return nil
    }
    return (
        keyword: String(match.1).lowercased(),
        value: String(match.2).trimmingCharacters(in: .whitespaces)
    )
}


nonisolated private func isOrgHorizontalRule(_ line: String) -> Bool {
    matchesRegex(line, pattern: #"^\s*-{5,}\s*$"#)
}

nonisolated private func matchesRegex(_ text: String, pattern: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
    let range = NSRange(location: 0, length: (text as NSString).length)
    return regex.firstMatch(in: text, range: range) != nil
}

nonisolated private func isInsideHTMLTag(_ text: NSString, range: NSRange) -> Bool {
    guard range.location != NSNotFound else { return false }
    let prefix = text.substring(to: range.location)
    guard let lastOpen = prefix.lastIndex(of: "<") else { return false }
    guard let lastClose = prefix.lastIndex(of: ">") else { return true }
    return lastOpen > lastClose
}

nonisolated private func isIndentedContinuationLine(_ line: String) -> Bool {
    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
    guard let first = line.first else { return false }
    return first == " " || first == "\t"
}

nonisolated private func isIndentedListItemLine(_ line: String) -> Bool {
    guard isIndentedContinuationLine(line) else { return false }
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix("- ") || orderedListItem(in: trimmed) != nil
}

nonisolated private func outdentOrgListLine(_ line: String) -> String {
    var result = line
    while result.first == " " || result.first == "\t" {
        result.removeFirst()
    }
    return result
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}


nonisolated func decodeHTMLEntities(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
}

nonisolated func sanitizedMarkdownHTMLBlock(_ rawHTML: String) -> String? {
    var protectedFragments: [String: String] = [:]
    var foundUnsafeMarkup = false
    let protected = protectMatches(
        in: rawHTML,
        pattern: #"(?s)<!--.*?-->|</?[A-Za-z][^>]*?>"#,
        protectedFragments: &protectedFragments
    ) { match, nsText in
        let rawTag = nsText.substring(with: match.range)
        guard let sanitizedTag = sanitizedMarkdownHTMLTag(rawTag) else {
            foundUnsafeMarkup = true
            return ""
        }
        return sanitizedTag
    }

    guard !foundUnsafeMarkup else { return nil }

    var sanitized = escapeHTML(protected)
    sanitized = replaceMatches(in: sanitized, pattern: #"ZZPROTECTED\d+ZZ"#) { match, nsText in
        let token = nsText.substring(with: match.range)
        return protectedFragments[token] ?? ""
    }

    return sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : sanitized
}

nonisolated func sanitizedMarkdownHTMLTag(_ rawTag: String) -> String? {
    let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">") else { return nil }
    guard !trimmed.lowercased().hasPrefix("<!--") else { return nil }

    let selfClosing = trimmed.hasSuffix("/>")
    let contentStart = trimmed.index(after: trimmed.startIndex)
    let contentEnd = trimmed.index(trimmed.endIndex, offsetBy: selfClosing ? -2 : -1)
    let inner = trimmed[contentStart..<contentEnd].trimmingCharacters(in: .whitespacesAndNewlines)
    let isClosing = inner.hasPrefix("/")
    let body = isClosing ? inner.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines) : inner
    let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard let rawName = parts.first else { return nil }
    let tagName = rawName.lowercased()
    let allowedTags: Set<String> = [
        "a", "abbr", "b", "blockquote", "br", "code", "del", "div", "em",
        "hr", "i", "img", "li", "ol", "p", "pre", "span", "strong", "sub",
        "sup", "u", "ul"
    ]
    guard allowedTags.contains(tagName) else { return nil }

    if isClosing {
        return "</\(tagName)>"
    }

    let attributePortion = parts.count > 1 ? String(parts[1]) : ""
    let attributes = parseHTMLAttributes(attributePortion)
    var renderedAttributes: [String] = []

    for (name, value) in attributes {
        switch (tagName, name.lowercased()) {
        case ("a", "href"):
            if let sanitized = sanitizedReadmeLinkURLString(decodeHTMLEntities(value)) {
                renderedAttributes.append(#"href="\#(sanitized)""#)
            }
        case ("img", "src"):
            if let sanitized = sanitizedReadmeImageURLString(decodeHTMLEntities(value)) {
                renderedAttributes.append(#"src="\#(sanitized)""#)
            }
        case ("img", "alt"), (_, "title"), (_, "class"):
            renderedAttributes.append(#"\#(name)="\#(escapeHTMLAttribute(value))""#)
        default:
            continue
        }
    }

    let suffix = selfClosing || tagName == "br" || tagName == "hr" || tagName == "img" ? " /" : ""
    let attributeText = renderedAttributes.isEmpty ? "" : " " + renderedAttributes.joined(separator: " ")
    return "<\(tagName)\(attributeText)\(suffix)>"
}

nonisolated private func parseHTMLAttributes(_ text: String) -> [(String, String)] {
    guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z_:][A-Za-z0-9:._-]*)\s*=\s*"([^"]*)""#) else {
        return []
    }
    let nsText = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { match in
        let name = nsText.substring(with: match.range(at: 1))
        let value = nsText.substring(with: match.range(at: 2))
        return (name, value)
    }
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
        let token = "ZZPROTECTED\(protectedFragments.count)ZZ"
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
    guard let sanitizedSource = sanitizedReadmeImageURLString(resolvedSource) else { return nil }
    let altText = escapeHTMLAttribute(alt ?? "")
    return #"<img src="\#(sanitizedSource)" alt="\#(altText)">"#
}

nonisolated private func isRenderableImageSource(_ source: String) -> Bool {
    let lowercased = source.lowercased()
    return [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp", ".heic"]
        .contains(where: { lowercased.hasSuffix($0) })
}

nonisolated func resolveRepositoryLinkURL(
    _ source: String,
    owner: String,
    repositoryName: String,
    readmePath: String?
) -> String? {
    let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSource.isEmpty else { return nil }

    if trimmedSource.hasPrefix("http://") || trimmedSource.hasPrefix("https://")
        || trimmedSource.hasPrefix("mailto:") || trimmedSource.hasPrefix("#") {
        return trimmedSource
    }

    return resolveRepositoryAssetURL(
        trimmedSource,
        owner: owner,
        repositoryName: repositoryName,
        readmePath: readmePath
    )
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
    var components = URLComponents()
    components.scheme = "https"
    components.host = "git.sr.ht"
    let encodedOwner = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? owner
    let encodedRepository = repositoryName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repositoryName
    let encodedRelativePath = relativePath
        .split(separator: "/", omittingEmptySubsequences: false)
        .map { segment in
            String(segment).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
        }
        .joined(separator: "/")
    components.percentEncodedPath = "/\(encodedOwner)/\(encodedRepository)/blob/HEAD/\(encodedRelativePath)"
    return components.string
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
    var baseURL: URL? = nil
    var onInterceptURL: ((URL) -> Bool)? = nil
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
                    baseURL: baseURL,
                    onInterceptURL: onInterceptURL,
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
    let baseURL: URL?
    let onInterceptURL: ((URL) -> Bool)?
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
        context.coordinator.parent = self
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
                white-space: pre;
                word-break: normal;
                overflow-wrap: normal;
            }
            img { max-width: 100%; height: auto; }
            svg {
                max-width: 100%;
                height: auto;
            }
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
            blockquote {
                border-left: 3px solid rgba(128, 128, 128, 0.5);
                margin: 0.5em 0;
                padding: 0.25em 0 0.25em 1em;
                color: inherit;
                opacity: 0.85;
            }
            .org-verse {
                white-space: pre-wrap;
            }
            hr {
                border: none;
                border-top: 1px solid rgba(128, 128, 128, 0.35);
                margin: 1em 0;
            }
            table {
                border-collapse: collapse;
                width: 100%;
                margin: 0.75em 0;
                font-size: 0.95em;
            }
            th {
                background: rgba(128, 128, 128, 0.15);
                font-weight: 600;
                text-align: left;
            }
            td, th {
                border: 1px solid rgba(128, 128, 128, 0.3);
                padding: 6px 10px;
            }
            dl.org-properties {
                margin: 0.5em 0;
                display: grid;
                grid-template-columns: max-content 1fr;
                gap: 2px 12px;
            }
            dt {
                font-weight: 600;
                font-family: ui-monospace, Menlo, monospace;
                font-size: 0.9em;
            }
            dd { margin: 0; }
            .org-metadata { margin-bottom: 1em; }
            figure.org-block {
                margin: 0.75em 0;
            }
            figure.org-block figcaption {
                margin-top: 0.4em;
                color: rgba(128, 128, 128, 0.85);
                font-size: 0.9em;
            }
            .btn {
                display: inline-flex;
                align-items: center;
                gap: 0.4em;
            }
            .icon {
                display: inline-flex;
                align-items: center;
                vertical-align: middle;
            }
            .icon svg {
                width: 0.65em;
                height: 0.65em;
                display: block;
                fill: currentColor;
            }
            .org-title { margin: 0 0 0.25em; }
            .org-author, .org-date {
                margin: 0;
                color: rgba(128, 128, 128, 0.85);
                font-size: 0.9em;
            }
            del { opacity: 0.7; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """

        if let cachedHeight = HTMLWebViewCoordinator.heightCache.object(forKey: wrapped as NSString)?.doubleValue {
            let height = CGFloat(cachedHeight)
            if abs(dynamicHeight - height) > 0.5 {
                DispatchQueue.main.async {
                    if abs(self.dynamicHeight - height) > 0.5 {
                        self.dynamicHeight = height
                    }
                }
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
        webView.loadHTMLString(wrapped, baseURL: baseURL)
    }
}

private final class HTMLWebViewCoordinator: NSObject, WKNavigationDelegate, @unchecked Sendable {
    static let websiteDataStore = WKWebsiteDataStore.nonPersistent()
    static let heightCache = NSCache<NSString, NSNumber>()

    var parent: HTMLWebViewRepresentable
    var lastHTML: String?
    var lastReloadToken = 0

    init(parent: HTMLWebViewRepresentable) {
        self.parent = parent
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        DispatchQueue.main.async {
            self.parent.loadError = nil
        }
        updateHeight(for: webView)
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let requestURL = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if navigationAction.navigationType == .linkActivated {
            if isSameDocumentFragmentNavigation(requestURL) {
                decisionHandler(.allow)
                return
            }
            if let intercept = parent.onInterceptURL, intercept(requestURL) {
                decisionHandler(.cancel)
                return
            }
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
        webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
            guard let self else { return }
            guard let heightValue = result as? NSNumber else { return }
            let height = CGFloat(heightValue.doubleValue)
            guard height > 0 else { return }
            let rounded = ceil(height) + 4
            DispatchQueue.main.async {
                if let html = self.lastHTML {
                    Self.heightCache.setObject(NSNumber(value: Double(rounded)), forKey: html as NSString)
                }
                if abs(self.parent.dynamicHeight - rounded) > 0.5 {
                    self.parent.dynamicHeight = rounded
                }
            }
        }
    }

    private func isSameDocumentFragmentNavigation(_ url: URL) -> Bool {
        guard url.fragment != nil,
              let baseURL = parent.baseURL else {
            return false
        }

        guard var destination = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var base = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return false
        }

        destination.fragment = nil
        base.fragment = nil
        return destination.url == base.url
    }
}
