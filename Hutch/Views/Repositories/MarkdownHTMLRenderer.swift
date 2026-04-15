import Markdown

nonisolated func markdownToHTML(
    _ text: String,
    imageURLResolver: ((String) -> String?)? = nil,
    linkURLResolver: ((String) -> String?)? = nil
) -> String {
    let document = Document(parsing: text)
    var renderer = MarkdownHTMLRenderer(imageURLResolver: imageURLResolver, linkURLResolver: linkURLResolver)
    return renderer.visit(document)
}

private struct MarkdownHTMLRenderer: MarkupVisitor {
    typealias Result = String

    nonisolated(unsafe) let imageURLResolver: ((String) -> String?)?
    nonisolated(unsafe) let linkURLResolver: ((String) -> String?)?
    nonisolated(unsafe) private var isRenderingTableHead = false
    nonisolated(unsafe) private var currentTableAlignments: [Markdown.Table.ColumnAlignment?] = []
    nonisolated(unsafe) private var currentTableColumnIndex = 0

    nonisolated init(imageURLResolver: ((String) -> String?)?, linkURLResolver: ((String) -> String?)? = nil) {
        self.imageURLResolver = imageURLResolver
        self.linkURLResolver = linkURLResolver
    }

    nonisolated mutating func visit(_ markup: Markup) -> String {
        markup.accept(&self)
    }

    nonisolated mutating func defaultVisit(_ markup: Markup) -> String {
        visitChildren(of: markup)
    }

    nonisolated mutating func visitDocument(_ document: Document) -> String {
        visitChildren(of: document)
    }

    nonisolated mutating func visitHeading(_ heading: Heading) -> String {
        "<h\(heading.level)>\(visitChildren(of: heading))</h\(heading.level)>\n"
    }

    nonisolated mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(visitChildren(of: paragraph))</p>\n"
    }

    nonisolated mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\n\(visitChildren(of: blockQuote))</blockquote>\n"
    }

    nonisolated mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        "<ul>\n\(visitChildren(of: unorderedList))</ul>\n"
    }

    nonisolated mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        "<ol>\n\(visitChildren(of: orderedList))</ol>\n"
    }

    nonisolated mutating func visitListItem(_ listItem: ListItem) -> String {
        if let checkbox = listItem.checkbox,
           listItem.childCount == 1,
           let paragraph = listItem.child(at: 0) as? Paragraph {
            let content = visitChildren(of: paragraph)
            return "<li><span class=\"task-list-item\">\(checkboxHTML(for: checkbox)) \(content)</span></li>\n"
        }

        var body = visitChildren(of: listItem)
        if let checkbox = listItem.checkbox {
            body = "<span class=\"task-list-item\">\(checkboxHTML(for: checkbox))</span>" + body
        }
        return "<li>\(body)</li>\n"
    }

    nonisolated mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let classAttribute: String
        if let language = codeBlock.language, !language.isEmpty {
            classAttribute = " class=\"language-\(escapeHTMLAttribute(language))\""
        } else {
            classAttribute = ""
        }
        return "<pre><code\(classAttribute)>\(escapeHTML(codeBlock.code))</code></pre>\n"
    }

    nonisolated mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(escapeHTML(inlineCode.code))</code>"
    }

    nonisolated mutating func visitThematicBreak(_: ThematicBreak) -> String {
        "<hr>\n"
    }

    nonisolated mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        guard let sanitized = sanitizedMarkdownHTMLBlock(html.rawHTML) else { return "" }
        return sanitized + "\n"
    }

    nonisolated mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        sanitizedMarkdownHTMLTag(inlineHTML.rawHTML) ?? ""
    }

    nonisolated mutating func visitLink(_ link: Markdown.Link) -> String {
        let content = visitChildren(of: link)
        guard let destination = link.destination else {
            return content
        }
        let resolvedDestination = linkURLResolver?(destination) ?? destination
        guard let sanitizedDestination = sanitizedReadmeLinkURLString(resolvedDestination) else {
            return content
        }
        let href = escapeHTMLAttribute(decodeHTMLEntities(sanitizedDestination))
        return "<a href=\"\(href)\">\(content)</a>"
    }

    nonisolated mutating func visitImage(_ image: Markdown.Image) -> String {
        let altText = plainText(from: image)
        guard let source = image.source, !source.isEmpty else {
            return escapeHTML(altText)
        }

        let resolvedSource = imageURLResolver?(source) ?? source
        guard let sanitizedSource = sanitizedReadmeImageURLString(resolvedSource) else {
            return escapeHTML(altText)
        }

        let src = escapeHTMLAttribute(decodeHTMLEntities(sanitizedSource))
        return "<img src=\"\(src)\" alt=\"\(escapeHTMLAttribute(altText))\">"
    }

    nonisolated mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(visitChildren(of: strong))</strong>"
    }

    nonisolated mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(visitChildren(of: emphasis))</em>"
    }

    nonisolated mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(visitChildren(of: strikethrough))</del>"
    }

    nonisolated mutating func visitText(_ text: Markdown.Text) -> String {
        escapeHTML(text.string)
    }

    nonisolated mutating func visitSoftBreak(_: SoftBreak) -> String {
        " "
    }

    nonisolated mutating func visitLineBreak(_: LineBreak) -> String {
        "<br>"
    }

    nonisolated mutating func visitTable(_ table: Markdown.Table) -> String {
        let previousAlignments = currentTableAlignments
        let previousColumnIndex = currentTableColumnIndex
        currentTableAlignments = table.columnAlignments
        currentTableColumnIndex = 0
        let content = visitChildren(of: table)
        currentTableAlignments = previousAlignments
        currentTableColumnIndex = previousColumnIndex
        return "<table>\n\(content)</table>\n"
    }

    nonisolated mutating func visitTableHead(_ tableHead: Markdown.Table.Head) -> String {
        let previousValue = isRenderingTableHead
        isRenderingTableHead = true
        let content = visitChildren(of: tableHead)
        isRenderingTableHead = previousValue
        return "<thead>\(content)</thead>\n"
    }

    nonisolated mutating func visitTableBody(_ tableBody: Markdown.Table.Body) -> String {
        let previousValue = isRenderingTableHead
        isRenderingTableHead = false
        let content = visitChildren(of: tableBody)
        isRenderingTableHead = previousValue
        return "<tbody>\n\(content)</tbody>\n"
    }

    nonisolated mutating func visitTableRow(_ tableRow: Markdown.Table.Row) -> String {
        let previousColumnIndex = currentTableColumnIndex
        currentTableColumnIndex = 0
        let content = visitChildren(of: tableRow)
        currentTableColumnIndex = previousColumnIndex
        return "<tr>\(content)</tr>\n"
    }

    nonisolated mutating func visitTableCell(_ tableCell: Markdown.Table.Cell) -> String {
        let tagName = isRenderingTableHead ? "th" : "td"
        let styleAttribute = alignmentStyleAttribute(forColumn: currentTableColumnIndex)
        currentTableColumnIndex += 1
        return "<\(tagName)\(styleAttribute)>\(visitChildren(of: tableCell))</\(tagName)>"
    }

    nonisolated private mutating func visitChildren(of markup: Markup) -> String {
        var html = ""
        for child in markup.children {
            html += visit(child)
        }
        return html
    }

    nonisolated private func plainText(from markup: Markup) -> String {
        switch markup {
        case let text as Markdown.Text:
            return text.string
        case let inlineCode as InlineCode:
            return inlineCode.code
        case is SoftBreak:
            return " "
        case is LineBreak:
            return "\n"
        default:
            var text = ""
            for child in markup.children {
                text += plainText(from: child)
            }
            return text
        }
    }

    nonisolated private func alignmentStyleAttribute(forColumn column: Int) -> String {
        guard column < currentTableAlignments.count,
              let alignment = currentTableAlignments[column] else {
            return ""
        }

        let textAlignment: String
        switch alignment {
        case .left:
            textAlignment = "left"
        case .center:
            textAlignment = "center"
        case .right:
            textAlignment = "right"
        }

        return " style=\"text-align: \(textAlignment);\""
    }

    nonisolated private func checkboxHTML(for checkbox: Checkbox) -> String {
        switch checkbox {
        case .checked:
            return "<input type=\"checkbox\" checked disabled>"
        case .unchecked:
            return "<input type=\"checkbox\" disabled>"
        }
    }
}
