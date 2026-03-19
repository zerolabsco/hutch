import Foundation

/// The JSON body sent with every GraphQL request.
struct GraphQLRequestBody: Encodable, Sendable {
    let query: String
    let variables: [String: AnyCodable]?
}

/// The top-level shape of every GraphQL response.
struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLError]?
}

// MARK: - AnyCodable

/// A type-erased `Codable` wrapper so callers can pass `[String: Any]` variables
/// without losing type information at the encoding boundary.
struct AnyCodable: Sendable, Encodable {
    let value: any Sendable

    init(_ value: any Sendable) {
        self.value = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String:
            try container.encode(v)
        case let v as Int:
            try container.encode(v)
        case let v as Double:
            try container.encode(v)
        case let v as Bool:
            try container.encode(v)
        case let v as [String?]:
            try container.encode(v)
        case let v as [any Sendable]:
            try container.encode(v.map { AnyCodable($0) })
        case let v as [String: any Sendable]:
            try container.encode(v.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
