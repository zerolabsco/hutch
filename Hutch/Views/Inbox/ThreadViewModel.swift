import Foundation
import os

private let inboxLogger = Logger(subsystem: "net.cleberg.Hutch", category: "Inbox")

private struct InboxThreadDetailResponse: Decodable, Sendable {
    let list: InboxThreadDetailList?
}

private struct InboxThreadDetailList: Decodable, Sendable {
    let threads: InboxThreadPayloadPage?
}

private struct InboxThreadLookupResponse: Decodable, Sendable {
    let list: InboxThreadLookupList?
}

private struct InboxThreadLookupList: Decodable, Sendable {
    let message: InboxThreadLookupMessage?
}

private struct InboxThreadLookupMessage: Decodable, Sendable {
    let thread: InboxThreadPayloadDetail?
}

private struct InboxThreadPayloadDetail: Decodable, Sendable {
    let subject: String?
    let updated: Date?
    let replies: Int?
    let sender: Entity?
    let list: InboxMailingListReference?
    let root: InboxThreadMessagePayload?
    let descendants: InboxThreadMessagesPage?
}

private struct InboxThreadPayloadPage: Decodable, Sendable {
    let results: [InboxThreadPayloadDetail]
    let cursor: String?
}

private struct InboxThreadMessagesPage: Decodable, Sendable {
    let results: [InboxThreadMessagePayload]?
    let cursor: String?
}

private struct InboxThreadMessagePayload: Decodable, Sendable {
    let id: Int?
    let sender: Entity?
    let received: Date?
    let date: Date?
    let subject: String?
    let messageID: String?
    let body: String?
    let rawMessage: URL?
    let patch: InboxPatchPreview?
}

@Observable
@MainActor
final class ThreadViewModel {
    private(set) var thread: InboxThreadDetail?
    private(set) var isLoading = false
    var error: String?
    var composeDraft: MailComposeDraft?

    private let summary: InboxThreadSummary
    private let client: SRHTClient

    private static let threadDetailQuery = """
    query inboxThreadDetail($rid: ID!, $cursor: Cursor, $descCursor: Cursor) {
        list(rid: $rid) {
            threads(cursor: $cursor) {
                results {
                subject
                updated
                replies
                sender { canonicalName }
                list {
                    id
                    rid
                    name
                    owner { canonicalName }
                }
                root {
                    id
                    sender { canonicalName }
                    received
                    date
                    subject
                    messageID
                    body
                    rawMessage
                    patch { subject }
                }
                descendants(cursor: $descCursor) {
                    results {
                        id
                        sender { canonicalName }
                        received
                        date
                        subject
                        messageID
                        body
                        rawMessage
                        patch { subject }
                    }
                    cursor
                }
                }
                cursor
                }
        }
    }
    """

    private static let threadByMessageIDQuery = """
    query inboxThreadByMessageID($rid: ID!, $messageID: String!, $descCursor: Cursor) {
        list(rid: $rid) {
            message(messageID: $messageID) {
                thread {
                    subject
                    updated
                    replies
                    sender { canonicalName }
                    list {
                        id
                        rid
                        name
                        owner { canonicalName }
                    }
                    root {
                        id
                        sender { canonicalName }
                        received
                        date
                        subject
                        messageID
                        body
                        rawMessage
                        patch { subject }
                    }
                    descendants(cursor: $descCursor) {
                        results {
                            id
                            sender { canonicalName }
                            received
                            date
                            subject
                            messageID
                            body
                            rawMessage
                            patch { subject }
                        }
                        cursor
                    }
                }
            }
        }
    }
    """

    init(summary: InboxThreadSummary, client: SRHTClient) {
        self.summary = summary
        self.client = client
    }

    func loadThread() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        inboxLogger.debug("Opening inbox thread: \(self.summary.debugIdentifierSummary, privacy: .public)")

        do {
            let threadPayloads = try await fetchThreadPayloads()

            guard !threadPayloads.isEmpty else {
                throw SRHTError.graphQLErrors([GraphQLError(message: "Thread is no longer available.", locations: nil)])
            }

            let listReference = threadPayloads.lazy.compactMap(\.list).first ?? InboxMailingListReference(
                id: summary.listID,
                rid: summary.listRID,
                name: summary.listName,
                owner: summary.listOwner
            )
            var messagesByID: [Int: InboxMessage] = [:]

            for payload in threadPayloads {
                guard let rootMessage = Self.message(from: payload.root, fallbackID: summary.rootEmailID) else {
                    continue
                }
                messagesByID[rootMessage.id] = rootMessage

                let descendantMessages = try await fetchAllDescendantMessages(
                    initialPayload: payload,
                    candidateMessageIDs: Self.messageIDCandidates(from: payload.root?.messageID ?? summary.rootMessageID)
                )
                for message in descendantMessages {
                    messagesByID[message.id] = message
                }
            }

            let messages = messagesByID.values.sorted { $0.date < $1.date }
            guard !messages.isEmpty else {
                throw SRHTError.graphQLErrors([GraphQLError(message: "Thread root message is unavailable.", locations: nil)])
            }

            let latestPayload = threadPayloads.max(by: { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }) ?? threadPayloads[0]
            thread = InboxThreadDetail(
                id: summary.id,
                rootEmailID: summary.rootEmailID,
                rootMessageID: summary.rootMessageID,
                subject: latestPayload.subject ?? summary.subject,
                author: latestPayload.sender ?? summary.latestSender,
                lastActivityAt: latestPayload.updated ?? summary.lastActivityAt,
                mailto: nil,
                listID: listReference.id,
                listRID: listReference.rid,
                listName: listReference.name,
                listOwner: listReference.owner,
                messageCount: max(messages.count, summary.messageCount ?? 0),
                messages: messages
            )
        } catch {
            thread = nil
            self.error = error.localizedDescription
            inboxLogger.error("Inbox thread detail failed for \(self.summary.debugIdentifierSummary, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchThreadPayloads() async throws -> [InboxThreadPayloadDetail] {
        var payloads: [InboxThreadPayloadDetail] = []
        var seenRoots = Set<String>()

        for rootMessageID in summary.threadRootMessageIDs {
            guard !seenRoots.contains(rootMessageID) else { continue }
            seenRoots.insert(rootMessageID)
            if let payload = try await fetchThreadPayload(rootMessageID: rootMessageID) {
                payloads.append(payload)
            }
        }

        if payloads.isEmpty, let fallback = try await fetchThreadPayload(rootMessageID: summary.rootMessageID) {
            payloads.append(fallback)
        }

        return payloads
    }

    private func fetchThreadPayload(rootMessageID: String) async throws -> InboxThreadPayloadDetail? {
        if let messageMatchedThread = try await fetchThreadByMessageID(rootMessageID: rootMessageID) {
            return messageMatchedThread
        }
        return try await scanThreadPages(targetRootMessageID: rootMessageID)
    }

    private func fetchThreadByMessageID(rootMessageID: String) async throws -> InboxThreadPayloadDetail? {
        let candidateMessageIDs = Self.messageIDCandidates(from: rootMessageID)
        inboxLogger.debug(
            "Inbox thread lookup IDs: subject=\(self.summary.subject, privacy: .public) rootEmailID=\(self.summary.rootEmailID, privacy: .public) rootMessageID=\(rootMessageID, privacy: .public) candidates=\(candidateMessageIDs.joined(separator: ", "), privacy: .public)"
        )

        var lastLookupError: Error?

        for messageID in candidateMessageIDs {
            inboxLogger.debug(
                "Inbox thread detail lookup request: rid=\(self.summary.listRID, privacy: .public) messageID=\(messageID, privacy: .public)"
            )

            do {
                let response: InboxThreadLookupResponse = try await Self.executeGraphQLRequest(
                    client: client,
                    query: Self.threadByMessageIDQuery,
                    variables: [
                        "rid": self.summary.listRID,
                        "messageID": messageID,
                        "descCursor": nil as String?
                    ]
                )

                if let thread = response.list?.message?.thread {
                    return thread
                }
            } catch let error as SRHTError {
                switch error {
                case .graphQLErrors(let errors):
                    let combinedMessage = errors.map(\.message).joined(separator: " | ")
                    inboxLogger.error(
                        "Inbox thread message lookup failed: rid=\(self.summary.listRID, privacy: .public) messageID=\(messageID, privacy: .public) errors=\(combinedMessage, privacy: .public)"
                    )
                    if errors.allSatisfy({ $0.message.localizedCaseInsensitiveContains("no rows in result set") }) {
                        lastLookupError = error
                        continue
                    }
                    throw error
                default:
                    throw error
                }
            }
        }

        if let lastLookupError {
            inboxLogger.debug(
                "Inbox thread message lookup exhausted candidates for \(self.summary.debugIdentifierSummary, privacy: .public): \(lastLookupError.localizedDescription, privacy: .public)"
            )
        }
        return nil
    }

    private func scanThreadPages(targetRootMessageID: String) async throws -> InboxThreadPayloadDetail? {
        var threadCursor: String?

        while true {
            var variables: [String: any Sendable] = ["rid": summary.listRID]
            if let threadCursor {
                variables["cursor"] = threadCursor
            }

            let response: InboxThreadDetailResponse = try await Self.executeGraphQLRequest(
                client: client,
                query: Self.threadDetailQuery,
                variables: {
                    var variables = variables
                    variables["descCursor"] = nil as String?
                    return variables
                }()
            )

            guard let threadPage = response.list?.threads else {
                throw SRHTError.graphQLErrors([GraphQLError(message: "Thread is no longer available.", locations: nil)])
            }

            let candidates = threadPage.results.map { payload in
                "subject=\(payload.subject ?? "<nil>") rootEmailID=\(payload.root?.id.map(String.init) ?? "<nil>") rootMessageID=\(payload.root?.messageID ?? "<nil>")"
            }.joined(separator: " | ")
            inboxLogger.debug("Inbox thread detail page candidates: \(candidates, privacy: .public)")

            if let matchedThread = threadPage.results.first(where: {
                $0.root?.messageID == targetRootMessageID ||
                $0.root?.id == summary.rootEmailID ||
                $0.root?.subject == summary.subject
            }) {
                return matchedThread
            }

            guard let nextCursor = threadPage.cursor else {
                return nil
            }
            threadCursor = nextCursor
        }
    }

    private func fetchAllDescendantMessages(
        initialPayload: InboxThreadPayloadDetail,
        candidateMessageIDs: [String]
    ) async throws -> [InboxMessage] {
        var messagesByID: [Int: InboxMessage] = [:]

        for payload in initialPayload.descendants?.results ?? [] {
            if let message = Self.message(from: payload, fallbackID: nil) {
                messagesByID[message.id] = message
            }
        }

        var descendantCursor = initialPayload.descendants?.cursor
        while let currentCursor = descendantCursor {
            guard let page = try await fetchDescendantPage(
                cursor: currentCursor,
                candidateMessageIDs: candidateMessageIDs
            ) else {
                break
            }

            for payload in page.results ?? [] {
                if let message = Self.message(from: payload, fallbackID: nil) {
                    messagesByID[message.id] = message
                }
            }
            descendantCursor = page.cursor
        }

        return messagesByID.values.sorted { $0.date < $1.date }
    }

    private func fetchDescendantPage(
        cursor: String,
        candidateMessageIDs: [String]
    ) async throws -> InboxThreadMessagesPage? {
        for messageID in candidateMessageIDs {
            let response: InboxThreadLookupResponse = try await Self.executeGraphQLRequest(
                client: client,
                query: Self.threadByMessageIDQuery,
                variables: [
                    "rid": summary.listRID,
                    "messageID": messageID,
                    "descCursor": cursor
                ]
            )

            if let descendants = response.list?.message?.thread?.descendants {
                return descendants
            }
        }

        return nil
    }

    func prepareReply() {
        guard let thread else {
            error = "This thread is not ready to reply to yet."
            return
        }
        inboxLogger.debug(
            "Preparing inbox reply: subject=\(thread.subject, privacy: .public) listRID=\(thread.listRID, privacy: .public) rootMessageID=\(thread.rootMessageID, privacy: .public) recipient=\(thread.replyRecipient, privacy: .public) senderIdentity=system-mail-account"
        )
        composeDraft = MailComposeDraft(
            recipients: [thread.replyRecipient],
            ccRecipients: [],
            subject: thread.replySubject,
            body: ""
        )
    }

    func dismissReply() {
        composeDraft = nil
    }

    private static func message(from payload: InboxThreadMessagePayload?, fallbackID: Int?) -> InboxMessage? {
        guard let payload else { return nil }
        guard let id = payload.id ?? fallbackID,
              let author = payload.sender,
              let date = payload.date ?? payload.received,
              let subject = payload.subject,
              let body = payload.body else {
            return nil
        }

        let normalizedIdentity = normalizedSenderIdentity(from: body, fallbackAuthor: author)
        let displayBody = sanitizedDisplayBody(from: body)
        let contentBlocks = segmentMessageBody(displayBody, isPatch: payload.patch != nil)

        return InboxMessage(
            id: id,
            author: author,
            date: date,
            subject: subject,
            body: body,
            senderDisplayName: normalizedIdentity.displayName,
            senderEmailAddress: normalizedIdentity.emailAddress,
            isPatch: payload.patch != nil,
            contentBlocks: contentBlocks,
            rawMessageURL: payload.rawMessage
        )
    }

    nonisolated static func mailComposeDraft(from mailto: String) -> MailComposeDraft? {
        guard let components = URLComponents(string: mailto),
              components.scheme?.lowercased() == "mailto" else {
            return nil
        }

        let recipients = components.path
            .split(separator: ",")
            .map { String($0) }
            .filter { !$0.isEmpty }
        let queryItems = components.queryItems ?? []
        let ccRecipients = queryItems
            .first(where: { $0.name.caseInsensitiveCompare("cc") == .orderedSame })?
            .value?
            .split(separator: ",")
            .map(String.init) ?? []
        let subject = queryItems
            .first(where: { $0.name.caseInsensitiveCompare("subject") == .orderedSame })?
            .value ?? ""
        let body = queryItems
            .first(where: { $0.name.caseInsensitiveCompare("body") == .orderedSame })?
            .value ?? ""

        return MailComposeDraft(
            recipients: recipients,
            ccRecipients: ccRecipients,
            subject: subject,
            body: body
        )
    }

    private static func messageIDCandidates(from messageID: String) -> [String] {
        let trimmedMessageID = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessageID.isEmpty else { return [] }

        if trimmedMessageID.hasPrefix("<"), trimmedMessageID.hasSuffix(">") {
            return [trimmedMessageID, String(trimmedMessageID.dropFirst().dropLast())]
        }

        return [trimmedMessageID, "<\(trimmedMessageID)>"]
    }

    private static func normalizedSenderIdentity(from body: String, fallbackAuthor: Entity) -> (displayName: String, emailAddress: String?) {
        guard let fromLine = leadingHeaderValue(named: "From", in: body) else {
            return fallbackSenderIdentity(from: fallbackAuthor)
        }

        let trimmedFromLine = fromLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmedFromLine.lastIndex(of: "<"),
           let end = trimmedFromLine.lastIndex(of: ">"),
           start < end {
            let email = String(trimmedFromLine[trimmedFromLine.index(after: start)..<end]).trimmingCharacters(in: .whitespaces)
            let name = String(trimmedFromLine[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return (name, email.isEmpty ? nil : email)
            }
            return (email.isEmpty ? trimmedFromLine : email, email.isEmpty ? nil : email)
        }

        if trimmedFromLine.contains("@") {
            return (trimmedFromLine, trimmedFromLine)
        }

        return (trimmedFromLine, nil)
    }

    private static func fallbackSenderIdentity(from author: Entity) -> (displayName: String, emailAddress: String?) {
        let canonicalName = author.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        if canonicalName.contains("@") {
            return (canonicalName, canonicalName)
        }
        if canonicalName.hasPrefix("~") {
            return (String(canonicalName.dropFirst()), nil)
        }
        return (canonicalName, nil)
    }

    private static func sanitizedDisplayBody(from body: String) -> String {
        let lines = body.components(separatedBy: .newlines)
        let headerPrefixes = ["From:", "Date:", "To:", "Cc:", "Subject:"]
        var headerCount = 0
        var blankLineIndex: Int?

        for (index, line) in lines.prefix(12).enumerated() {
            if line.isEmpty {
                blankLineIndex = index
                break
            }
            if headerPrefixes.contains(where: { line.hasPrefix($0) }) {
                headerCount += 1
            } else if headerCount > 0 {
                break
            }
        }

        guard headerCount >= 2, let blankLineIndex else {
            return body
        }

        return lines.dropFirst(blankLineIndex + 1).joined(separator: "\n")
    }

    nonisolated static func segmentMessageBodyForTesting(_ body: String, isPatch: Bool) -> [InboxMessageContentBlock] {
        segmentMessageBody(body, isPatch: isPatch)
    }

    private nonisolated static func segmentMessageBody(_ body: String, isPatch: Bool) -> [InboxMessageContentBlock] {
        guard isPatch else {
            let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedBody.isEmpty ? [] : [.plainText(trimmedBody)]
        }

        let normalizedBody = normalizeLineEndings(in: body)
        let lines = normalizedBody.components(separatedBy: "\n")
        guard let diffStartIndex = actualDiffStartIndex(in: lines) else {
            let trimmedBody = normalizedBody.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedBody.isEmpty ? [] : [.plainText(trimmedBody)]
        }

        var blocks: [InboxMessageContentBlock] = []
        let leadingPlainText = lines[..<diffStartIndex]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !leadingPlainText.isEmpty {
            blocks.append(.plainText(leadingPlainText))
        }

        let remainingLines = Array(lines[diffStartIndex...])
        let signatureIndex = remainingLines.firstIndex(where: isEmailSignatureSeparator)

        let diffLines: ArraySlice<String>
        let trailingPlainText: String
        if let signatureIndex {
            diffLines = remainingLines[..<signatureIndex]
            trailingPlainText = remainingLines[signatureIndex...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            diffLines = remainingLines[...]
            trailingPlainText = ""
        }

        let diff = diffLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !diff.isEmpty {
            blocks.append(.diff(diff))
        }

        if !trailingPlainText.isEmpty {
            blocks.append(.plainText(trailingPlainText))
        }
        return blocks
    }

    private nonisolated static func actualDiffStartIndex(in lines: [String]) -> Int? {
        if let explicitDiffIndex = lines.firstIndex(where: { $0.hasPrefix("diff --git ") }) {
            return explicitDiffIndex
        }

        for index in lines.indices {
            let line = lines[index]
            guard line.hasPrefix("--- ") else { continue }
            let nextIndex = lines.index(after: index)
            guard nextIndex < lines.endIndex else { continue }
            let nextLine = lines[nextIndex]
            guard nextLine.hasPrefix("+++ ") else { continue }

            let oldPath = String(line.dropFirst(4))
            let newPath = String(nextLine.dropFirst(4))
            let looksLikeUnifiedDiff = (oldPath.hasPrefix("a/") || oldPath == "/dev/null") &&
                (newPath.hasPrefix("b/") || newPath == "/dev/null")

            if looksLikeUnifiedDiff {
                return index
            }
        }

        return nil
    }

    private nonisolated static func isEmailSignatureSeparator(_ line: String) -> Bool {
        line == "-- " || line == "--"
    }

    private nonisolated static func normalizeLineEndings(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func leadingHeaderValue(named headerName: String, in body: String) -> String? {
        let prefix = "\(headerName):"
        let lines = body.components(separatedBy: .newlines)
        for line in lines.prefix(12) {
            if line.isEmpty {
                break
            }
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func executeGraphQLRequest<T: Decodable>(
        client: SRHTClient,
        query: String,
        variables: [String: any Sendable]
    ) async throws -> T {
        guard let token = KeychainHelper.loadToken(), !token.isEmpty else {
            throw SRHTError.unauthorized
        }

        var request = URLRequest(url: SRHTService.lists.url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(
            GraphQLRequestBody(
                query: query,
                variables: variables.mapValues { AnyCodable($0) }
            )
        )

        let (data, _) = try await URLSession.shared.data(for: request)
        #if DEBUG
        let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
        inboxLogger.debug("Inbox thread raw GraphQL response: \(responseBody, privacy: .public)")
        #endif

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .srhtFlexible
        let envelope = try decoder.decode(GraphQLResponse<T>.self, from: data)
        if let errors = envelope.errors, !errors.isEmpty {
            throw SRHTError.graphQLErrors(errors)
        }
        guard let payload = envelope.data else {
            throw SRHTError.decodingError(
                DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "No data in thread detail response"))
            )
        }
        return payload
    }
}
