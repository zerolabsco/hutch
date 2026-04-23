import Foundation
import Testing
@testable import Hutch

private final class SettingsViewModelCapturingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedRequests.append(request)

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // No cleanup is needed because the stub responds immediately in `startLoading()`.
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Self.self]
        return URLSession(configuration: config)
    }
}

private struct DeletePGPKeyEnvelope: Decodable {
    let deletePGPKey: DeleteResultPayload?
}

private struct DeleteResultPayload: Decodable {
    let id: Int?
}

@Suite(.serialized)
struct SettingsViewModelTests {

    @Test
    @MainActor
    func deletePGPKeyResponseDecodesNullPayloadWithGraphQLErrors() throws {
        let json = """
        {
            "errors": [
                {
                    "message": "PGP key ID 13629 is set as the user's preferred PGP key - it must be unset before removing the key"
                }
            ],
            "data": {
                "deletePGPKey": null
            }
        }
        """

        let decoded = try JSONDecoder().decode(
            GraphQLResponse<DeletePGPKeyEnvelope>.self,
            from: Data(json.utf8)
        )

        #expect(decoded.data?.deletePGPKey == nil)
        #expect(decoded.errors?.first?.message.contains("preferred PGP key") == true)
    }

    @Test
    @MainActor
    func loadProfileDoesNotRequestSSHKeyFingerprintField() async throws {
        SettingsViewModelCapturingURLProtocol.capturedRequests = []

        let client = SRHTClient(
            session: SettingsViewModelCapturingURLProtocol.makeSession(),
            token: "test-token"
        )
        let viewModel = SettingsViewModel(client: client)

        await viewModel.loadProfile()

        let request = try #require(SettingsViewModelCapturingURLProtocol.capturedRequests.first)
        let body = try #require(request.httpBody)
        let jsonObject = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let query = try #require(jsonObject["query"] as? String)

        #expect(query.contains("sshKeys"))
        #expect(!query.contains("results { id fingerprint comment created lastUsed }"))
        #expect(!query.contains("fingerprint comment created lastUsed"))
    }
}
