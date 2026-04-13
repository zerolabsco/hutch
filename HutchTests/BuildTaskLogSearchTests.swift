import Testing
@testable import Hutch

struct BuildTaskLogSearchTests {

    @Test
    func logMatchRangesFindsCaseInsensitiveOccurrences() {
        let matches = logMatchRanges(in: "Error: one\nerror: two\nwarning", query: "ERROR")

        #expect(matches.count == 2)
        #expect(matches[0] == LogTextRange(location: 0, length: 5))
        #expect(matches[1].location > matches[0].location)
    }

    @Test
    func detectLogAnchorsFindsImportantFailureLines() {
        let anchors = detectLogAnchors(in: """
        compile step
        warning: this is fine
        error: missing header
        traceback (most recent call last):
        panic: build failed
        """)

        #expect(anchors.count == 2)
        #expect(anchors[0].lineNumber == 3)
        #expect(anchors[0].label.contains("missing header"))
        #expect(anchors[1].lineNumber == 5)
    }
}
