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
        let html = markdownToHTML("1. First\n2. Second")

        #expect(html.contains("<ol>"))
        #expect(html.contains("<li>"))
    }

    @Test
    func markdownBlockquote() {
        let html = markdownToHTML("> This is a quote")

        #expect(html.contains("<blockquote>"))
    }

    @Test
    func markdownTable() {
        let input = "| A | B |\n|---|---|\n| 1 | 2 |"
        let html = markdownToHTML(input)

        #expect(html.contains("<table>"))
        #expect(html.contains("<th>"))
    }

    @Test
    func markdownTableAlignment() {
        let input = "| Left | Center | Right |\n|:-----|:------:|------:|\n| a | b | c |"
        let html = markdownToHTML(input)

        #expect(html.contains("text-align: left;"))
        #expect(html.contains("text-align: center;"))
        #expect(html.contains("text-align: right;"))
    }

    @Test
    func markdownStrikethrough() {
        let html = markdownToHTML("~~deleted~~")

        #expect(html.contains("<del>"))
    }

    @Test
    func markdownDeepHeadings() {
        let html = markdownToHTML("#### Level 4")

        #expect(html.contains("<h4>"))
    }

    @Test
    func markdownHardWrapNormalization() {
        let html = markdownToHTML("line one\nline two")

        #expect(!html.contains("line one\nline two"))
        #expect(html.contains("line one"))
        #expect(html.contains("line two"))
    }

    @Test
    func markdownSoftBreakIsSpace() {
        let html = markdownToHTML("word one\nword two")

        #expect(html.contains("word one word two") || (html.contains("word one") && html.contains("word two")))
        #expect(!html.contains("<br>"))
    }

    @Test
    func markdownUnsafeLinkDropped() {
        let html = markdownToHTML("[click](javascript:alert(1))")

        #expect(!html.contains("href="))
        #expect(!html.contains("javascript:"))
    }

    @Test
    func markdownRelativeLinkWithoutResolverDropped() {
        let html = markdownToHTML("[LICENSE](LICENSE)")

        #expect(!html.contains("href="))
        #expect(html.contains("LICENSE"))
    }

    @Test
    func markdownRelativeLinkWithResolverRendersAnchor() {
        let html = markdownToHTML(
            "[LICENSE](LICENSE)",
            linkURLResolver: { source in
                source == "LICENSE" ? "https://git.sr.ht/~ccleberg/Hutch/blob/HEAD/LICENSE" : nil
            }
        )

        #expect(html.contains(#"href="https://git.sr.ht/~ccleberg/Hutch/blob/HEAD/LICENSE""#))
        #expect(html.contains(">LICENSE</a>"))
    }

    @Test
    func markdownFragmentLinkWithResolverPreservesFragment() {
        let html = markdownToHTML(
            "[section](#install)",
            linkURLResolver: { source in
                resolveRepositoryLinkURL(
                    source,
                    owner: "~ccleberg",
                    repositoryName: "Hutch",
                    readmePath: "README.md"
                )
            }
        )

        #expect(html.contains("href=\"#install\""))
    }

    @Test
    func markdownImageRenders() {
        let html = markdownToHTML("![logo](https://example.com/logo.png)")

        #expect(html.contains("<img src=\"https://example.com/logo.png\" alt=\"logo\">"))
        #expect(!html.contains(#"\"#))
    }

    @Test
    func markdownLinkedImageRendersAnchor() {
        let html = markdownToHTML("[![badge](https://example.com/badge.png)](https://example.com/build)")

        #expect(html.contains("<a href=\"https://example.com/build\">"))
        #expect(html.contains("<img src=\"https://example.com/badge.png\" alt=\"badge\">"))
        #expect(!html.contains(#"\"#))
    }

    @Test
    func markdownInlineCodeEscaping() {
        let html = processInline("`<b>`")

        #expect(html.contains("<code>"))
        #expect(html.contains("&lt;b&gt;"))
        #expect(!html.contains("<b>"))
    }

    @Test
    func markdownPlainEmailAutolinks() {
        let html = processInline("Contact hello@cleberg.net")

        #expect(html.contains(#"href="mailto:hello@cleberg.net""#))
        #expect(html.contains(">hello@cleberg.net</a>"))
    }

    @Test
    func markdownImageQueryStringPreservesAmpersands() {
        let html = processInline("![badge](https://sonarcloud.io/api/project_badges/measure?project=ccleberg_Hutch&metric=security_rating)")

        #expect(html.contains("metric=security_rating"))
        #expect(!html.contains("amp;metric"))
        #expect(html.contains("<img"))
    }

    @Test
    func markdownLinkedImagesWithQueryStringsRenderAllImages() {
        let html = markdownToHTML("""
        [![builds.sr.ht status](https://builds.sr.ht/~ccleberg/Hutch.svg)](https://builds.sr.ht/~ccleberg/Hutch?)
        [![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=ccleberg_Hutch&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=ccleberg_Hutch)
        [![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=ccleberg_Hutch&metric=reliability_rating)](https://sonarcloud.io/summary/new_code?id=ccleberg_Hutch)
        """)

        #expect(html.contains("Hutch.svg"))
        #expect(html.contains("metric=security_rating"))
        #expect(html.contains("metric=reliability_rating"))
        #expect(!html.contains("amp;amp;"))
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

    @Test
    func orgHeaderKeywordsIgnored() {
        let html = orgToHTML("""
        #+OPTIONS: toc:nil
        #+PROPERTY: header-args :results output
        Body text
        """)

        #expect(!html.contains("#+OPTIONS"))
        #expect(!html.contains("#+PROPERTY"))
        #expect(html.contains("<p>Body text</p>"))
    }

    @Test
    func orgVerseBlock() {
        let html = orgToHTML("""
        #+begin_verse
        There is a line.
          And an indented line.
        #+end_verse
        """)

        #expect(html.contains(#"<blockquote class="org-verse">"#))
        #expect(html.contains("There is a line."))
        #expect(html.contains("And an indented line."))
        #expect(!html.contains("#+begin_verse"))
    }

    @Test
    func orgNamedBlockRendersCaption() {
        let html = orgToHTML("""
        #+CAPTION: Build output
        #+NAME: build-log
        #+begin_example
        hello world
        #+end_example
        """)

        #expect(html.contains(#"<figure class="org-block" id="build-log">"#))
        #expect(html.contains("<figcaption>Build output</figcaption>"))
        #expect(!html.contains("#+CAPTION"))
        #expect(!html.contains("#+NAME"))
    }

    @Test
    func orgLinkedImageRenders() {
        let html = orgToHTML("[[https://example.com][[https://img.cleberg.net/apps/hutch/screenshots/ipad/01_patch.jpg]]]")

        #expect(html.contains(#"<a href="https://example.com">"#))
        #expect(html.contains(#"<img src="https://img.cleberg.net/apps/hutch/screenshots/ipad/01_patch.jpg" alt="">"#))
    }

    @Test
    func orgLinkedRelativeImageRenders() {
        let html = orgToHTML(
            "[[https://example.com/docs][[./images/badge.svg]]]",
            imageURLResolver: { source in
                source == "./images/badge.svg" ? "https://git.sr.ht/~ccleberg/Hutch/blob/HEAD/images/badge.svg" : nil
            }
        )

        #expect(html.contains(#"<a href="https://example.com/docs">"#))
        #expect(html.contains(#"<img src="https://git.sr.ht/~ccleberg/Hutch/blob/HEAD/images/badge.svg" alt="">"#))
    }

    @Test
    func orgNestedBulletListRendersNestedMarkup() {
        let html = orgToHTML("""
        * Lists
        ** Unordered
        - First bullet
        - Second bullet
        - Third bullet with /italic/ and *bold*
        - Bullet with wrapped
          continuation line
        - Bullet with nested list
          - Nested child one
          - Nested child two
        - Bullet with inline code ~let x = 1~
        """)

        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>Bullet with nested list\n<ul>"))
        #expect(html.contains("<li>Nested child one</li>"))
        #expect(html.contains("<li>Nested child two</li>"))
        #expect(html.contains("<li>Bullet with wrapped continuation line</li>"))
    }

    @Test
    func orgTableAlignmentRendersStyles() {
        let html = orgToHTML("""
        | Left | Center | Right |
        |:-----+:-----:+------:|
        | a    | b      | c     |
        | 1    | 2      | 3     |
        """)

        #expect(html.contains("text-align: left;"))
        #expect(html.contains("text-align: center;"))
        #expect(html.contains("text-align: right;"))
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

struct RepositoryLinkURLTests {

    @Test
    func repositoryLinkURLResolvesRelativePath() {
        let url = resolveRepositoryLinkURL(
            "LICENSE",
            owner: "~ccleberg",
            repositoryName: "Hutch",
            readmePath: "README.md"
        )

        #expect(url == "https://git.sr.ht/~ccleberg/Hutch/blob/HEAD/LICENSE")
    }

    @Test
    func repositoryLinkURLPassesThroughAbsoluteURL() {
        let url = resolveRepositoryLinkURL(
            "https://example.com/page",
            owner: "~ccleberg",
            repositoryName: "Hutch",
            readmePath: "README.md"
        )

        #expect(url == "https://example.com/page")
    }

    @Test
    func repositoryLinkURLPassesThroughFragment() {
        let url = resolveRepositoryLinkURL(
            "#install",
            owner: "~ccleberg",
            repositoryName: "Hutch",
            readmePath: "README.md"
        )

        #expect(url == "#install")
    }

    @Test
    func repositoryLinkURLPassesThroughMailto() {
        let url = resolveRepositoryLinkURL(
            "mailto:hello@example.com",
            owner: "~ccleberg",
            repositoryName: "Hutch",
            readmePath: "README.md"
        )

        #expect(url == "mailto:hello@example.com")
    }

    @Test
    func repositoryLinkURLResolvesSubdirectoryRelativePath() {
        let url = resolveRepositoryLinkURL(
            "docs/SECURITY.md",
            owner: "~ccleberg",
            repositoryName: "Hutch",
            readmePath: "README.md"
        )

        #expect(url == "https://git.sr.ht/~ccleberg/Hutch/blob/HEAD/docs/SECURITY.md")
    }
}
