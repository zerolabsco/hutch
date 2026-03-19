import Foundation
import Testing
@testable import Hutch

struct SettingsViewTests {

    @Test
    @MainActor
    func settingsBioAttributedStringPreservesInlineMarkdown() {
        let attributed = settingsBioAttributedString("Hello **world** and [link](https://example.com)")

        #expect(String(attributed.characters).contains("Hello world and link"))
    }

    @Test
    @MainActor
    func settingsBioAttributedStringFallsBackForInvalidMarkdown() {
        let attributed = settingsBioAttributedString("[broken")

        #expect(String(attributed.characters) == "[broken")
    }
}
