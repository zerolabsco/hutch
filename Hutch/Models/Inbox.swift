import Foundation

struct InboxThreadSummary: Identifiable, Hashable, Sendable {
    let rootEmailID: Int
    let rootMessageID: String
    let threadRootEmailIDs: [Int]
    let threadRootMessageIDs: [String]
    let listID: Int
    let listRID: String
    let listName: String
    let listOwner: Entity
    let subject: String
    let latestSender: Entity
    let lastActivityAt: Date
    let messageCount: Int?
    let repo: String?
    let containsPatch: Bool
    let isUnread: Bool

    var id: String {
        threadGroupingKey
    }

    var listDisplayName: String {
        "\(listOwner.canonicalName)/\(listName)"
    }

    var displaySubject: String {
        Self.normalizedSubject(from: subject)
    }

    var metadataLine: String {
        var parts = [latestSenderDisplayName]
        if let messageCount, messageCount > 1 {
            let replyCount = max(messageCount - 1, 1)
            parts.append("\(replyCount) repl\(replyCount == 1 ? "y" : "ies")")
        }
        parts.append(lastActivityAt.relativeDescription)
        return parts.joined(separator: " • ")
    }

    var latestSenderDisplayName: String {
        let canonicalName = latestSender.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        if canonicalName.contains("@") {
            return canonicalName
        }
        return canonicalName
    }

    var debugIdentifierSummary: String {
        "subject=\(subject) listRID=\(listRID) listID=\(listID) rootEmailID=\(rootEmailID) rootMessageID=\(rootMessageID) groupingKey=\(threadGroupingKey)"
    }

    var threadGroupingKey: String {
        "\(listRID)#\(displaySubject.lowercased())"
    }

    private static func normalizedSubject(from subject: String) -> String {
        let collapsedWhitespace = subject
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let pattern = #"^(?:(?:re|fwd?)\s*:\s*)+"#
        return collapsedWhitespace.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}

struct InboxMessage: Identifiable, Hashable, Sendable {
    let id: Int
    let author: Entity
    let date: Date
    let subject: String
    let body: String
    let senderDisplayName: String
    let senderEmailAddress: String?
    let isPatch: Bool
    let contentBlocks: [InboxMessageContentBlock]
    let rawMessageURL: URL?
}

enum InboxMessageContentBlock: Hashable, Sendable {
    case plainText(String)
    case diff(String)
}

struct InboxThreadDetail: Sendable {
    let id: String
    let rootEmailID: Int
    let rootMessageID: String
    let subject: String
    let author: Entity
    let lastActivityAt: Date
    let mailto: String?
    let listID: Int
    let listRID: String
    let listName: String
    let listOwner: Entity
    let messageCount: Int?
    let messages: [InboxMessage]

    var listDisplayName: String {
        "\(listOwner.canonicalName)/\(listName)"
    }
}

extension InboxThreadDetail {
    var replyRecipient: String {
        "\(listOwner.canonicalName)/\(listName)@lists.sr.ht"
    }

    var replySubject: String {
        subject.lowercased().hasPrefix("re:") ? subject : "Re: \(subject)"
    }

    var displaySubject: String {
        InboxThreadSummary(
            rootEmailID: rootEmailID,
            rootMessageID: rootMessageID,
            threadRootEmailIDs: [rootEmailID],
            threadRootMessageIDs: [rootMessageID],
            listID: listID,
            listRID: listRID,
            listName: listName,
            listOwner: listOwner,
            subject: subject,
            latestSender: author,
            lastActivityAt: lastActivityAt,
            messageCount: messageCount,
            repo: nil,
            containsPatch: messages.contains(where: \.isPatch),
            isUnread: false
        ).displaySubject
    }
}

struct MailComposeDraft: Sendable {
    let recipients: [String]
    let ccRecipients: [String]
    let subject: String
    let body: String

    var id: String {
        ([subject] + recipients + ccRecipients).joined(separator: "|")
    }
}

extension MailComposeDraft: Identifiable {}

struct InboxMailingListReference: Decodable, Sendable, Hashable, Identifiable {
    let id: Int
    let rid: String
    let name: String
    let owner: Entity
}

struct InboxPatchPreview: Decodable, Sendable, Hashable {
    let subject: String?
}

enum InboxReadStateStore {
    private static let key = "InboxThreadLastViewed"

    static func lastViewedAt(for threadID: String, defaults: UserDefaults = .standard) -> Date? {
        guard let dictionary = defaults.dictionary(forKey: key) as? [String: TimeInterval],
              let timestamp = dictionary[threadID] else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    static func markViewed(_ date: Date, for threadID: String, defaults: UserDefaults = .standard) {
        var dictionary = defaults.dictionary(forKey: key) as? [String: TimeInterval] ?? [:]
        dictionary[threadID] = date.timeIntervalSince1970
        defaults.set(dictionary, forKey: key)
    }

    static func markUnread(for threadID: String, defaults: UserDefaults = .standard) {
        var dictionary = defaults.dictionary(forKey: key) as? [String: TimeInterval] ?? [:]
        dictionary.removeValue(forKey: threadID)
        defaults.set(dictionary, forKey: key)
    }

    static func isUnread(threadID: String, lastActivityAt: Date, defaults: UserDefaults = .standard) -> Bool {
        guard let lastViewedAt = lastViewedAt(for: threadID, defaults: defaults) else {
            return true
        }
        return lastActivityAt > lastViewedAt
    }
}
