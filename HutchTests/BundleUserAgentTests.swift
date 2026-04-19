import Foundation
import Testing
@testable import Hutch

// MARK: - URLProtocol stub

/// Captures outgoing URLRequests and returns a minimal 401 so callers fail fast
/// without touching the real network.
private final class CapturingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        CapturingURLProtocol.capturedRequests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // No cleanup is needed because the stub responds immediately in `startLoading()`.
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MARK: - Tests

/// Tests are serialized because CapturingURLProtocol uses shared static state.
@Suite(.serialized)
struct BundleUserAgentTests {

    // MARK: Bundle extension

    @Test
    func hutchUserAgentHasNameSlashVersion() {
        let ua = Bundle.main.hutchUserAgent
        let parts = ua.split(separator: "/", maxSplits: 1)
        #expect(parts.count == 2)
        #expect(parts[0] == "Hutch")
        #expect(!parts[1].isEmpty)
    }

    @Test
    func hutchUserAgentContainsNoParenthesizedContext() {
        // The old SystemStatusService user-agent appended "(System Status)".
        // The shared agent should be plain "Hutch/<version>".
        #expect(!Bundle.main.hutchUserAgent.contains("("))
    }

    // MARK: SRHTClient

    @Test
    func sRHTClientSetsUserAgentOnExecute() async {
        CapturingURLProtocol.capturedRequests = []
        let client = SRHTClient(session: CapturingURLProtocol.makeSession(), token: "test-token")

        _ = try? await client.execute(
            service: .builds,
            query: "{ jobs { results { id } } }",
            responseType: [String: String].self
        )

        guard let captured = CapturingURLProtocol.capturedRequests.first else {
            Issue.record("No request was captured by SRHTClient.execute.")
            return
        }
        #expect(captured.value(forHTTPHeaderField: "User-Agent") == Bundle.main.hutchUserAgent)
    }

    @Test
    func sRHTClientSetsUserAgentOnFetchText() async throws {
        CapturingURLProtocol.capturedRequests = []
        let client = SRHTClient(session: CapturingURLProtocol.makeSession(), token: "test-token")
        let url = try #require(URL(string: "https://builds.sr.ht/~test/job/1/log"))

        _ = try? await client.fetchText(url: url)

        guard let captured = CapturingURLProtocol.capturedRequests.first else {
            Issue.record("No request was captured by SRHTClient.fetchText.")
            return
        }
        #expect(captured.value(forHTTPHeaderField: "User-Agent") == Bundle.main.hutchUserAgent)
    }

    // MARK: SystemStatusService

    @Test
    func systemStatusServiceSetsUserAgent() async {
        CapturingURLProtocol.capturedRequests = []
        let service = SystemStatusService(session: CapturingURLProtocol.makeSession())

        _ = try? await service.fetchSnapshotHTML()

        guard let captured = CapturingURLProtocol.capturedRequests.first else {
            Issue.record("No request was captured by SystemStatusService.")
            return
        }
        #expect(captured.value(forHTTPHeaderField: "User-Agent") == Bundle.main.hutchUserAgent)
    }

    // MARK: HutchStatsService

    @Test
    func hutchStatsServiceSetsUserAgent() async {
        CapturingURLProtocol.capturedRequests = []
        let service = HutchStatsService(
            session: CapturingURLProtocol.makeSession(),
            configuration: AppConfiguration(environment: [:])
        )

        _ = try? await service.fetchContributionCalendar(actor: "testuser", endingOn: .now)

        guard let captured = CapturingURLProtocol.capturedRequests.first else {
            Issue.record("No request was captured by HutchStatsService.")
            return
        }
        #expect(captured.value(forHTTPHeaderField: "User-Agent") == Bundle.main.hutchUserAgent)
    }
}
