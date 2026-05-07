import CryptoKit
import Foundation

enum CachePolicy: Sendable, Equatable {
    case networkOnly
    case cacheOnly
    case cacheFirstThenRefresh
    case refreshIgnoringCache
}

enum CacheResourceType: String, Codable, Sendable {
    case repositoryDetail
    case repositoryList
    case repositoryTree
    case repositoryFile
    case repositoryReadme
    case ticketDetail
    case ticketList
    case buildDetail
    case buildList
    case buildLog
    case userProfile
    case status
    case pasteList
    case debug
}

struct CacheEntryMetadata: Codable, Sendable, Equatable {
    let cacheKey: String
    let resourceType: CacheResourceType
    let fetchedAt: Date
    let expiresAt: Date
    var lastAccessedAt: Date
    let payloadHash: String
    let schemaVersion: Int
    let payloadSize: Int

    func isExpired(now: Date = Date()) -> Bool {
        expiresAt <= now
    }
}

struct APICacheEntry: Sendable {
    var metadata: CacheEntryMetadata
    let payload: Data
}

struct CachedValue<Value> {
    let value: Value
    let metadata: CacheEntryMetadata?
    let source: CacheValueSource

    var isFromCache: Bool { source == .cache }
    var isStale: Bool { metadata?.isExpired() ?? false }
}

enum CacheValueSource: Sendable, Equatable {
    case cache
    case network
}

enum APICacheError: LocalizedError, Sendable {
    case miss
    case entryTooLarge(Int)
    case cacheTooLarge

    var errorDescription: String? {
        switch self {
        case .miss:
            "No cached data is available."
        case .entryTooLarge(let bytes):
            "The response is too large to cache (\(bytes) bytes)."
        case .cacheTooLarge:
            "The cache size limit was exceeded."
        }
    }
}

struct APICacheConfiguration: Sendable {
    var directory: URL
    var maxCacheSizeBytes: Int
    var maxEntrySizeBytes: Int
    var memoryEntryLimit: Int
    var schemaVersion: Int

    static func accountScoped(accountID: String) -> APICacheConfiguration {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return APICacheConfiguration(
            directory: base
                .appendingPathComponent("Hutch", isDirectory: true)
                .appendingPathComponent("APICache", isDirectory: true)
                .appendingPathComponent(accountID, isDirectory: true),
            maxCacheSizeBytes: 50 * 1024 * 1024,
            maxEntrySizeBytes: 2 * 1024 * 1024,
            memoryEntryLimit: 64,
            schemaVersion: 1
        )
    }

    static func temporary(directory: URL) -> APICacheConfiguration {
        APICacheConfiguration(
            directory: directory,
            maxCacheSizeBytes: 4 * 1024 * 1024,
            maxEntrySizeBytes: 512 * 1024,
            memoryEntryLimit: 16,
            schemaVersion: 1
        )
    }
}

protocol APICache: Sendable {
    func read(cacheKey: String) async throws -> APICacheEntry
    func write(payload: Data, cacheKey: String, resourceType: CacheResourceType, ttl: TimeInterval) async throws -> CacheEntryMetadata
    func remove(cacheKey: String) async
    func removeByPrefix(_ prefix: String) async
    func clearAll() async
    func pruneExpired(now: Date) async
    func pruneToSizeLimit() async
}

actor PersistentAPICache: APICache {
    private struct StoredEntry: Codable, Sendable {
        var metadata: CacheEntryMetadata
        let payload: Data
    }

    private let configuration: APICacheConfiguration
    private let fileManager: FileManager
    private var memoryEntries: [String: APICacheEntry] = [:]
    private var memoryOrder: [String] = []
    private var knownMetadata: [String: CacheEntryMetadata] = [:]
    private var writeCountSincePrune = 0

    init(configuration: APICacheConfiguration, fileManager: FileManager = .default) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    func read(cacheKey: String) async throws -> APICacheEntry {
        if var entry = memoryEntries[cacheKey] {
            entry.metadata.lastAccessedAt = Date()
            memoryEntries[cacheKey] = entry
            markMemoryUse(cacheKey)
            try? persist(entry)
            return entry
        }

        let url = fileURL(for: cacheKey)
        guard fileManager.fileExists(atPath: url.path) else {
            throw APICacheError.miss
        }

        var stored = try decodeEntry(from: url)
        guard stored.metadata.schemaVersion == configuration.schemaVersion else {
            try? fileManager.removeItem(at: url)
            throw APICacheError.miss
        }

        stored.metadata.lastAccessedAt = Date()
        let entry = APICacheEntry(metadata: stored.metadata, payload: stored.payload)
        knownMetadata[cacheKey] = stored.metadata
        remember(entry)
        try? persist(entry)
        return entry
    }

    func write(
        payload: Data,
        cacheKey: String,
        resourceType: CacheResourceType,
        ttl: TimeInterval
    ) async throws -> CacheEntryMetadata {
        guard payload.count <= configuration.maxEntrySizeBytes else {
            throw APICacheError.entryTooLarge(payload.count)
        }

        try ensureDirectoryExists()
        let now = Date()
        let payloadHash = Self.payloadHash(payload)
        if let existing = try? await read(cacheKey: cacheKey),
           existing.metadata.payloadHash == payloadHash {
            let metadata = CacheEntryMetadata(
                cacheKey: cacheKey,
                resourceType: resourceType,
                fetchedAt: now,
                expiresAt: now.addingTimeInterval(ttl),
                lastAccessedAt: now,
                payloadHash: payloadHash,
                schemaVersion: configuration.schemaVersion,
                payloadSize: payload.count
            )
            let entry = APICacheEntry(metadata: metadata, payload: payload)
            remember(entry)
            try persist(entry)
            return metadata
        }

        let metadata = CacheEntryMetadata(
            cacheKey: cacheKey,
            resourceType: resourceType,
            fetchedAt: now,
            expiresAt: now.addingTimeInterval(ttl),
            lastAccessedAt: now,
            payloadHash: payloadHash,
            schemaVersion: configuration.schemaVersion,
            payloadSize: payload.count
        )
        let entry = APICacheEntry(metadata: metadata, payload: payload)
        remember(entry)
        try persist(entry)

        writeCountSincePrune += 1
        if writeCountSincePrune >= 12 {
            writeCountSincePrune = 0
            await pruneExpired(now: now)
            await pruneToSizeLimit()
        }
        return metadata
    }

    func remove(cacheKey: String) async {
        memoryEntries.removeValue(forKey: cacheKey)
        memoryOrder.removeAll { $0 == cacheKey }
        knownMetadata.removeValue(forKey: cacheKey)
        try? fileManager.removeItem(at: fileURL(for: cacheKey))
    }

    func removeByPrefix(_ prefix: String) async {
        await loadKnownMetadataIfNeeded()
        for key in knownMetadata.keys where key.hasPrefix(prefix) {
            await remove(cacheKey: key)
        }
    }

    func clearAll() async {
        memoryEntries.removeAll()
        memoryOrder.removeAll()
        knownMetadata.removeAll()
        try? fileManager.removeItem(at: configuration.directory)
    }

    func pruneExpired(now: Date = Date()) async {
        await loadKnownMetadataIfNeeded()
        for metadata in knownMetadata.values where metadata.isExpired(now: now) {
            await remove(cacheKey: metadata.cacheKey)
        }
    }

    func pruneToSizeLimit() async {
        await loadKnownMetadataIfNeeded()
        var totalSize = knownMetadata.values.reduce(0) { $0 + $1.payloadSize }
        guard totalSize > configuration.maxCacheSizeBytes else { return }

        let victims = knownMetadata.values.sorted { $0.lastAccessedAt < $1.lastAccessedAt }
        for metadata in victims {
            await remove(cacheKey: metadata.cacheKey)
            totalSize -= metadata.payloadSize
            if totalSize <= configuration.maxCacheSizeBytes { break }
        }
    }

    private func remember(_ entry: APICacheEntry) {
        memoryEntries[entry.metadata.cacheKey] = entry
        knownMetadata[entry.metadata.cacheKey] = entry.metadata
        markMemoryUse(entry.metadata.cacheKey)
        while memoryOrder.count > configuration.memoryEntryLimit, let evicted = memoryOrder.first {
            memoryOrder.removeFirst()
            memoryEntries.removeValue(forKey: evicted)
        }
    }

    private func markMemoryUse(_ cacheKey: String) {
        memoryOrder.removeAll { $0 == cacheKey }
        memoryOrder.append(cacheKey)
    }

    private func persist(_ entry: APICacheEntry) throws {
        try ensureDirectoryExists()
        let stored = StoredEntry(metadata: entry.metadata, payload: entry.payload)
        let data = try JSONEncoder.srhtCache.encode(stored)
        try data.write(to: fileURL(for: entry.metadata.cacheKey), options: [.atomic])
    }

    private func decodeEntry(from url: URL) throws -> StoredEntry {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.srhtCache.decode(StoredEntry.self, from: data)
    }

    private func loadKnownMetadataIfNeeded() async {
        guard knownMetadata.isEmpty else { return }
        guard let urls = try? fileManager.contentsOfDirectory(
            at: configuration.directory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in urls where url.pathExtension == "json" {
            guard let stored = try? decodeEntry(from: url) else { continue }
            knownMetadata[stored.metadata.cacheKey] = stored.metadata
        }
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: configuration.directory.path) {
            try fileManager.createDirectory(
                at: configuration.directory,
                withIntermediateDirectories: true
            )
        }
    }

    private func fileURL(for cacheKey: String) -> URL {
        configuration.directory
            .appendingPathComponent(Self.payloadHash(Data(cacheKey.utf8)))
            .appendingPathExtension("json")
    }

    private static func payloadHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension JSONEncoder {
    static var srhtCache: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var srhtCache: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
