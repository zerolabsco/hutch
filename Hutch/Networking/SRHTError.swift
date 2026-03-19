import Foundation

/// Errors produced by the Sourcehut GraphQL client.
enum SRHTError: LocalizedError, Sendable {
    /// The server returned one or more GraphQL-level errors.
    case graphQLErrors([GraphQLError])
    /// The HTTP response had a non-2xx status code.
    case httpError(Int)
    /// The client refused to send credentials to an unexpected URL.
    case invalidAuthenticatedURL(URL)
    /// The response data could not be decoded.
    case decodingError(any Error)
    /// A networking error from URLSession (timeout, DNS, connectivity, etc.).
    case networkError(any Error)
    /// 401 or no authentication token configured.
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .graphQLErrors(let errors):
            let messages = errors.map(\.message).joined(separator: "\n")
            return "GraphQL error: \(messages)"
        case .httpError(let code):
            return "Server returned HTTP \(code)."
        case .invalidAuthenticatedURL(let url):
            return "Refused to authenticate request to unexpected URL: \(url.absoluteString)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unauthorized:
            return "Authentication required. Please sign in again."
        }
    }

    /// Whether this error represents a connectivity issue (no internet, timeout, DNS).
    var isConnectivityError: Bool {
        switch self {
        case .networkError(let error):
            let nsError = error as NSError
            let connectivityCodes: Set<Int> = [
                NSURLErrorNotConnectedToInternet,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorInternationalRoamingOff,
                NSURLErrorDataNotAllowed
            ]
            return connectivityCodes.contains(nsError.code)
        default:
            return false
        }
    }
}

/// A single error entry from the GraphQL `errors` array.
struct GraphQLError: Decodable, Sendable {
    let message: String
    let locations: [GraphQLErrorLocation]?
}

struct GraphQLErrorLocation: Decodable, Sendable {
    let line: Int
    let column: Int
}
