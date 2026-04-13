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

    @Test
    func graphQLErrorUserFacingMessagePreservesValidationDetails() {
        let error = SRHTError.graphQLErrors([
            GraphQLError(message: "A tracker named bugs already exists", locations: nil)
        ])

        #expect(error.userFacingMessage == "A tracker named bugs already exists")
    }

    @Test
    func graphQLErrorUserFacingMessageClassifiesNotFoundResponses() {
        let error = SRHTError.graphQLErrors([
            GraphQLError(message: "reference not found", locations: nil)
        ])

        #expect(error.userFacingMessage == "That content is no longer available.")
        #expect(error.matchesGraphQLErrorClassification(.missingReference))
    }

    @Test
    func graphQLErrorUserFacingMessageClassifiesServiceProvisioningFailures() {
        let error = SRHTError.graphQLErrors([
            GraphQLError(message: "No such repository or user found", locations: nil)
        ])

        #expect(error.userFacingMessage == "That account needs to activate this SourceHut service before this action can succeed.")
        #expect(error.matchesGraphQLErrorClassification(.serviceNotProvisioned))
    }
}
