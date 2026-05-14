import Foundation
import Testing
@testable import Hutch

struct SourceHutWebDeepLinkMapperTests {
    @Test
    func mapsRepositoryURLs() {
        #expect(mapped("https://git.sr.ht/~ccleberg/Hutch") == "hutch://git/~ccleberg/Hutch")
        #expect(mapped("https://hg.sr.ht/~user/repo") == "hutch://hg/~user/repo")
    }

    @Test
    func mapsTrackerBuildAndListURLs() {
        #expect(mapped("https://todo.sr.ht/~ccleberg/hutch/123") == "hutch://todo/~ccleberg/hutch/123")
        #expect(mapped("https://builds.sr.ht/~ccleberg/job/12345") == "hutch://builds/~ccleberg/job/12345")
        #expect(mapped("https://lists.sr.ht/~ccleberg/hutch-announce") == "hutch://lists/~ccleberg/hutch-announce")
    }

    @Test
    func mapsProfileHostsToLookup() {
        #expect(mapped("https://sr.ht/~ccleberg") == "hutch://lookup/~ccleberg")
        #expect(mapped("https://meta.sr.ht/~ccleberg") == "hutch://lookup/~ccleberg")
        #expect(mapped("https://git.sr.ht/~ccleberg/") == "hutch://lookup/~ccleberg")
        #expect(mapped("https://hg.sr.ht/~user") == "hutch://lookup/~user")
        #expect(mapped("https://todo.sr.ht/~user") == "hutch://lookup/~user")
        #expect(mapped("https://lists.sr.ht/~user") == "hutch://lookup/~user")
        #expect(mapped("https://sr.ht/projects/~user") == "hutch://lookup/~user")
    }

    @Test
    func preservesQueryAndFragment() {
        #expect(mapped("https://git.sr.ht/~ccleberg/Hutch/tree/main/item/README.md?plain=1#L10") == "hutch://git/~ccleberg/Hutch/tree/main/item/README.md?plain=1#L10")
    }

    @Test
    func rejectsUnsupportedHostsAndSchemes() {
        #expect(SourceHutWebDeepLinkMapper.deepLink(for: URL(string: "https://chat.sr.ht")!) == nil)
        #expect(SourceHutWebDeepLinkMapper.deepLink(for: URL(string: "http://git.sr.ht/~ccleberg/Hutch")!) == nil)
    }

    private func mapped(_ string: String) -> String? {
        SourceHutWebDeepLinkMapper.deepLink(for: URL(string: string)!)?.absoluteString
    }
}
