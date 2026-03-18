import Foundation

/// The standard paginated response shape used by all sr.ht GraphQL APIs.
///   { results: [T], cursor: String? }
/// A null cursor means the list is exhausted.
struct CursorPage<Element: Decodable & Sendable>: Decodable, Sendable {
    let results: [Element]
    let cursor: String?
}

/// An `AsyncSequence` that lazily fetches pages from a paginated sr.ht GraphQL
/// query. Each element yielded is a single `Element` from the `results` array.
///
/// The sequence re-issues the query with an updated `$cursor` variable on each
/// page until the server returns a null cursor.
///
/// Usage:
/// ```swift
/// let sequence = SRHTPaginatedSequence<Repository>(
///     client: client,
///     service: .git,
///     query: "query($cursor: String) { me { repositories(cursor: $cursor) { results { id name } cursor } } }",
///     variables: nil,
///     resultKeyPath: "me.repositories"
/// )
/// for try await repo in sequence {
///     print(repo.name)
/// }
/// ```
struct SRHTPaginatedSequence<Element: Decodable & Sendable>: AsyncSequence, Sendable {
    let client: SRHTClient
    let service: SRHTService
    let query: String
    let variables: [String: any Sendable]?
    let resultKeyPath: String

    func makeAsyncIterator() -> Iterator {
        Iterator(
            client: client,
            service: service,
            query: query,
            variables: variables,
            resultKeyPath: resultKeyPath
        )
    }

    struct Iterator: AsyncIteratorProtocol {
        private let client: SRHTClient
        private let service: SRHTService
        private let query: String
        private let baseVariables: [String: any Sendable]?
        private let resultKeyPath: String

        /// Buffer of elements from the current page.
        private var buffer: [Element] = []
        /// Index into the current buffer.
        private var bufferIndex = 0
        /// The cursor for the next page. Nil means we haven't started or are done.
        private var nextCursor: String? = nil
        /// Whether we've exhausted all pages.
        private var isFinished = false

        init(
            client: SRHTClient,
            service: SRHTService,
            query: String,
            variables: [String: any Sendable]?,
            resultKeyPath: String
        ) {
            self.client = client
            self.service = service
            self.query = query
            self.baseVariables = variables
            self.resultKeyPath = resultKeyPath
        }

        mutating func next() async throws -> Element? {
            // Yield buffered elements first.
            if bufferIndex < buffer.count {
                let element = buffer[bufferIndex]
                bufferIndex += 1
                return element
            }

            // If we already know there are no more pages, stop.
            if isFinished {
                return nil
            }

            // Fetch the next page.
            var vars = baseVariables ?? [:]
            if let cursor = nextCursor {
                vars["cursor"] = cursor
            }

            let page = try await fetchPage(variables: vars)

            if let cursor = page.cursor {
                nextCursor = cursor
            } else {
                isFinished = true
            }

            buffer = page.results
            bufferIndex = 0

            guard bufferIndex < buffer.count else {
                return nil
            }

            let element = buffer[bufferIndex]
            bufferIndex += 1
            return element
        }

        private func fetchPage(variables: [String: any Sendable]) async throws -> CursorPage<Element> {
            // We decode the raw JSON and navigate the key path manually,
            // since the paginated object can be nested arbitrarily
            // (e.g. "me.repositories" or just "repositories").
            let raw = try await client.execute(
                service: service,
                query: query,
                variables: variables.isEmpty ? nil : variables,
                responseType: RawJSON.self
            )

            // Walk the key path to find the paginated object.
            let pathComponents = resultKeyPath.split(separator: ".").map(String.init)
            var current = raw.value
            for component in pathComponents {
                guard let dict = current as? [String: Any],
                      let next = dict[component] else {
                    throw SRHTError.decodingError(
                        DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing key path: \(resultKeyPath)"))
                    )
                }
                current = next
            }

            // Re-serialize the nested object and decode as CursorPage<Element>.
            let pageData = try JSONSerialization.data(withJSONObject: current)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(.srht)
            return try decoder.decode(CursorPage<Element>.self, from: pageData)
        }
    }
}

// MARK: - RawJSON

/// A Decodable wrapper that preserves the raw JSON structure as Foundation objects
/// so we can navigate dynamic key paths at runtime.
struct RawJSON: Decodable, Sendable {
    let value: Any

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: RawJSON].self) {
            value = dict.mapValues(\.value)
        } else if let array = try? container.decode([RawJSON].self) {
            value = array.map(\.value)
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }
}
