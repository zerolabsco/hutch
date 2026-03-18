import Foundation

extension Int {
    /// Human-readable byte size string (e.g. "1.2 MB", "340 KB").
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
