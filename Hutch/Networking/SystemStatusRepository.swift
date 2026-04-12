import Foundation

protocol SystemStatusServing: Sendable {
    func fetchSnapshotHTML() async throws -> String
    func fetchIncidentFeedData() async throws -> Data
}

struct CachedSystemStatusValue<Value: Sendable>: Sendable {
    let value: Value
    let lastSuccessfulAt: Date
    let isStale: Bool
    let refreshErrorMessage: String?
}

actor SystemStatusRepository {
    private let service: any SystemStatusServing
    private let ttl: TimeInterval
    private let cacheStore: SystemStatusCacheStore
    private let now: @Sendable () -> Date

    private var snapshotCache: CacheEntry<SystemStatusSnapshot>?
    private var incidentsCache: CacheEntry<[StatusIncident]>?
    private var hasLoadedPersistentCache = false

    init(
        service: any SystemStatusServing = SystemStatusService(),
        ttl: TimeInterval = 10 * 60,
        cacheStore: SystemStatusCacheStore = SystemStatusCacheStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.service = service
        self.ttl = ttl
        self.cacheStore = cacheStore
        self.now = now
    }

    func snapshot(forceRefresh: Bool = false) async throws -> SystemStatusSnapshot {
        try await snapshotResult(forceRefresh: forceRefresh).value
    }

    func recentIncidents(forceRefresh: Bool = false) async throws -> [StatusIncident] {
        try await recentIncidentsResult(forceRefresh: forceRefresh).value
    }

    func snapshotResult(forceRefresh: Bool = false) async throws -> CachedSystemStatusValue<SystemStatusSnapshot> {
        await loadPersistentCacheIfNeeded()

        if let cached = snapshotCache, !forceRefresh, !cached.isExpired(ttl: ttl, now: now) {
            return CachedSystemStatusValue(
                value: cached.value,
                lastSuccessfulAt: cached.timestamp,
                isStale: false,
                refreshErrorMessage: nil
            )
        }

        do {
            let html = try await service.fetchSnapshotHTML()
            let snapshot = try SystemStatusService.parseSnapshotHTML(html, fetchedAt: now())
            let entry = CacheEntry(value: snapshot, timestamp: now())
            snapshotCache = entry
            await cacheStore.saveSnapshotHTML(html, timestamp: entry.timestamp)
            return CachedSystemStatusValue(
                value: snapshot,
                lastSuccessfulAt: entry.timestamp,
                isStale: false,
                refreshErrorMessage: nil
            )
        } catch {
            if let cached = snapshotCache {
                return CachedSystemStatusValue(
                    value: cached.value,
                    lastSuccessfulAt: cached.timestamp,
                    isStale: true,
                    refreshErrorMessage: refreshErrorMessage(from: error)
                )
            }
            throw error
        }
    }

    func recentIncidentsResult(forceRefresh: Bool = false) async throws -> CachedSystemStatusValue<[StatusIncident]> {
        await loadPersistentCacheIfNeeded()

        if let cached = incidentsCache, !forceRefresh, !cached.isExpired(ttl: ttl, now: now) {
            return CachedSystemStatusValue(
                value: cached.value,
                lastSuccessfulAt: cached.timestamp,
                isStale: false,
                refreshErrorMessage: nil
            )
        }

        do {
            let feedData = try await service.fetchIncidentFeedData()
            let incidents = try await SystemStatusService.parseIncidentFeedXML(feedData)
            let entry = CacheEntry(value: incidents, timestamp: now())
            incidentsCache = entry
            await cacheStore.saveIncidentFeedData(feedData, timestamp: entry.timestamp)
            return CachedSystemStatusValue(
                value: incidents,
                lastSuccessfulAt: entry.timestamp,
                isStale: false,
                refreshErrorMessage: nil
            )
        } catch {
            if let cached = incidentsCache {
                return CachedSystemStatusValue(
                    value: cached.value,
                    lastSuccessfulAt: cached.timestamp,
                    isStale: true,
                    refreshErrorMessage: refreshErrorMessage(from: error)
                )
            }
            throw error
        }
    }

    private func loadPersistentCacheIfNeeded() async {
        guard !hasLoadedPersistentCache else { return }
        if let persistedSnapshot = await cacheStore.loadSnapshotHTML(),
           let snapshot = try? SystemStatusService.parseSnapshotHTML(persistedSnapshot.html, fetchedAt: persistedSnapshot.timestamp) {
            snapshotCache = CacheEntry(value: snapshot, timestamp: persistedSnapshot.timestamp)
        }
        if let persistedFeed = await cacheStore.loadIncidentFeedData(),
           let incidents = try? await SystemStatusService.parseIncidentFeedXML(persistedFeed.data) {
            incidentsCache = CacheEntry(value: incidents, timestamp: persistedFeed.timestamp)
        }
        hasLoadedPersistentCache = true
    }

    private func refreshErrorMessage(from error: any Error) -> String {
        if let error = error as? SRHTError {
            switch error {
            case .graphQLErrors(let errors):
                let firstMessage = errors.first?.message.lowercased() ?? ""
                if firstMessage.contains("unauthorized") || firstMessage.contains("forbidden") {
                    return "You do not have permission to do that."
                }
                if firstMessage.contains("not found") || firstMessage.contains("no rows in result set") {
                    return "That content is no longer available."
                }
                return "Something went wrong. Please try again."
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
            case .networkError(let underlyingError):
                return refreshErrorMessage(from: underlyingError)
            case .unauthorized:
                return "Please sign in again."
            }
        }

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
            return "Something went wrong. Please try again."
        }
    }
}

struct CacheEntry<Value: Sendable>: Sendable {
    let value: Value
    let timestamp: Date

    nonisolated func isExpired(ttl: TimeInterval, now: @escaping @Sendable () -> Date = Date.init) -> Bool {
        now().timeIntervalSince(timestamp) > ttl
    }
}
