import Foundation
import Testing
@testable import Hutch

@Suite(.serialized)
struct APICacheTests {
    private struct Payload: Codable, Sendable, Equatable {
        let value: String
    }

    private struct GraphPayload: Decodable, Sendable, Equatable {
        let item: Payload
    }

    @Test
    func cacheReadWriteRoundTrip() async throws {
        let cache = makeCache()
        let data = try JSONEncoder().encode(Payload(value: "cached"))

        _ = try await cache.write(payload: data, cacheKey: "repo|one", resourceType: .repositoryDetail, ttl: 60)
        let entry = try await cache.read(cacheKey: "repo|one")
        let decoded = try JSONDecoder().decode(Payload.self, from: entry.payload)

        #expect(decoded == Payload(value: "cached"))
        #expect(entry.metadata.cacheKey == "repo|one")
        #expect(entry.metadata.resourceType == .repositoryDetail)
    }

    @Test
    func expiredEntryBehaviorAndPruneExpired() async throws {
        let cache = makeCache()
        let data = Data("expired".utf8)

        let metadata = try await cache.write(payload: data, cacheKey: "ticket|old", resourceType: .ticketDetail, ttl: -1)
        #expect(metadata.isExpired())
        let entry = try await cache.read(cacheKey: "ticket|old")
        #expect(entry.payload == data)

        await cache.pruneExpired(now: Date())

        await expectCacheMiss(cache, key: "ticket|old")
    }

    @Test
    func invalidationByPrefixRemovesMatchingEntriesOnly() async throws {
        let cache = makeCache()
        _ = try await cache.write(payload: Data("a".utf8), cacheKey: "todo|ticket|1", resourceType: .ticketDetail, ttl: 60)
        _ = try await cache.write(payload: Data("b".utf8), cacheKey: "todo|tickets", resourceType: .ticketList, ttl: 60)
        _ = try await cache.write(payload: Data("c".utf8), cacheKey: "builds|job|1", resourceType: .buildDetail, ttl: 60)

        await cache.removeByPrefix("todo|ticket")

        await expectCacheMiss(cache, key: "todo|ticket|1")
        await expectCacheMiss(cache, key: "todo|tickets")
        _ = try await cache.read(cacheKey: "builds|job|1")
    }

    @Test
    func maxEntrySizeEnforced() async throws {
        let directory = temporaryDirectory()
        let cache = PersistentAPICache(configuration: APICacheConfiguration(
            directory: directory,
            maxCacheSizeBytes: 1024,
            maxEntrySizeBytes: 3,
            memoryEntryLimit: 4,
            schemaVersion: 1
        ))

        do {
            _ = try await cache.write(payload: Data("toolarge".utf8), cacheKey: "large", resourceType: .buildLog, ttl: 60)
            Issue.record("Expected max-entry enforcement.")
        } catch APICacheError.entryTooLarge(let bytes) {
            #expect(bytes == 8)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func pruneToSizeLimitUsesLRU() async throws {
        let directory = temporaryDirectory()
        let cache = PersistentAPICache(configuration: APICacheConfiguration(
            directory: directory,
            maxCacheSizeBytes: 9,
            maxEntrySizeBytes: 20,
            memoryEntryLimit: 4,
            schemaVersion: 1
        ))

        _ = try await cache.write(payload: Data("1111".utf8), cacheKey: "old", resourceType: .repositoryFile, ttl: 60)
        try await Task.sleep(for: .milliseconds(5))
        _ = try await cache.write(payload: Data("2222".utf8), cacheKey: "middle", resourceType: .repositoryFile, ttl: 60)
        try await Task.sleep(for: .milliseconds(5))
        _ = try await cache.write(payload: Data("3333".utf8), cacheKey: "new", resourceType: .repositoryFile, ttl: 60)

        await cache.pruneToSizeLimit()

        await expectCacheMiss(cache, key: "old")
        _ = try await cache.read(cacheKey: "middle")
        _ = try await cache.read(cacheKey: "new")
    }

    @Test
    func cacheFirstThenRefreshReturnsUsableStaleCacheWhenRefreshFails() async throws {
        let cache = makeCache()
        let staleEnvelope = #"{"data":{"item":{"value":"stale"}}}"#.data(using: .utf8)!
        _ = try await cache.write(payload: staleEnvelope, cacheKey: "resource", resourceType: .repositoryDetail, ttl: -1)
        CachedURLProtocol.reset(responses: [.failure])
        let client = makeClient(cache: cache)

        let result = try await client.executeCached(
            service: .git,
            query: "{ item { value } }",
            responseType: GraphPayload.self,
            cacheKey: "resource",
            resourceType: .repositoryDetail,
            ttl: 60,
            policy: .cacheFirstThenRefresh
        )

        #expect(result.value.item.value == "stale")
        #expect(result.isFromCache)
    }

    @Test
    func refreshIgnoringCacheUpdatesCache() async throws {
        let cache = makeCache()
        CachedURLProtocol.reset(responses: [.success("fresh")])
        let client = makeClient(cache: cache)

        let result = try await client.executeCached(
            service: .git,
            query: "{ item { value } }",
            responseType: GraphPayload.self,
            cacheKey: "resource",
            resourceType: .repositoryDetail,
            ttl: 60,
            policy: .refreshIgnoringCache
        )
        let cached = try await client.executeCached(
            service: .git,
            query: "{ item { value } }",
            responseType: GraphPayload.self,
            cacheKey: "resource",
            resourceType: .repositoryDetail,
            ttl: 60,
            policy: .cacheOnly
        )

        #expect(result.value.item.value == "fresh")
        #expect(cached.value.item.value == "fresh")
    }

    @Test
    func networkOnlyBypassesCacheAndDoesNotWrite() async throws {
        let cache = makeCache()
        _ = try await cache.write(
            payload: #"{"data":{"item":{"value":"cached"}}}"#.data(using: .utf8)!,
            cacheKey: "resource",
            resourceType: .repositoryDetail,
            ttl: 60
        )
        CachedURLProtocol.reset(responses: [.success("network")])
        let client = makeClient(cache: cache)

        let result = try await client.executeCached(
            service: .git,
            query: "{ item { value } }",
            responseType: GraphPayload.self,
            cacheKey: "resource",
            resourceType: .repositoryDetail,
            ttl: 60,
            policy: .networkOnly
        )
        let cached = try await client.executeCached(
            service: .git,
            query: "{ item { value } }",
            responseType: GraphPayload.self,
            cacheKey: "resource",
            resourceType: .repositoryDetail,
            ttl: 60,
            policy: .cacheOnly
        )

        #expect(result.value.item.value == "network")
        #expect(cached.value.item.value == "cached")
    }

    @Test
    func plainMutationPathDoesNotReadFromCache() async throws {
        let cache = makeCache()
        _ = try await cache.write(
            payload: #"{"data":{"item":{"value":"cached"}}}"#.data(using: .utf8)!,
            cacheKey: "mutation-resource",
            resourceType: .debug,
            ttl: 60
        )
        CachedURLProtocol.reset(responses: [.success("network")])
        let client = makeClient(cache: cache)

        let result = try await client.execute(
            service: .git,
            query: "mutation update { item { value } }",
            responseType: GraphPayload.self
        )

        #expect(result.item.value == "network")
        #expect(CachedURLProtocol.requestCount == 1)
    }

    @Test
    func duplicateConcurrentRequestsAreCoalesced() async throws {
        let cache = makeCache()
        CachedURLProtocol.reset(responses: [.success("fresh")], responseDelay: 0.05)
        let client = makeClient(cache: cache)

        async let first: CachedValue<GraphPayload> = client.executeCached(
            service: .git,
            query: "{ item { value } }",
            responseType: GraphPayload.self,
            cacheKey: "same-resource",
            resourceType: .repositoryDetail,
            ttl: 60,
            policy: .refreshIgnoringCache
        )
        async let second: CachedValue<GraphPayload> = client.executeCached(
            service: .git,
            query: "{ item { value } }",
            responseType: GraphPayload.self,
            cacheKey: "same-resource",
            resourceType: .repositoryDetail,
            ttl: 60,
            policy: .refreshIgnoringCache
        )

        let values = try await [first.value.item.value, second.value.item.value]
        #expect(values == ["fresh", "fresh"])
        #expect(CachedURLProtocol.requestCount == 1)
    }

    private func makeCache() -> PersistentAPICache {
        PersistentAPICache(configuration: .temporary(directory: temporaryDirectory()))
    }

    private func makeClient(cache: any APICache) -> SRHTClient {
        SRHTClient(session: CachedURLProtocol.makeSession(), token: "token", cache: cache)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("HutchAPICacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func expectCacheMiss(_ cache: any APICache, key: String) async {
        do {
            _ = try await cache.read(cacheKey: key)
            Issue.record("Expected cache miss for \(key).")
        } catch APICacheError.miss {
            // expected: a miss is the success path here
        } catch {
            Issue.record("Unexpected error for \(key): \(error).")
        }
    }
}

private enum CachedURLProtocolResponse: Sendable {
    case success(String)
    case failure
}

private final class CachedURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var responses: [CachedURLProtocolResponse] = []
    nonisolated(unsafe) private static var delay: TimeInterval = 0
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        if Self.delay > 0 {
            Thread.sleep(forTimeInterval: Self.delay)
        }
        let next = Self.responses.isEmpty ? .success("fresh") : Self.responses.removeFirst()
        switch next {
        case .success(let value):
            let data = #"{"data":{"item":{"value":"\#(value)"}}}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
    }

    override func stopLoading() {} // required override; nothing to tear down

    static func reset(responses: [CachedURLProtocolResponse], responseDelay: TimeInterval = 0) {
        Self.responses = responses
        Self.delay = responseDelay
        Self.requestCount = 0
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CachedURLProtocol.self]
        return URLSession(configuration: config)
    }
}
