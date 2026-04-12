import Foundation
import Testing
@testable import Hutch

struct SRHTWebURLTests {

    @Test
    func browserOnlyServiceURLsUseCanonicalHosts() {
        #expect(SRHTWebURL.chat.absoluteString == "https://chat.sr.ht")
        #expect(SRHTWebURL.status.absoluteString == "https://status.sr.ht")
    }
}
