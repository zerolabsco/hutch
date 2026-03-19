import Foundation
import Testing
@testable import Hutch

private struct DeletePGPKeyEnvelope: Decodable {
    let deletePGPKey: DeleteResultPayload?
}

private struct DeleteResultPayload: Decodable {
    let id: Int?
}

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
}
