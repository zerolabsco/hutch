import Foundation

enum InboxThreadUtilities {
    nonisolated static func deriveRepositoryName(from listName: String) -> String? {
        let separators = ["-devel", "-patches", "-dev", ".patches"]
        for separator in separators where listName.hasSuffix(separator) {
            return String(listName.dropLast(separator.count))
        }
        return nil
    }
}
