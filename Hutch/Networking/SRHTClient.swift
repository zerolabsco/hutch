import CryptoKit
import Foundation
import os

private let logger = Logger(subsystem: "net.cleberg.Hutch", category: "SRHTClient")

struct MultipartUploadFile: Sendable {
    let variablePath: String
    let fileData: Data
    let fileName: String
    let mimeType: String
}

/// Placeholder type for decoding GraphQL error responses when the data shape is unknown.
private struct EmptyData: Decodable {}

/// A lightweight GraphQL client for SourceHut services.
/// All requests require a personal access token set via ``token``.
final class SRHTClient: Sendable {

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let cache: any APICache
    private let requestCoalescer = RequestCoalescer()

    /// The personal access token used for `Authorization: Bearer` headers.
    /// Loaded from Keychain on init; can be refreshed via ``reloadToken()``.
    private let tokenLock: OSAllocatedUnfairLock<String?>

    /// In-memory response cache for stale-while-revalidate pattern.
    let responseCache = ResponseCache()

    var hasToken: Bool {
        tokenLock.withLock { $0 != nil }
    }

    init(
        session: URLSession = .shared,
        token: String? = nil,
        cache: (any APICache)? = nil
    ) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .srhtFlexible
        self.encoder = JSONEncoder()
        self.tokenLock = OSAllocatedUnfairLock(initialState: token)
        self.cache = cache ?? PersistentAPICache(
            configuration: .accountScoped(accountID: token.map { Self.tokenCacheScope($0) } ?? "anonymous")
        )
    }

    /// Update the stored token (e.g. after the user saves a new one in Keychain).
    func setToken(_ token: String?) {
        tokenLock.withLock { $0 = token }
    }

    /// Execute a GraphQL query or mutation against a SourceHut service.
    ///
    /// - Parameters:
    ///   - service: The target SourceHut service (determines the endpoint URL).
    ///   - query: The GraphQL query or mutation string.
    ///   - variables: Optional dictionary of GraphQL variables.
    ///   - responseType: The expected `Decodable` type nested under `data`.
    /// - Returns: The decoded `data` payload.
    func execute<T: Decodable>(
        service: SRHTService,
        query: String,
        variables: [String: any Sendable]? = nil,
        responseType _: T.Type
    ) async throws -> T {
        let data = try await performGraphQLRequest(service: service, query: query, variables: variables)
        return try decodeGraphQLData(data, service: service, query: query, variables: variables)
    }

    func executeCached<T: Decodable>(
        service: SRHTService,
        query: String,
        variables: [String: any Sendable]? = nil,
        responseType _: T.Type,
        cacheKey: String,
        resourceType: CacheResourceType,
        ttl: TimeInterval,
        policy: CachePolicy = .cacheFirstThenRefresh
    ) async throws -> CachedValue<T> {
        switch policy {
        case .networkOnly:
            let data = try await performGraphQLRequest(
                service: service,
                query: query,
                variables: variables
            )
            let value: T = try decodeGraphQLData(data, service: service, query: query, variables: variables)
            return CachedValue(value: value, metadata: nil, source: .network)

        case .cacheOnly:
            let entry = try await cache.read(cacheKey: cacheKey)
            let value: T = try decodeGraphQLData(entry.payload, service: service, query: query, variables: variables)
            return CachedValue(value: value, metadata: entry.metadata, source: .cache)

        case .cacheFirstThenRefresh:
            if let entry = try? await cache.read(cacheKey: cacheKey) {
                let value: T = try decodeGraphQLData(entry.payload, service: service, query: query, variables: variables)
                if entry.metadata.isExpired() {
                    Task.detached { [self] in
                        _ = try? await self.fetchAndCacheGraphQLData(
                            service: service,
                            query: query,
                            variables: variables,
                            cacheKey: cacheKey,
                            resourceType: resourceType,
                            ttl: ttl
                        )
                    }
                }
                return CachedValue(value: value, metadata: entry.metadata, source: .cache)
            }

            let (value, metadata): (T, CacheEntryMetadata?) = try await fetchAndCacheGraphQL(
                service: service,
                query: query,
                variables: variables,
                cacheKey: cacheKey,
                resourceType: resourceType,
                ttl: ttl
            )
            return CachedValue(value: value, metadata: metadata, source: .network)

        case .refreshIgnoringCache:
            let (value, metadata): (T, CacheEntryMetadata?) = try await fetchAndCacheGraphQL(
                service: service,
                query: query,
                variables: variables,
                cacheKey: cacheKey,
                resourceType: resourceType,
                ttl: ttl
            )
            return CachedValue(value: value, metadata: metadata, source: .network)
        }
    }

    func fetchCachedText(
        url: URL,
        cacheKey: String,
        resourceType: CacheResourceType = .buildLog,
        ttl: TimeInterval,
        policy: CachePolicy = .cacheFirstThenRefresh
    ) async throws -> CachedValue<String> {
        switch policy {
        case .networkOnly:
            let text = try await fetchText(url: url)
            return CachedValue(value: text, metadata: nil, source: .network)
        case .cacheOnly:
            let entry = try await cache.read(cacheKey: cacheKey)
            guard let text = String(data: entry.payload, encoding: .utf8) else {
                throw SRHTError.decodingError(
                    DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Cached text is not UTF-8"))
                )
            }
            return CachedValue(value: text, metadata: entry.metadata, source: .cache)
        case .cacheFirstThenRefresh:
            if let entry = try? await cache.read(cacheKey: cacheKey),
               let text = String(data: entry.payload, encoding: .utf8) {
                if entry.metadata.isExpired() {
                    Task.detached { [self] in
                        _ = try? await self.fetchAndCacheText(url: url, cacheKey: cacheKey, resourceType: resourceType, ttl: ttl)
                    }
                }
                return CachedValue(value: text, metadata: entry.metadata, source: .cache)
            }
            let (text, metadata) = try await fetchAndCacheText(url: url, cacheKey: cacheKey, resourceType: resourceType, ttl: ttl)
            return CachedValue(value: text, metadata: metadata, source: .network)
        case .refreshIgnoringCache:
            let (text, metadata) = try await fetchAndCacheText(url: url, cacheKey: cacheKey, resourceType: resourceType, ttl: ttl)
            return CachedValue(value: text, metadata: metadata, source: .network)
        }
    }

    func cachedPayload(forKey cacheKey: String) async -> Data? {
        if let entry = try? await cache.read(cacheKey: cacheKey) {
            return entry.payload
        }
        return responseCache.get(forKey: cacheKey)
    }

    func invalidateCache(prefix: String) async {
        await cache.removeByPrefix(prefix)
    }

    func removeCachedValue(forKey cacheKey: String) async {
        await cache.remove(cacheKey: cacheKey)
        responseCache.remove(forKey: cacheKey)
    }

    func clearPersistentCache() async {
        await cache.clearAll()
        responseCache.clear()
    }

    // MARK: - Multipart Upload

    /// Execute a GraphQL mutation with a file upload using the
    /// graphql-multipart-request-spec (multipart/form-data).
    ///
    /// - Parameters:
    ///   - service: The target SourceHut service.
    ///   - query: The GraphQL mutation string.
    ///   - variables: Variables dict; the file variable should be set to `nil`.
    ///   - file: Multipart file payload (`variablePath` is the dot-separated GraphQL variable, e.g. `input.avatar`).
    ///   - responseType: The expected `Decodable` type nested under `data`.
    func executeMultipart<T: Decodable>(
        service: SRHTService,
        query: String,
        variables: [String: any Sendable],
        file: MultipartUploadFile,
        responseType _: T.Type
    ) async throws -> T {
        try await executeMultipartFiles(
            service: service,
            query: query,
            variables: variables,
            files: [file],
            responseType: T.self
        )
    }

    func executeMultipartFiles<T: Decodable>(
        service: SRHTService,
        query: String,
        variables: [String: any Sendable],
        files: [MultipartUploadFile],
        responseType _: T.Type
    ) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try makeAuthorizedRequest(
            service: service,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )

        let operationsData = try encodedGraphQLBody(query: query, variables: variables)

        let mapDict = Dictionary(uniqueKeysWithValues: files.enumerated().map { index, file in
            (String(index), ["variables.\(file.variablePath)"])
        })
        let mapData = try encoder.encode(mapDict)

        var body = Data()

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"operations\"\r\n")
        body.append("Content-Type: application/json\r\n\r\n")
        body.append(operationsData)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"map\"\r\n")
        body.append("Content-Type: application/json\r\n\r\n")
        body.append(mapData)
        body.append("\r\n")

        for (index, file) in files.enumerated() {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(index)\"; filename=\"\(file.fileName)\"\r\n")
            body.append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.fileData)
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")
        request.httpBody = body

        let data = try await send(request)
        return try decodeGraphQLData(data, service: service, query: query, variables: variables)
    }


    // MARK: - Plain-text fetch

    /// Fetch the contents of a URL as plain text, using the same authorization header.
    /// Used for build logs and other non-GraphQL resources.
    func fetchText(url: URL) async throws -> String {
        guard let token = tokenLock.withLock({ $0 }), !token.isEmpty else {
            throw SRHTError.unauthorized
        }
        guard Self.isTrustedAuthenticatedTextURL(url) else {
            throw SRHTError.invalidAuthenticatedURL(url)
        }

        var request = URLRequest(url: url)
        request.setValue(Bundle.main.hutchUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SRHTError.networkError(error)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                throw SRHTError.unauthorized
            }
            if !(200...299).contains(http.statusCode) {
                throw SRHTError.httpError(http.statusCode)
            }
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw SRHTError.decodingError(
                DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Response is not UTF-8 text"))
            )
        }

        return text
    }

    // MARK: - Pagination

    /// Returns an `AsyncSequence` that lazily iterates through all pages of a
    /// paginated sr.ht GraphQL query.
    ///
    /// The query must accept a `$cursor: String` variable and return the standard
    /// `{ results: [T], cursor: String? }` shape at the given key path.
    func paginated<T: Decodable & Sendable>(
        service: SRHTService,
        query: String,
        variables: [String: any Sendable]? = nil,
        resultKeyPath: String
    ) -> SRHTPaginatedSequence<T> {
        SRHTPaginatedSequence(
            client: self,
            service: service,
            query: query,
            variables: variables,
            resultKeyPath: resultKeyPath
        )
    }

    /// Fetches all pages of a paginated sr.ht GraphQL query and returns the
    /// collected results.
    func fetchAll<T: Decodable & Sendable>(
        service: SRHTService,
        query: String,
        variables: [String: any Sendable]? = nil,
        resultKeyPath: String
    ) async throws -> [T] {
        var all: [T] = []
        let pages: SRHTPaginatedSequence<T> = paginated(
            service: service,
            query: query,
            variables: variables,
            resultKeyPath: resultKeyPath
        )
        for try await element in pages {
            all.append(element)
        }
        return all
    }
}

// MARK: - Data Helper

private extension SRHTClient {
    /// Builds an authorized POST for `service`. Throws ``SRHTError/unauthorized``
    /// when no token is set, so callers never have to guard separately.
    func makeAuthorizedRequest(service: SRHTService, contentType: String) throws -> URLRequest {
        guard let token = tokenLock.withLock({ $0 }), !token.isEmpty else {
            throw SRHTError.unauthorized
        }

        var request = URLRequest(url: service.url)
        request.httpMethod = "POST"
        request.setValue(Bundle.main.hutchUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Sends a prepared request and returns the raw body, mapping transport and
    /// HTTP failures onto ``SRHTError``. sr.ht reports GraphQL errors under a 200
    /// as often as under a 4xx, so both paths check the envelope.
    func send(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SRHTError.networkError(error)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                throw SRHTError.unauthorized
            }
            if !(200...299).contains(http.statusCode) {
                try throwGraphQLErrorsIfPresent(in: data)
                throw SRHTError.httpError(http.statusCode)
            }
        }

        try throwGraphQLErrorsIfPresent(in: data)
        return data
    }

    func encodedGraphQLBody(query: String, variables: [String: any Sendable]?) throws -> Data {
        try encoder.encode(
            GraphQLRequestBody(
                query: query,
                variables: variables?.mapValues { AnyCodable($0) }
            )
        )
    }

    func performGraphQLRequest(
        service: SRHTService,
        query: String,
        variables: [String: any Sendable]?
    ) async throws -> Data {
        var request = try makeAuthorizedRequest(service: service, contentType: "application/json")
        request.httpBody = try encodedGraphQLBody(query: query, variables: variables)
        return try await send(request)
    }

    func decodeGraphQLData<T: Decodable>(
        _ data: Data,
        service: SRHTService,
        query: String,
        variables: [String: any Sendable]?
    ) throws -> T {
        let graphQLResponse: GraphQLResponse<T>
        do {
            graphQLResponse = try decoder.decode(GraphQLResponse<T>.self, from: data)
        } catch {
            #if DEBUG
            let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
            logger.error(
                """
                Decoding failed for \(String(describing: T.self), privacy: .public)
                service: \(service.rawValue, privacy: .public)
                query:
                \(query, privacy: .public)
                variables:
                \(String(describing: variables), privacy: .public)
                error:
                \(String(describing: error), privacy: .public)
                response:
                \(responseBody, privacy: .public)
                """
            )
            #endif
            throw SRHTError.decodingError(error)
        }

        if let errors = graphQLResponse.errors, !errors.isEmpty {
            throw SRHTError.graphQLErrors(errors)
        }

        guard let result = graphQLResponse.data else {
            throw SRHTError.decodingError(
                DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "No data in response"))
            )
        }
        return result
    }

    func fetchAndCacheGraphQL<T: Decodable>(
        service: SRHTService,
        query: String,
        variables: [String: any Sendable]?,
        cacheKey: String,
        resourceType: CacheResourceType,
        ttl: TimeInterval
    ) async throws -> (T, CacheEntryMetadata?) {
        let data = try await requestCoalescer.value(for: cacheKey) {
            try await self.performGraphQLRequest(service: service, query: query, variables: variables)
        }
        let value: T = try decodeGraphQLData(data, service: service, query: query, variables: variables)
        responseCache.set(data, forKey: cacheKey)
        let metadata = try? await cache.write(payload: data, cacheKey: cacheKey, resourceType: resourceType, ttl: ttl)
        return (value, metadata)
    }

    func fetchAndCacheGraphQLData(
        service: SRHTService,
        query: String,
        variables: [String: any Sendable]?,
        cacheKey: String,
        resourceType: CacheResourceType,
        ttl: TimeInterval
    ) async throws -> CacheEntryMetadata? {
        let data = try await requestCoalescer.value(for: cacheKey) {
            try await self.performGraphQLRequest(service: service, query: query, variables: variables)
        }
        responseCache.set(data, forKey: cacheKey)
        return try? await cache.write(payload: data, cacheKey: cacheKey, resourceType: resourceType, ttl: ttl)
    }

    func fetchAndCacheText(
        url: URL,
        cacheKey: String,
        resourceType: CacheResourceType,
        ttl: TimeInterval
    ) async throws -> (String, CacheEntryMetadata?) {
        let data = try await requestCoalescer.value(for: cacheKey) {
            let text = try await self.fetchText(url: url)
            guard let data = text.data(using: .utf8) else {
                throw SRHTError.decodingError(
                    DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Text could not be encoded as UTF-8"))
                )
            }
            return data
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw SRHTError.decodingError(
                DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Response is not UTF-8 text"))
            )
        }
        responseCache.set(data, forKey: cacheKey)
        let metadata = try? await cache.write(payload: data, cacheKey: cacheKey, resourceType: resourceType, ttl: ttl)
        return (text, metadata)
    }

    static func tokenCacheScope(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func throwGraphQLErrorsIfPresent(in data: Data) throws {
        if let envelope = try? decoder.decode(GraphQLResponse<EmptyData>.self, from: data),
           let errors = envelope.errors,
           !errors.isEmpty {
            throw SRHTError.graphQLErrors(errors)
        }
    }

    static func isTrustedAuthenticatedTextURL(_ url: URL) -> Bool {
        guard url.scheme?.localizedCaseInsensitiveCompare("https") == .orderedSame,
              let host = url.host?.lowercased() else {
            return false
        }

        return host.hasSuffix(".sr.ht")
    }
}

private actor RequestCoalescer {
    private var tasks: [String: Task<Data, Error>] = [:]

    func value(for key: String, operation: @Sendable @escaping () async throws -> Data) async throws -> Data {
        if let task = tasks[key] {
            return try await task.value
        }

        let task = Task {
            try await operation()
        }
        tasks[key] = task
        defer { tasks.removeValue(forKey: key) }
        return try await task.value
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
