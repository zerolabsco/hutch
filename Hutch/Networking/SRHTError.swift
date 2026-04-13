import Foundation

/// Errors produced by the SourceHut GraphQL client.
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
            let messages = errors.diagnosticSummary
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

    nonisolated var userFacingMessage: String {
        switch self {
        case .graphQLErrors(let errors):
            switch errors.classification {
            case .unauthorized, .forbidden:
                return "You do not have permission to do that."
            case .notFound, .noRows, .missingReference, .unknownRevision:
                return "That content is no longer available."
            case .serviceNotProvisioned:
                return "That account needs to activate this SourceHut service before this action can succeed."
            case .validation:
                return errors.primaryMessage ?? "Please review your changes and try again."
            case .other:
                return "Something went wrong. Please try again."
            }
        case .httpError(let code):
            if code == 401 {
                return "Please sign in again."
            }
            if code == 403 {
                return "You do not have permission to do that."
            }
            if code == 404 {
                return "That content is no longer available."
            }
            if (500...599).contains(code) {
                return "The server is unavailable right now. Please try again."
            }
            return "Something went wrong. Please try again."
        case .invalidAuthenticatedURL:
            return "That request could not be completed."
        case .decodingError:
            return "The response could not be loaded right now."
        case .networkError(let error):
            let nsError = error as NSError
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorDataNotAllowed:
                return "Check your connection and try again."
            default:
                return "The network request failed. Please try again."
            }
        case .unauthorized:
            return "Please sign in again."
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

extension Error {
    nonisolated var userFacingMessage: String {
        if let error = self as? SRHTError {
            return error.userFacingMessage
        }

        let nsError = self as NSError
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorTimedOut,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorDataNotAllowed:
            return "Check your connection and try again."
        default:
            return "Something went wrong. Please try again."
        }
    }

    nonisolated var graphQLErrors: [GraphQLError]? {
        guard let srhtError = self as? SRHTError,
              case let SRHTError.graphQLErrors(errors) = srhtError else {
            return nil
        }
        return errors
    }

    nonisolated func matchesGraphQLErrorClassification(_ classification: GraphQLErrorClassification) -> Bool {
        graphQLErrors?.classification == classification
    }

    nonisolated func containsGraphQLErrorMessage(_ fragment: String) -> Bool {
        graphQLErrors?.containsMessage(fragment) == true
    }
}

/// A single error entry from the GraphQL `errors` array.
struct GraphQLError: Decodable, Sendable {
    let message: String
    let locations: [GraphQLErrorLocation]?
}

enum GraphQLErrorClassification: Sendable {
    case unauthorized
    case forbidden
    case notFound
    case noRows
    case missingReference
    case unknownRevision
    case serviceNotProvisioned
    case validation
    case other
}

extension Array where Element == GraphQLError {
    nonisolated var classification: GraphQLErrorClassification {
        if containsMessage("unauthorized") { return .unauthorized }
        if containsMessage("forbidden") { return .forbidden }
        if containsMessage("reference not found") { return .missingReference }
        if containsMessage("no rows in result set") { return .noRows }
        if containsMessage("unknown revision") || containsMessage("path not in the working tree") {
            return .unknownRevision
        }
        if containsMessage("not found") || containsMessage("no such") || containsMessage("missing revision") {
            return .notFound
        }
        if containsMessage("no such repository or user found") {
            return .serviceNotProvisioned
        }
        if let primaryMessage, !primaryMessage.isEmpty {
            return .validation
        }
        return .other
    }

    nonisolated var primaryMessage: String? {
        let candidates = map(\.message)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return candidates.first
    }

    nonisolated var diagnosticSummary: String {
        map(\.message)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    nonisolated func containsMessage(_ fragment: String) -> Bool {
        contains { $0.message.localizedCaseInsensitiveContains(fragment) }
    }
}

struct GraphQLErrorLocation: Decodable, Sendable {
    let line: Int
    let column: Int
}
