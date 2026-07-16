import Foundation

// MARK: - Response types (file-private to avoid @MainActor Decodable issues)

private struct ListEmailsResponse: Decodable, Sendable {
    let list: ListEmailsPayload?
}

private struct ListEmailsPayload: Decodable, Sendable {
    let emails: ListEmailPage
}

private struct ListEmailPage: Decodable, Sendable {
    let results: [ListEmailPayload]
    let cursor: String?
}

private struct ListEmailPayload: Decodable, Sendable {
    /// When sr.ht received the mail. Unlike `date`, which comes from the sender's
    /// Date: header and is both nullable and not to be trusted, this is
    /// server-authoritative.
    let received: Date
    let thread: ListEmailThread
}

private struct ListEmailThread: Decodable, Sendable {
    let root: ListEmailThreadRoot
}

private struct ListEmailThreadRoot: Decodable, Sendable {
    let id: Int
}

// MARK: - Activity

/// When each thread on a mailing list last received mail.
///
/// `Thread.updated` cannot answer this. Despite its name, and despite the schema
/// describing threads as ordered "most recently bumped", it is the root email's
/// insert time and never advances when a reply arrives — sr.ht reports `updated`
/// seven seconds after `root.date` on a thread carrying four replies. Anything
/// built on it silently treats thread creation as activity.
///
/// `MailingList.emails` is reverse-chronological arrival data, so it can.
struct MailingListActivity: Sendable {
    private let newestByRootEmailID: [Int: Date]

    init(newestByRootEmailID: [Int: Date] = [:]) {
        self.newestByRootEmailID = newestByRootEmailID
    }

    /// The newest arrival in the thread rooted at `rootEmailID`.
    ///
    /// Falls back to `fallback` for threads with nothing inside the scanned
    /// window, which are by definition older than the cutoff and therefore read.
    func lastActivity(rootEmailID: Int, fallback: Date) -> Date {
        guard let newest = newestByRootEmailID[rootEmailID] else { return fallback }
        return max(newest, fallback)
    }
}

enum MailingListActivityLoader {

    private static let listEmailsQuery = """
    query listActivity($rid: ID!, $cursor: Cursor) {
        list(rid: $rid) {
            emails(cursor: $cursor) {
                results {
                    received
                    thread { root { id } }
                }
                cursor
            }
        }
    }
    """

    /// Scans the list's mail newest-first and stops once it is older than
    /// `cutoff`, so a quiet list costs a single page and a busy one costs only
    /// what has arrived since.
    ///
    /// `maxPages` bounds the scan. An account carrying pre-existing read state has
    /// a `distantPast` cutoff, which would otherwise walk the entire archive;
    /// threads beyond the window keep their fallback date and stay read, which is
    /// what they already were.
    ///
    /// Returns empty activity on failure rather than throwing: unread is a
    /// decoration, and losing it should not fail the thread list around it.
    static func load(
        client: SRHTClient,
        listRID: String,
        since cutoff: Date,
        maxPages: Int = 3
    ) async -> MailingListActivity {
        var newest: [Int: Date] = [:]
        var cursor: String?
        var pagesFetched = 0

        while pagesFetched < maxPages {
            var variables: [String: any Sendable] = ["rid": listRID]
            if let cursor {
                variables["cursor"] = cursor
            }

            let response: ListEmailsResponse
            do {
                response = try await client.execute(
                    service: .lists,
                    query: listEmailsQuery,
                    variables: variables,
                    responseType: ListEmailsResponse.self
                )
            } catch {
                return MailingListActivity(newestByRootEmailID: newest)
            }

            guard let page = response.list?.emails else { break }
            pagesFetched += 1

            for email in page.results {
                let rootID = email.thread.root.id
                if let existing = newest[rootID], existing >= email.received { continue }
                newest[rootID] = email.received
            }

            // Reverse chronological, so once a page ends older than the cutoff
            // nothing further back can matter.
            if let oldest = page.results.map(\.received).min(), oldest <= cutoff { break }
            guard let next = page.cursor, !next.isEmpty else { break }
            cursor = next
        }

        return MailingListActivity(newestByRootEmailID: newest)
    }
}
