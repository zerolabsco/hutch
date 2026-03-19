import Foundation
import Testing
@testable import Hutch

struct GitObjectTests {

    @Test
    @MainActor
    func decodesMetadataOnlyTextBlobUsingTypename() throws {
        let data = Data(#"{"type":"BLOB","__typename":"TextBlob","id":"blob123","shortId":"blob123","size":42}"#.utf8)

        let blob = try JSONDecoder().decode(GitObject.self, from: data)

        guard case .textBlob(let textBlob) = blob else {
            Issue.record("Expected metadata-only blob to decode as text blob.")
            return
        }

        #expect(textBlob.id == "blob123")
        #expect(textBlob.size == 42)
        #expect(textBlob.text == nil)
    }

    @Test
    @MainActor
    func decodesMetadataOnlyBinaryBlobUsingTypename() throws {
        let data = Data(#"{"type":"BLOB","__typename":"BinaryBlob","id":"blob456","shortId":"blob456","size":64}"#.utf8)

        let blob = try JSONDecoder().decode(GitObject.self, from: data)

        guard case .binaryBlob(let binaryBlob) = blob else {
            Issue.record("Expected metadata-only blob to decode as binary blob.")
            return
        }

        #expect(binaryBlob.id == "blob456")
        #expect(binaryBlob.size == 64)
        #expect(binaryBlob.content == nil)
    }
}
