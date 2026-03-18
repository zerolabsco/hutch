import Foundation
import os

/// Thread-safe in-memory cache for raw GraphQL response data.
/// Keyed by a caller-provided string (typically service name + query hash).
final class ResponseCache: Sendable {

    private let storage: OSAllocatedUnfairLock<[String: Data]>

    init() {
        self.storage = OSAllocatedUnfairLock(initialState: [:])
    }

    /// Store raw response data under a cache key.
    func set(_ data: Data, forKey key: String) {
        storage.withLock { $0[key] = data }
    }

    /// Retrieve cached response data. Returns nil on cache miss.
    func get(forKey key: String) -> Data? {
        storage.withLock { $0[key] }
    }

    /// Remove a specific entry.
    func remove(forKey key: String) {
        storage.withLock { _ = $0.removeValue(forKey: key) }
    }

    /// Clear all cached data (e.g. on sign-out).
    func clear() {
        storage.withLock { $0.removeAll() }
    }
}
