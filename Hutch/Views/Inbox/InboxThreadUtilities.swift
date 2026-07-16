import Foundation

enum InboxThreadUtilities {
    nonisolated static func deriveRepositoryName(from listName: String) -> String? {
        let separators = ["-devel", "-patches", "-dev", ".patches"]
        for separator in separators where listName.hasSuffix(separator) {
            return String(listName.dropLast(separator.count))
        }
        return nil
    }

    /// Splits an email body into its commit message and diff, so patch mail can be
    /// rendered as prose plus a diff rather than one undifferentiated blob.
    ///
    /// Shared by the inbox thread view and patchset review: sr.ht's `Patch` type
    /// carries no diff, so the diff has to be recovered from the email body.
    nonisolated static func segmentMessageBody(_ body: String, isPatch: Bool) -> [InboxMessageContentBlock] {
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

    nonisolated static func actualDiffStartIndex(in lines: [String]) -> Int? {
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

    nonisolated static func isEmailSignatureSeparator(_ line: String) -> Bool {
        line == "-- " || line == "--"
    }

    nonisolated static func normalizeLineEndings(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
