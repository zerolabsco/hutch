import Foundation

extension Bundle {
    /// The HTTP `User-Agent` string sent with all Hutch network requests.
    ///
    /// Format: `Hutch/<version>`
    var hutchUserAgent: String {
        let name = (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Hutch"
        let version = (object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
        return "\(name)/\(version)"
    }
}
