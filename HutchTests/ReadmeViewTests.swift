import Foundation
import Testing
@testable import Hutch

struct ReadmeViewTests {

    @Test
    func sanitizedReadmeLinkURLStringRejectsUnexpectedSchemes() {
        #expect(sanitizedReadmeLinkURLString("javascript:alert(1)") == nil)
        #expect(sanitizedReadmeLinkURLString("file:///tmp/readme") == nil)
        #expect(sanitizedReadmeLinkURLString("data:text/html;base64,SGVsbG8=") == nil)
    }

    @Test
    func processInlineDropsUnsafeMarkdownLinks() {
        let rendered = processInline("[click me](javascript:alert)")

        #expect(rendered == "click me")
        #expect(!rendered.contains("href="))
        #expect(!rendered.contains("javascript:"))
    }

    @Test
    func sanitizedReadmeLinkURLStringAllowsExpectedDestinations() {
        #expect(sanitizedReadmeLinkURLString("https://example.com/docs?q=1") == "https://example.com/docs?q=1")
        #expect(sanitizedReadmeLinkURLString("mailto:test@example.com") == "mailto:test@example.com")
        #expect(sanitizedReadmeLinkURLString("#readme") == "#readme")
    }
}

struct MarkdownRenderingTests {

    @Test
    func markdownOrderedList() {
        let html = markdownToHTML("1. First\n2. Second\n3. Third")

        #expect(html.contains("<ol>"))
        #expect(html.contains("<li>First</li>"))
        #expect(html.contains("<li>Third</li>"))
        #expect(html.contains("</ol>"))
    }

    @Test
    func markdownBlockquote() {
        let html = markdownToHTML("> This is a quote")

        #expect(html.contains("<blockquote>"))
        #expect(html.contains("This is a quote"))
        #expect(html.contains("</blockquote>"))
    }

    @Test
    func markdownTable() {
        let input = "| A | B |\n|---|---|\n| 1 | 2 |"
        let html = markdownToHTML(input)

        #expect(html.contains("<table>"))
        #expect(html.contains("<th>"))
        #expect(html.contains("<td>"))
    }

    @Test
    func markdownHorizontalRule() {
        let html = markdownToHTML("---")

        #expect(html.contains("<hr>"))
    }

    @Test
    func markdownDeepHeadings() {
        let html = markdownToHTML("#### Level 4\n##### Level 5\n###### Level 6")

        #expect(html.contains("<h4>"))
        #expect(html.contains("<h5>"))
        #expect(html.contains("<h6>"))
    }

    @Test
    func markdownStrikethrough() {
        let html = markdownToHTML("~~deleted~~")

        #expect(html.contains("<del>deleted</del>"))
    }

    @Test
    func markdownInlineCodeEscaping() {
        let html = processInline("`<b>`")

        #expect(html.contains("<code>"))
        #expect(html.contains("&lt;b&gt;"))
        #expect(!html.contains("<b>"))
    }

    @Test
    func markdownWrappedBulletNormalizesLines() {
        let html = markdownToHTML("- First line\n  continues here")

        #expect(html.contains("<li>First line continues here</li>"))
    }

    @Test
    func markdownPlainEmailAutolinks() {
        let html = processInline("Contact hello@cleberg.net")

        #expect(html.contains(#"href="mailto:hello@cleberg.net""#))
        #expect(html.contains(">hello@cleberg.net</a>"))
    }

    @Test
    func markdownListContinuesAfterCodeBlock() {
        let html = markdownToHTML("""
        1. Clone the repository:
           ```sh
           git clone https://git.sr.ht/~ccleberg/Hutch
           ```
        2. Open the project in Xcode.
        """)

        #expect(html.contains("<ol>"))
        #expect(html.contains("<pre><code>"))
        #expect(html.contains("<li><p>Clone the repository:</p>"))
        #expect(html.contains("<li>Open the project in Xcode.</li>"))
        #expect(html.contains("</ol>"))
    }

    @Test
    func markdownListContinuesAfterBlankLineIndentedCodeBlock() {
        let html = markdownToHTML("""
        1. Clone the repository:

           ```sh
           git clone https://git.sr.ht/~ccleberg/Hutch
           ```

        2. Open the project in Xcode.
        """)

        #expect(html.contains("<li><p>Clone the repository:</p>"))
        #expect(html.contains("<pre><code>git clone https://git.sr.ht/~ccleberg/Hutch</code></pre>"))
        #expect(html.contains("<li>Open the project in Xcode.</li>"))
        #expect(!html.contains("<ol>\n<li>Open the project in Xcode.</li>\n</ol>\n<ol>"))
        #expect(html.firstRange(of: "<p>Clone the repository:</p>")!.lowerBound < html.firstRange(of: "<pre><code>git clone https://git.sr.ht/~ccleberg/Hutch</code></pre>")!.lowerBound)
    }

    @Test
    func markdownImageQueryStringPreservesAmpersands() {
        let html = processInline("![badge](https://sonarcloud.io/api/project_badges/measure?project=ccleberg_Hutch&metric=security_rating)")

        #expect(html.contains("metric=security_rating"))
        #expect(!html.contains("amp;metric"))
        #expect(html.contains("<img"))
    }

    @Test
    func markdownAllowsSafeInlineHTML() {
        let html = processInline(#"<strong>Bold</strong> <a href="https://example.com">Link</a>"#)

        #expect(html.contains("<strong>Bold</strong>"))
        #expect(html.contains(#"<a href="https://example.com">Link</a>"#))
    }

    @Test
    func markdownProtectedTokensDoNotLeak() {
        let html = processInline(#"<a href="https://example.com">Back to top</a> `yoshi [ARG] <FILE>`"#)

        #expect(!html.contains("ZZPROTECTED"))
        #expect(html.contains(#"<a href="https://example.com">Back to top</a>"#))
        #expect(html.contains("<code>yoshi [ARG] &lt;FILE&gt;</code>"))
    }
}

struct OrgRenderingTests {

    @Test
    func orgDeepHeading() {
        let html = orgToHTML("**** Level 4 Heading")

        #expect(html.contains("<h4>"))
    }

    @Test
    func orgCommentLinesIgnored() {
        let html = orgToHTML("# This is a comment\nNormal text")

        #expect(!html.contains("This is a comment"))
        #expect(html.contains("Normal text"))
    }

    @Test
    func orgStrikethrough() {
        let html = orgToHTML("+deleted text+")

        #expect(html.contains("<del>"))
    }

    @Test
    func orgExampleBlock() {
        let html = orgToHTML("#+begin_example\nhello world\n#+end_example")

        #expect(html.contains("<pre><code>"))
        #expect(html.contains("hello world"))
    }

    @Test
    func orgTitleKeyword() {
        let html = orgToHTML("#+TITLE: My Document\nBody text")

        #expect(html.contains("org-title"))
        #expect(html.contains("My Document"))
    }

    @Test
    func orgItalicDoesNotMatchURLPaths() {
        let html = orgToHTML("[[https://example.com/path/to/file]]")

        #expect(!html.contains("<em>"))
    }

    @Test
    func orgWrappedBulletNormalizesLines() {
        let html = orgToHTML("- First line\n  continues here")

        #expect(html.contains("<li>First line continues here</li>"))
    }
}

struct RepositoryAssetURLTests {

    @Test
    func repositoryAssetURLPercentEncodesImagePaths() {
        let url = resolveRepositoryAssetURL(
            "images/My Logo.png",
            owner: "~ccleberg",
            repositoryName: "Hutch",
            readmePath: "README.md"
        )

        #expect(url == "https://git.sr.ht/~ccleberg/Hutch/blob/HEAD/images/My%20Logo.png")
    }
}
