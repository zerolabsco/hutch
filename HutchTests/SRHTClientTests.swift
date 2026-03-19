import Foundation
import Testing
@testable import Hutch

struct SRHTClientTests {

    @Test
    @MainActor
    func fetchTextRejectsUnexpectedAuthenticatedURL() async throws {
        let client = SRHTClient(token: "test-token")
        let url = try #require(URL(string: "https://example.com/build-log"))

        do {
            _ = try await client.fetchText(url: url)
            Issue.record("Expected fetchText(url:) to reject non-sr.ht URLs.")
        } catch let error as SRHTError {
            guard case .invalidAuthenticatedURL(let rejectedURL) = error else {
                Issue.record("Expected invalidAuthenticatedURL error, got \(error).")
                return
            }

            #expect(rejectedURL == url)
        } catch {
            Issue.record("Expected SRHTError.invalidAuthenticatedURL, got \(error).")
        }
    }
}
