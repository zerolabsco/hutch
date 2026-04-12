import Foundation

struct AppConfiguration: Sendable {
    static let defaultHutchStatsBaseURL = URL(string: "https://hutch-stats.zerolabs.sh")!
    static let hutchStatsBaseURLEnvironmentKey = "HUTCH_STATS_BASE_URL"

    let hutchStatsBaseURL: URL

    init(
        userDefaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo,
        environment: [String: String]? = nil
    ) {
        let resolvedEnvironment = environment ?? processInfo.environment

        if
            let rawValue = resolvedEnvironment[Self.hutchStatsBaseURLEnvironmentKey],
            let url = Self.normalizedURL(from: rawValue)
        {
            self.hutchStatsBaseURL = url
        } else if
            let rawValue = userDefaults.string(forKey: AppStorageKeys.hutchStatsBaseURL),
            let url = Self.normalizedURL(from: rawValue)
        {
            self.hutchStatsBaseURL = url
        } else {
            self.hutchStatsBaseURL = Self.defaultHutchStatsBaseURL
        }
    }

    private static func normalizedURL(from rawValue: String) -> URL? {
        guard var components = URLComponents(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        if components.path.isEmpty {
            components.path = "/"
        }

        return components.url
    }
}
