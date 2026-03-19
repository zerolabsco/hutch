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

/// A lightweight GraphQL client for Sourcehut services.
/// All requests require a personal access token set via ``token``.
final class SRHTClient: Sendable {

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// The personal access token used for `Authorization: Bearer` headers.
    /// Loaded from Keychain on init; can be refreshed via ``reloadToken()``.
    private let _token: OSAllocatedUnfairLock<String?>

    /// In-memory response cache for stale-while-revalidate pattern.
    let responseCache = ResponseCache()

    var hasToken: Bool {
        _token.withLock { $0 != nil }
    }

    init(session: URLSession = .shared, token: String? = nil) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .srhtFlexible
        self.encoder = JSONEncoder()
        self._token = OSAllocatedUnfairLock(initialState: token)
    }

    /// Update the stored token (e.g. after the user saves a new one in Keychain).
    func setToken(_ token: String?) {
        _token.withLock { $0 = token }
    }

    /// Execute a GraphQL query or mutation against a Sourcehut service.
    ///
    /// - Parameters:
    ///   - service: The target Sourcehut service (determines the endpoint URL).
    ///   - query: The GraphQL query or mutation string.
    ///   - variables: Optional dictionary of GraphQL variables.
    ///   - responseType: The expected `Decodable` type nested under `data`.
    /// - Returns: The decoded `data` payload.
    func execute<T: Decodable>(
        service: SRHTService,
        query: String,
        variables: [String: any Sendable]? = nil,
        responseType: T.Type
    ) async throws -> T {
        guard let token = _token.withLock({ $0 }), !token.isEmpty else {
            throw SRHTError.unauthorized
        }

        // Build request
        var request = URLRequest(url: service.url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GraphQLRequestBody(
            query: query,
            variables: variables?.mapValues { AnyCodable($0) }
        )
        request.httpBody = try encoder.encode(body)

        // Execute
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SRHTError.networkError(error)
        }

        // Check HTTP status
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                throw SRHTError.unauthorized
            }
            if !(200...299).contains(http.statusCode) {
                // Try to extract GraphQL errors from the response body even on non-2xx
                if let gqlResponse = try? decoder.decode(GraphQLResponse<EmptyData>.self, from: data),
                   let errors = gqlResponse.errors, !errors.isEmpty {
                    throw SRHTError.graphQLErrors(errors)
                }
                throw SRHTError.httpError(http.statusCode)
            }
        }

        // Decode GraphQL response envelope
        let graphQLResponse: GraphQLResponse<T>
        do {
            graphQLResponse = try decoder.decode(GraphQLResponse<T>.self, from: data)
        } catch {
            #if DEBUG
            let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
            let variablesDescription = String(describing: variables)
            if let decodingError = error as? DecodingError {
                logger.error(
                    """
                    Decoding failed for \(String(describing: T.self), privacy: .public)
                    service: \(service.rawValue, privacy: .public)
                    query:
                    \(query, privacy: .public)
                    variables:
                    \(variablesDescription, privacy: .public)
                    decodingError:
                    \(String(describing: decodingError), privacy: .public)
                    response:
                    \(responseBody, privacy: .public)
                    """
                )
            } else {
                logger.error(
                    """
                    Decoding failed for \(String(describing: T.self), privacy: .public)
                    service: \(service.rawValue, privacy: .public)
                    query:
                    \(query, privacy: .public)
                    variables:
                    \(variablesDescription, privacy: .public)
                    error:
                    \(String(describing: error), privacy: .public)
                    response:
                    \(responseBody, privacy: .public)
                    """
                )
            }
            #else
            logger.error("Decoding failed for \(String(describing: T.self), privacy: .public): \(error, privacy: .public)")
            #endif
            throw SRHTError.decodingError(error)
        }

        // Surface GraphQL-level errors
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

    // MARK: - Multipart Upload

    /// Execute a GraphQL mutation with a file upload using the
    /// graphql-multipart-request-spec (multipart/form-data).
    ///
    /// - Parameters:
    ///   - service: The target Sourcehut service.
    ///   - query: The GraphQL mutation string.
    ///   - variables: Variables dict; the file variable should be set to `nil`.
    ///   - fileVariablePath: The dot-separated path to the file variable (e.g. "input.avatar").
    ///   - fileData: The raw file data (e.g. JPEG).
    ///   - fileName: The file name to send (e.g. "avatar.jpg").
    ///   - mimeType: The MIME type (e.g. "image/jpeg").
    ///   - responseType: The expected `Decodable` type nested under `data`.
    func executeMultipart<T: Decodable>(
        service: SRHTService,
        query: String,
        variables: [String: any Sendable],
        fileVariablePath: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        responseType: T.Type
    ) async throws -> T {
        guard let token = _token.withLock({ $0 }), !token.isEmpty else {
            throw SRHTError.unauthorized
        }

        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: service.url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build the operations JSON (file variable mapped to null)
        let operationsBody = GraphQLRequestBody(
            query: query,
            variables: variables.mapValues { AnyCodable($0) }
        )
        let operationsData = try encoder.encode(operationsBody)

        // Build the map JSON: { "0": ["variables.<fileVariablePath>"] }
        let mapDict = ["0": ["variables.\(fileVariablePath)"]]
        let mapData = try encoder.encode(mapDict)

        // Assemble multipart body
        var body = Data()

        // Part: operations
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"operations\"\r\n")
        body.append("Content-Type: application/json\r\n\r\n")
        body.append(operationsData)
        body.append("\r\n")

        // Part: map
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"map\"\r\n")
        body.append("Content-Type: application/json\r\n\r\n")
        body.append(mapData)
        body.append("\r\n")

        // Part: file
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"0\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n")

        // Closing boundary
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

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

        let graphQLResponse: GraphQLResponse<T>
        do {
            graphQLResponse = try decoder.decode(GraphQLResponse<T>.self, from: data)
        } catch {
            #if DEBUG
            let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
            let variablesDescription = String(describing: variables)
            if let decodingError = error as? DecodingError {
                logger.error(
                    """
                    Decoding failed for \(String(describing: T.self), privacy: .public)
                    service: \(service.rawValue, privacy: .public)
                    query:
                    \(query, privacy: .public)
                    variables:
                    \(variablesDescription, privacy: .public)
                    decodingError:
                    \(String(describing: decodingError), privacy: .public)
                    response:
                    \(responseBody, privacy: .public)
                    """
                )
            } else {
                logger.error(
                    """
                    Decoding failed for \(String(describing: T.self), privacy: .public)
                    service: \(service.rawValue, privacy: .public)
                    query:
                    \(query, privacy: .public)
                    variables:
                    \(variablesDescription, privacy: .public)
                    error:
                    \(String(describing: error), privacy: .public)
                    response:
                    \(responseBody, privacy: .public)
                    """
                )
            }
            #else
            logger.error("Decoding failed for \(String(describing: T.self), privacy: .public): \(error, privacy: .public)")
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

    func executeMultipartFiles<T: Decodable>(
        service: SRHTService,
        query: String,
        variables: [String: any Sendable],
        files: [MultipartUploadFile],
        responseType: T.Type
    ) async throws -> T {
        guard let token = _token.withLock({ $0 }), !token.isEmpty else {
            throw SRHTError.unauthorized
        }

        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: service.url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let operationsBody = GraphQLRequestBody(
            query: query,
            variables: variables.mapValues { AnyCodable($0) }
        )
        let operationsData = try encoder.encode(operationsBody)

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
                if let gqlResponse = try? decoder.decode(GraphQLResponse<EmptyData>.self, from: data),
                   let errors = gqlResponse.errors, !errors.isEmpty {
                    throw SRHTError.graphQLErrors(errors)
                }
                throw SRHTError.httpError(http.statusCode)
            }
        }

        let graphQLResponse: GraphQLResponse<T>
        do {
            graphQLResponse = try decoder.decode(GraphQLResponse<T>.self, from: data)
        } catch {
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

    // MARK: - Cached Execute

    /// Execute a query and cache the raw response data. Returns cached data
    /// immediately on cache hit, then refreshes in the background via the
    /// `onRefresh` callback.
    func executeCached<T: Decodable>(
        service: SRHTService,
        query: String,
        variables: [String: any Sendable]? = nil,
        responseType: T.Type,
        cacheKey: String
    ) async throws -> T {
        // Try cache first
        if let cachedData = responseCache.get(forKey: cacheKey) {
            if let cached = try? decoder.decode(GraphQLResponse<T>.self, from: cachedData),
               let data = cached.data {
                return data
            }
        }

        // No cache hit — fetch normally
        return try await executeAndCache(
            service: service,
            query: query,
            variables: variables,
            responseType: responseType,
            cacheKey: cacheKey
        )
    }

    /// Execute a query, cache the raw data, and return the decoded result.
    func executeAndCache<T: Decodable>(
        service: SRHTService,
        query: String,
        variables: [String: any Sendable]? = nil,
        responseType: T.Type,
        cacheKey: String
    ) async throws -> T {
        guard let token = _token.withLock({ $0 }), !token.isEmpty else {
            throw SRHTError.unauthorized
        }

        var request = URLRequest(url: service.url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GraphQLRequestBody(
            query: query,
            variables: variables?.mapValues { AnyCodable($0) }
        )
        request.httpBody = try encoder.encode(body)

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

        // Cache the raw response data before decoding
        responseCache.set(data, forKey: cacheKey)

        let graphQLResponse: GraphQLResponse<T>
        do {
            graphQLResponse = try decoder.decode(GraphQLResponse<T>.self, from: data)
        } catch {
            #if DEBUG
            let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
            let variablesDescription = String(describing: variables)
            if let decodingError = error as? DecodingError {
                logger.error(
                    """
                    Decoding failed for \(String(describing: T.self), privacy: .public)
                    service: \(service.rawValue, privacy: .public)
                    query:
                    \(query, privacy: .public)
                    variables:
                    \(variablesDescription, privacy: .public)
                    decodingError:
                    \(String(describing: decodingError), privacy: .public)
                    response:
                    \(responseBody, privacy: .public)
                    """
                )
            } else {
                logger.error(
                    """
                    Decoding failed for \(String(describing: T.self), privacy: .public)
                    service: \(service.rawValue, privacy: .public)
                    query:
                    \(query, privacy: .public)
                    variables:
                    \(variablesDescription, privacy: .public)
                    error:
                    \(String(describing: error), privacy: .public)
                    response:
                    \(responseBody, privacy: .public)
                    """
                )
            }
            #else
            logger.error("Decoding failed for \(String(describing: T.self), privacy: .public): \(error, privacy: .public)")
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

    // MARK: - Plain-text fetch

    /// Fetch the contents of a URL as plain text, using the same authorization header.
    /// Used for build logs and other non-GraphQL resources.
    func fetchText(url: URL) async throws -> String {
        guard let token = _token.withLock({ $0 }), !token.isEmpty else {
            throw SRHTError.unauthorized
        }
        guard Self.isTrustedAuthenticatedTextURL(url) else {
            throw SRHTError.invalidAuthenticatedURL(url)
        }

        var request = URLRequest(url: url)
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
        resultKeyPath: String,
        type: T.Type
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
        resultKeyPath: String,
        type: T.Type
    ) async throws -> [T] {
        var all: [T] = []
        for try await element in paginated(
            service: service,
            query: query,
            variables: variables,
            resultKeyPath: resultKeyPath,
            type: type
        ) {
            all.append(element)
        }
        return all
    }
}

// MARK: - Data Helper

private extension SRHTClient {
    static func isTrustedAuthenticatedTextURL(_ url: URL) -> Bool {
        guard url.scheme?.localizedCaseInsensitiveCompare("https") == .orderedSame,
              let host = url.host?.lowercased() else {
            return false
        }

        return host.hasSuffix(".sr.ht")
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
