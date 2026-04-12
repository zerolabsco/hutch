import Foundation

actor SystemStatusCacheStore {
    private let snapshotCacheKey = "systemStatusSnapshotCache"
    private let incidentCacheKey = "systemStatusIncidentCache"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSnapshotHTML() -> (html: String, timestamp: Date)? {
        guard let html = defaults.string(forKey: snapshotCacheKey) else {
            return nil
        }

        let timestampValue = defaults.double(forKey: snapshotTimestampKey)
        guard timestampValue > 0 else {
            defaults.removeObject(forKey: snapshotCacheKey)
            defaults.removeObject(forKey: snapshotTimestampKey)
            return nil
        }

        return (html, Date(timeIntervalSince1970: timestampValue))
    }

    func saveSnapshotHTML(_ html: String, timestamp: Date) {
        defaults.set(html, forKey: snapshotCacheKey)
        defaults.set(timestamp.timeIntervalSince1970, forKey: snapshotTimestampKey)
    }

    func loadIncidentFeedData() -> (data: Data, timestamp: Date)? {
        guard let data = defaults.data(forKey: incidentCacheKey) else {
            return nil
        }

        let timestampValue = defaults.double(forKey: incidentTimestampKey)
        guard timestampValue > 0 else {
            defaults.removeObject(forKey: incidentCacheKey)
            defaults.removeObject(forKey: incidentTimestampKey)
            return nil
        }

        return (data, Date(timeIntervalSince1970: timestampValue))
    }

    func saveIncidentFeedData(_ data: Data, timestamp: Date) {
        defaults.set(data, forKey: incidentCacheKey)
        defaults.set(timestamp.timeIntervalSince1970, forKey: incidentTimestampKey)
    }

    private var snapshotTimestampKey: String {
        "\(snapshotCacheKey).timestamp"
    }

    private var incidentTimestampKey: String {
        "\(incidentCacheKey).timestamp"
    }
}
