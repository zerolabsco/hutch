import Foundation

extension DateFormatter {
    /// Formatter for the sr.ht `Time` scalar: `%Y-%m-%dT%H:%M:%SZ` (UTC).
    static let srht: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Fallback formatter that also accepts fractional seconds.
    static let srhtFractional: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

extension JSONDecoder.DateDecodingStrategy {
    /// Tries the primary sr.ht format first, then falls back to fractional seconds.
    static let srhtFlexible: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        if let date = DateFormatter.srht.date(from: string) {
            return date
        }
        if let date = DateFormatter.srhtFractional.date(from: string) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Cannot decode date string: \(string)"
        )
    }
}
