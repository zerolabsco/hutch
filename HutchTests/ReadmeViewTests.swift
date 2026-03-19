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
