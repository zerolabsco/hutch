import Foundation

actor SystemStatusRepository {
    private let service: SystemStatusService
    private let ttl: TimeInterval

    private var snapshotCache: CacheEntry<SystemStatusSnapshot>?
    private var incidentsCache: CacheEntry<[StatusIncident]>?

    init(service: SystemStatusService = SystemStatusService(), ttl: TimeInterval = 10 * 60) {
        self.service = service
        self.ttl = ttl
    }

    func snapshot(forceRefresh: Bool = false) async throws -> SystemStatusSnapshot {
        if let cached = snapshotCache, !forceRefresh, !cached.isExpired(ttl: ttl) {
            return cached.value
        }

        do {
            let snapshot = try await service.fetchSnapshot()
            snapshotCache = CacheEntry(value: snapshot, timestamp: Date())
            return snapshot
        } catch {
            if let cached = snapshotCache {
                return cached.value
            }
            throw error
        }
    }

    func recentIncidents(forceRefresh: Bool = false) async throws -> [StatusIncident] {
        if let cached = incidentsCache, !forceRefresh, !cached.isExpired(ttl: ttl) {
            return cached.value
        }

        do {
            let incidents = try await service.fetchIncidentFeed()
            incidentsCache = CacheEntry(value: incidents, timestamp: Date())
            return incidents
        } catch {
            if let cached = incidentsCache {
                return cached.value
            }
            throw error
        }
    }
}

private struct CacheEntry<Value: Sendable>: Sendable {
    let value: Value
    let timestamp: Date

    nonisolated func isExpired(ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(timestamp) > ttl
    }
}
